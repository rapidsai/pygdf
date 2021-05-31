/*
 * Copyright (c) 2021, NVIDIA CORPORATION.
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

#include "binary_ops.hpp"
#include "operation.cuh"

#include <rmm/cuda_stream_view.hpp>
#include <rmm/exec_policy.hpp>

namespace cudf {
namespace binops {
namespace compiled {

// Functors to launch only defined operations.

/**
 * @brief Functor to launch only defined operations with common type.
 *
 * @tparam BinaryOperator binary operator functor
 */
template <typename BinaryOperator, bool store_as_result = false>
struct ops_wrapper {
  mutable_column_device_view& out;
  column_device_view const& lhs;
  column_device_view const& rhs;
  template <typename TypeCommon>
  __device__ void operator()(size_type i)
  {
    if constexpr (std::is_invocable_v<BinaryOperator, TypeCommon, TypeCommon>) {
      TypeCommon x = type_dispatcher(lhs.type(), type_casted_accessor<TypeCommon>{}, i, lhs);
      TypeCommon y = type_dispatcher(rhs.type(), type_casted_accessor<TypeCommon>{}, i, rhs);
      auto result  = BinaryOperator{}.template operator()<TypeCommon, TypeCommon>(x, y);
      if constexpr (store_as_result)
        out.element<decltype(result)>(i) = result;
      else
        type_dispatcher(out.type(), typed_casted_writer<decltype(result)>{}, i, out, result);
    }
    (void)i;
  }
};

// Specialize for NullEquals
template <>
struct ops_wrapper<ops::NullEquals, true> {
  mutable_column_device_view& out;
  column_device_view const& lhs;
  column_device_view const& rhs;
  template <typename TypeCommon>
  __device__ void operator()(size_type i)
  {
    if constexpr (std::is_invocable_v<ops::NullEquals, TypeCommon, TypeCommon>) {
      TypeCommon x = type_dispatcher(lhs.type(), type_casted_accessor<TypeCommon>{}, i, lhs);
      TypeCommon y = type_dispatcher(rhs.type(), type_casted_accessor<TypeCommon>{}, i, rhs);
      auto result  = ops::NullEquals{}.template operator()<TypeCommon, TypeCommon>(
        x, y, lhs.is_valid(i), rhs.is_valid(i));
      out.element<decltype(result)>(i) = result;
    }
    (void)i;
  }
};

/**
 * @brief Functor to launch only defined operations without common type.
 *
 * @tparam BinaryOperator binary operator functor
 */
template <typename BinaryOperator, bool store_as_result = false>
struct ops2_wrapper {
  mutable_column_device_view& out;
  column_device_view const& lhs;
  column_device_view const& rhs;
  template <typename TypeLhs, typename TypeRhs>
  __device__ void operator()(size_type i)
  {
    if constexpr (!has_common_type_v<TypeLhs, TypeRhs> and
                  std::is_invocable_v<BinaryOperator, TypeLhs, TypeRhs>) {
      TypeLhs x   = lhs.element<TypeLhs>(i);
      TypeRhs y   = rhs.element<TypeRhs>(i);
      auto result = BinaryOperator{}.template operator()<TypeLhs, TypeRhs>(x, y);
      if constexpr (store_as_result)
        out.element<decltype(result)>(i) = result;
      else
        type_dispatcher(out.type(), typed_casted_writer<decltype(result)>{}, i, out, result);
    }
    (void)i;
  }
};

// Specialize for NullEquals
template <>
struct ops2_wrapper<ops::NullEquals, true> {
  mutable_column_device_view& out;
  column_device_view const& lhs;
  column_device_view const& rhs;
  template <typename TypeLhs, typename TypeRhs>
  __device__ void operator()(size_type i)
  {
    if constexpr (!has_common_type_v<TypeLhs, TypeRhs> and
                  std::is_invocable_v<ops::NullEquals, TypeLhs, TypeRhs>) {
      TypeLhs x   = lhs.element<TypeLhs>(i);
      TypeRhs y   = rhs.element<TypeRhs>(i);
      auto result = ops::NullEquals{}.template operator()<TypeLhs, TypeRhs>(
        x, y, lhs.is_valid(i), rhs.is_valid(i));
      out.element<decltype(result)>(i) = result;
    }
    (void)i;
  }
};

/**
 * @brief Functor which does single, and double type dispatcher in device code
 *
 * single type dispatcher for lhs and rhs with common types.
 * double type dispatcher for lhs and rhs without common types.
 *
 * @tparam BinaryOperator binary operator functor
 */
template <class BinaryOperator, bool store_as_result = false>
struct device_type_dispatcher {
  //, OperatorType type)
  // (type == OperatorType::Direct ? operator_name : 'R' + operator_name);
  mutable_column_device_view out;
  column_device_view lhs;
  column_device_view rhs;
  std::optional<data_type> common_data_type;

  __device__ void operator()(size_type i)
  {
    if (common_data_type) {
      type_dispatcher(
        *common_data_type, ops_wrapper<BinaryOperator, store_as_result>{out, lhs, rhs}, i);
    } else {
      double_type_dispatcher(
        lhs.type(), rhs.type(), ops2_wrapper<BinaryOperator, store_as_result>{out, lhs, rhs}, i);
    }
  }
};

/**
 * @brief Deploys single type or double type dispatcher that runs binary operation on each element
 * of @p lhsd and @p rhsd columns.
 *
 * This template is instantiated for each binary operator.
 *
 * @tparam BinaryOperator Binary operator functor
 * @param outd mutable device view of output column
 * @param lhsd device view of left operand column
 * @param rhsd device view of right operand column
 * @param stream CUDA stream used for device memory operations
 */
template <class BinaryOperator>
void compiled_binary_op(mutable_column_device_view& outd,
                        column_device_view const& lhsd,
                        column_device_view const& rhsd,
                        rmm::cuda_stream_view stream)
{
  auto common_dtype = get_common_type(outd.type(), lhsd.type(), rhsd.type());

  // Create binop functor instance
  auto binop_func = device_type_dispatcher<BinaryOperator>{outd, lhsd, rhsd, common_dtype};
  // Execute it on every element
  thrust::for_each(rmm::exec_policy(stream),
                   thrust::make_counting_iterator<size_type>(0),
                   thrust::make_counting_iterator<size_type>(outd.size()),
                   binop_func);
  //"cudf::binops::jit::kernel_v_v")  //TODO v_s, s_v.
}

}  // namespace compiled
}  // namespace binops
}  // namespace cudf
