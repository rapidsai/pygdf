/*
 * Copyright (c) 2020-2021, NVIDIA CORPORATION.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
#pragma once

#include <cudf/ast/operators.hpp>
#include <cudf/scalar/scalar.hpp>
#include <cudf/scalar/scalar_device_view.cuh>
#include <cudf/table/table_view.hpp>
#include <cudf/types.hpp>
#include <cudf/utilities/error.hpp>

namespace cudf {
namespace ast {

// Forward declaration
enum class table_reference;
class literal;
class column_reference;
class expression;

namespace detail {

/**
 * @brief Enum defining data reference types used by a node.
 *
 * This enum is device-specific. For instance, intermediate data references are generated by the
 * linearization process but cannot be explicitly created by the user.
 */
enum class device_data_reference_type {
  COLUMN,       // A value in a table column
  LITERAL,      // A literal value
  INTERMEDIATE  // An internal temporary value
};

/**
 * @brief A device data reference describes a source of data used by a node.
 *
 * This is a POD class used to create references describing data type and locations for consumption
 * by the `row_evaluator`.
 */
struct alignas(8) device_data_reference {
  device_data_reference(device_data_reference_type reference_type,
                        cudf::data_type data_type,
                        cudf::size_type data_index,
                        table_reference table_source);

  device_data_reference(device_data_reference_type reference_type,
                        cudf::data_type data_type,
                        cudf::size_type data_index);

  const device_data_reference_type reference_type;  // Source of data
  const cudf::data_type data_type;                  // Type of data
  const cudf::size_type data_index;                 // The column index of a table, index of a
                                                    // literal, or index of an intermediate
  const table_reference table_source;

  inline bool operator==(const device_data_reference& rhs) const
  {
    return std::tie(data_index, reference_type, table_source) ==
           std::tie(rhs.data_index, rhs.reference_type, rhs.table_source);
  }
};

// Forward declaration
class linearizer;

/**
 * @brief A generic node that can be evaluated to return a value.
 *
 * This class is a part of a "visitor" pattern with the `linearizer` class.
 * Nodes inheriting from this class can accept visitors.
 */
struct node {
  virtual cudf::size_type accept(detail::linearizer& visitor) const = 0;
};

/**
 * @brief The linearizer traverses an abstract syntax tree to prepare for execution on the device.
 *
 * This class is part of a "visitor" pattern with the `node` class.
 *
 * This class does pre-processing work on the host, validating operators and operand data types. It
 * traverses downward from a root node in a depth-first fashion, capturing information about
 * the nodes and constructing vectors of information that are later used by the device for
 * evaluating the abstract syntax tree as a "linear" list of operators whose input dependencies are
 * resolved into intermediate data storage in shared memory.
 */
class linearizer {
 public:
  /**
   * @brief Construct a new linearizer object
   *
   * @param expr The expression to create an evaluable linearizer for.
   * @param left The left table used for evaluating the abstract syntax tree.
   * @param right The right table used for evaluating the abstract syntax tree.
   */
  linearizer(detail::node const& expr, cudf::table_view left, cudf::table_view right)
    : _left(left), _right(right), _node_count(0), _intermediate_counter()
  {
    expr.accept(*this);
  }

  /**
   * @brief Construct a new linearizer object
   *
   * @param expr The expression to create an evaluable linearizer for.
   * @param table The table used for evaluating the abstract syntax tree.
   */
  linearizer(detail::node const& expr, cudf::table_view table)
    : _left(table), _right(table), _node_count(0), _intermediate_counter()
  {
    expr.accept(*this);
  }

  /**
   * @brief Get the root data type of the abstract syntax tree.
   *
   * @return cudf::data_type
   */
  cudf::data_type root_data_type() const;

  /**
   * @brief Get the maximum number of intermediates stored by the abstract syntax tree.
   *
   * @return cudf::size_type
   */
  cudf::size_type intermediate_count() const { return _intermediate_counter.get_max_used(); }

  /**
   * @brief Get the device data references.
   *
   * @return std::vector<detail::device_data_reference>
   */
  std::vector<detail::device_data_reference> const& data_references() const
  {
    return _data_references;
  }

  /**
   * @brief Get the operators.
   *
   * @return std::vector<ast_operator>
   */
  std::vector<ast_operator> const& operators() const { return _operators; }

  /**
   * @brief Get the operator source indices.
   *
   * @return std::vector<cudf::size_type>
   */
  std::vector<cudf::size_type> const& operator_source_indices() const
  {
    return _operator_source_indices;
  }

  /**
   * @brief Get the literal device views.
   *
   * @return std::vector<cudf::detail::fixed_width_scalar_device_view_base>
   */
  std::vector<cudf::detail::fixed_width_scalar_device_view_base> const& literals() const
  {
    return _literals;
  }

  /**
   * @brief Visit a literal node.
   *
   * @param expr Literal node.
   * @return cudf::size_type Index of device data reference for the node.
   */
  cudf::size_type visit(literal const& expr);

  /**
   * @brief Visit a column reference node.
   *
   * @param expr Column reference node.
   * @return cudf::size_type Index of device data reference for the node.
   */
  cudf::size_type visit(column_reference const& expr);

  /**
   * @brief Visit an expression node.
   *
   * @param expr Expression node.
   * @return cudf::size_type Index of device data reference for the node.
   */
  cudf::size_type visit(expression const& expr);

  /**
   * @brief Internal class used to track the utilization of intermediate storage locations.
   *
   * As nodes are being evaluated, they may generate "intermediate" data that is immediately
   * consumed. Rather than manifesting this data in global memory, we can store intermediates of any
   * fixed width type (up to 8 bytes) by placing them in shared memory. This class helps to track
   * the number and indices of intermediate data in shared memory using a give-take model. Locations
   * in shared memory can be "taken" and used for storage, "given back," and then later re-used.
   * This aims to minimize the maximum amount of shared memory needed at any point during the
   * evaluation.
   *
   */
  class intermediate_counter {
   public:
    intermediate_counter() : used_values(), max_used(0) {}
    cudf::size_type take();
    void give(cudf::size_type value);
    cudf::size_type get_max_used() const { return max_used; }

   private:
    cudf::size_type find_first_missing() const;
    std::vector<cudf::size_type> used_values;
    cudf::size_type max_used;
  };

 private:
  std::vector<cudf::size_type> visit_operands(
    std::vector<std::reference_wrapper<const node>> operands);
  cudf::size_type add_data_reference(detail::device_data_reference data_ref);

  // State information about the "linearized" GPU execution plan
  cudf::table_view const& _left;
  cudf::table_view const& _right;
  cudf::size_type _node_count;
  intermediate_counter _intermediate_counter;
  std::vector<detail::device_data_reference> _data_references;
  std::vector<ast_operator> _operators;
  std::vector<cudf::size_type> _operator_source_indices;
  std::vector<cudf::detail::fixed_width_scalar_device_view_base> _literals;
};

}  // namespace detail

}  // namespace ast

}  // namespace cudf
