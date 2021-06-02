/*
 * Copyright (c) 2018-2021, NVIDIA CORPORATION.
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

#include <cudf/binaryop.hpp>
#include <cudf/null_mask.hpp>

#include <rmm/cuda_stream_view.hpp>

#include <optional>

namespace cudf {
// Forward declarations
class column_device_view;
class mutable_column_device_view;

namespace binops {
namespace detail {
/**
 * @brief Computes output valid mask for op between a column and a scalar
 */
rmm::device_buffer scalar_col_valid_mask_and(column_view const& col,
                                             scalar const& s,
                                             rmm::cuda_stream_view stream,
                                             rmm::mr::device_memory_resource* mr);
}  // namespace detail

/**
 * @brief Does the binop need to know if an operand is null/invalid to perform special
 * processing?
 */
inline bool is_null_dependent(binary_operator op)
{
  return op == binary_operator::NULL_EQUALS || op == binary_operator::NULL_MIN ||
         op == binary_operator::NULL_MAX;
}

namespace compiled {

/**
 * @brief Performs a binary operation between a string scalar and a string
 * column.
 *
 * The output contains the result of op(lhs, rhs[i]) for all 0 <= i < rhs.size()
 * The scalar is the left operand and the column elements are the right operand.
 * This distinction is significant in case of non-commutative binary operations
 *
 * Regardless of the operator, the validity of the output value is the logical
 * AND of the validity of the two operands
 *
 * @param lhs         The left operand string scalar
 * @param rhs         The right operand string column
 * @param output_type The desired data type of the output column
 * @param mr          Device memory resource used to allocate the returned column's device memory
 * @param stream      CUDA stream used for device memory operations and kernel launches.
 * @return std::unique_ptr<column> Output column
 */
std::unique_ptr<column> binary_operation(
  scalar const& lhs,
  column_view const& rhs,
  binary_operator op,
  data_type output_type,
  rmm::cuda_stream_view stream        = rmm::cuda_stream_default,
  rmm::mr::device_memory_resource* mr = rmm::mr::get_current_device_resource());

/**
 * @brief Performs a binary operation between a string column and a string
 * scalar.
 *
 * The output contains the result of op(lhs[i], rhs) for all 0 <= i < lhs.size()
 * The column elements are the left operand and the scalar is the right operand.
 * This distinction is significant in case of non-commutative binary operations
 *
 * Regardless of the operator, the validity of the output value is the logical
 * AND of the validity of the two operands
 *
 * @param lhs         The left operand string column
 * @param rhs         The right operand string scalar
 * @param output_type The desired data type of the output column
 * @param mr          Device memory resource used to allocate the returned column's device memory
 * @param stream      CUDA stream used for device memory operations and kernel launches.
 * @return std::unique_ptr<column> Output column
 */
std::unique_ptr<column> binary_operation(
  column_view const& lhs,
  scalar const& rhs,
  binary_operator op,
  data_type output_type,
  rmm::cuda_stream_view stream        = rmm::cuda_stream_default,
  rmm::mr::device_memory_resource* mr = rmm::mr::get_current_device_resource());

/**
 * @brief Performs a binary operation between two string columns.
 *
 * @note The sizes of @p lhs and @p rhs should be the same
 *
 * The output contains the result of op(lhs[i], rhs[i]) for all 0 <= i <
 * lhs.size()
 *
 * Regardless of the operator, the validity of the output value is the logical
 * AND of the validity of the two operands
 *
 * @param lhs         The left operand string column
 * @param rhs         The right operand string column
 * @param output_type The desired data type of the output column
 * @param mr          Device memory resource used to allocate the returned column's device memory
 * @param stream      CUDA stream used for device memory operations and kernel launches.
 * @return std::unique_ptr<column> Output column
 */
std::unique_ptr<column> binary_operation(
  column_view const& lhs,
  column_view const& rhs,
  binary_operator op,
  data_type output_type,
  rmm::cuda_stream_view stream        = rmm::cuda_stream_default,
  rmm::mr::device_memory_resource* mr = rmm::mr::get_current_device_resource());

void binary_operation(mutable_column_view& out,
                      column_view const& lhs,
                      column_view const& rhs,
                      binary_operator op,
                      rmm::cuda_stream_view stream);
// Defined in util.cpp
std::optional<data_type> get_common_type(data_type out, data_type lhs, data_type rhs);
bool is_supported_operation(data_type out, data_type lhs, data_type rhs, binary_operator op);

// Defined in individual .cu files.
template <class BinaryOperator>
void apply_binary_op(mutable_column_device_view&,
                     column_device_view const&,
                     column_device_view const&,
                     rmm::cuda_stream_view stream);
void dispatch_comparison_op(mutable_column_device_view& outd,
                            column_device_view const& lhsd,
                            column_device_view const& rhsd,
                            binary_operator op,
                            rmm::cuda_stream_view stream);
void dispatch_equality_op(mutable_column_device_view& outd,
                          column_device_view const& lhsd,
                          column_device_view const& rhsd,
                          binary_operator op,
                          rmm::cuda_stream_view stream);
}  // namespace compiled
}  // namespace binops
}  // namespace cudf
