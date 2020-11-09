/*
 * Copyright (c) 2019, NVIDIA CORPORATION.
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

#include <cudf/column/column.hpp>
#include <cudf/detail/nvtx/ranges.hpp>
#include <cudf/detail/unary.hpp>
#include <cudf/fixed_point/fixed_point.hpp>
#include <cudf/null_mask.hpp>
#include <cudf/unary.hpp>
#include <cudf/utilities/traits.hpp>

#include <rmm/thrust_rmm_allocator.h>

namespace cudf {
namespace detail {
template <typename _TargetT>
struct unary_cast {
  template <typename SourceT,
            typename TargetT                                          = _TargetT,
            typename std::enable_if_t<(cudf::is_numeric<SourceT>() &&
                                       cudf::is_numeric<TargetT>())>* = nullptr>
  CUDA_DEVICE_CALLABLE TargetT operator()(SourceT const element)
  {
    return static_cast<TargetT>(element);
  }

  template <typename SourceT,
            typename TargetT                                            = _TargetT,
            typename std::enable_if_t<(cudf::is_timestamp<SourceT>() &&
                                       cudf::is_timestamp<TargetT>())>* = nullptr>
  CUDA_DEVICE_CALLABLE TargetT operator()(SourceT const element)
  {
    // Convert source tick counts into target tick counts without blindly truncating them
    // by dividing the respective duration time periods (which may not work for time before
    // UNIX epoch)
    return TargetT{simt::std::chrono::floor<TargetT::duration>(element.time_since_epoch())};
  }

  template <typename SourceT,
            typename TargetT                                           = _TargetT,
            typename std::enable_if_t<(cudf::is_duration<SourceT>() &&
                                       cudf::is_duration<TargetT>())>* = nullptr>
  CUDA_DEVICE_CALLABLE TargetT operator()(SourceT const element)
  {
    return TargetT{simt::std::chrono::floor<TargetT>(element)};
  }

  template <typename SourceT,
            typename TargetT                                         = _TargetT,
            typename std::enable_if_t<cudf::is_numeric<SourceT>() &&
                                      cudf::is_duration<TargetT>()>* = nullptr>
  CUDA_DEVICE_CALLABLE TargetT operator()(SourceT const element)
  {
    return TargetT{static_cast<typename TargetT::rep>(element)};
  }

  template <typename SourceT,
            typename TargetT                                           = _TargetT,
            typename std::enable_if_t<(cudf::is_timestamp<SourceT>() &&
                                       cudf::is_duration<TargetT>())>* = nullptr>
  CUDA_DEVICE_CALLABLE TargetT operator()(SourceT const element)
  {
    return TargetT{simt::std::chrono::floor<TargetT>(element.time_since_epoch())};
  }

  template <typename SourceT,
            typename TargetT                                        = _TargetT,
            typename std::enable_if_t<cudf::is_duration<SourceT>() &&
                                      cudf::is_numeric<TargetT>()>* = nullptr>
  CUDA_DEVICE_CALLABLE TargetT operator()(SourceT const element)
  {
    return static_cast<TargetT>(element.count());
  }

  template <typename SourceT,
            typename TargetT                                            = _TargetT,
            typename std::enable_if_t<(cudf::is_duration<SourceT>() &&
                                       cudf::is_timestamp<TargetT>())>* = nullptr>
  CUDA_DEVICE_CALLABLE TargetT operator()(SourceT const element)
  {
    return TargetT{simt::std::chrono::floor<TargetT::duration>(element)};
  }
};

template <typename _FixedPointT, typename _TargetT>
struct fixed_point_unary_cast {
  numeric::scale_type scale;
  using DeviceT = device_storage_type_t<_FixedPointT>;
  template <typename FixedPointT                                      = _FixedPointT,
            typename TargetT                                          = _TargetT,
            typename std::enable_if_t<(cudf::is_fixed_point<_FixedPointT>() &&
                                       cudf::is_numeric<TargetT>())>* = nullptr>
  CUDA_DEVICE_CALLABLE TargetT operator()(DeviceT const element)
  {
    auto const fp = FixedPointT{numeric::scaled_integer<DeviceT>{element, scale}};
    return static_cast<TargetT>(fp);
  }
};

// template <typename From, typename To>
// constexpr inline auto is_supported_cast()
// {
//   return
//     // Enable
//     ((is_fixed_width<To>() && not is_fixed_point<To>()) ||  //
//      (is_fixed_point<From>() && is_floating_point<To>())) &&
//     // Disable
//     not(is_timestamp<From>() && is_numeric<To>()) &&  //
//     not(is_timestamp<To>() && is_numeric<From>()) &&
//     not(is_fixed_point<To>() && is_fixed_point<From>());
// }

// clang-format off
template <typename From, typename To>
constexpr inline auto is_supported_non_fixed_point_cast()
{
  // Disallow conversions between timestamps and numeric
  return (cudf::is_numeric    <From>() && cudf::is_numeric       <To>()) ||
         (cudf::is_timestamp  <From>() && cudf::is_timestamp     <To>()) ||
         (cudf::is_duration   <From>() && cudf::is_duration      <To>()) ||
         (cudf::is_numeric    <From>() && cudf::is_duration      <To>()) ||
         (cudf::is_timestamp  <From>() && cudf::is_duration      <To>()) ||
         (cudf::is_duration   <From>() && cudf::is_numeric       <To>()) ||
         (cudf::is_duration   <From>() && cudf::is_timestamp     <To>());
}

template <typename From, typename To>
constexpr inline auto is_supported_fixed_point_cast()
{
  // TODO add more
  return (cudf::is_fixed_point<From>() && cudf::is_numeric<To>());
}
// clang-format on

template <typename From, typename To>
constexpr inline auto is_supported_cast()
{
  return is_supported_non_fixed_point_cast<From, To>() || is_supported_fixed_point_cast<From, To>();
}

template <typename SourceT>
struct dispatch_unary_cast_to {
  column_view input;

  dispatch_unary_cast_to(column_view inp) : input(inp) {}

  template <
    typename TargetT,
    typename std::enable_if_t<is_supported_non_fixed_point_cast<SourceT, TargetT>()>* = nullptr>
  std::unique_ptr<column> operator()(data_type type,
                                     rmm::mr::device_memory_resource* mr,
                                     cudaStream_t stream)
  {
    auto const size = input.size();
    auto output     = std::make_unique<column>(type,
                                           size,
                                           rmm::device_buffer{size * cudf::size_of(type), 0, mr},
                                           copy_bitmask(input, 0, mr),
                                           input.null_count());

    mutable_column_view output_mutable = *output;

    thrust::transform(rmm::exec_policy(stream)->on(stream),
                      input.begin<SourceT>(),
                      input.end<SourceT>(),
                      output_mutable.begin<TargetT>(),
                      unary_cast<TargetT>{});

    return output;
  }

  template <typename TargetT,
            typename std::enable_if_t<is_supported_fixed_point_cast<SourceT, TargetT>()>* = nullptr>
  std::unique_ptr<column> operator()(data_type type,
                                     rmm::mr::device_memory_resource* mr,
                                     cudaStream_t stream)
  {
    auto const size = input.size();
    auto output     = std::make_unique<column>(type,
                                           size,
                                           rmm::device_buffer{size * cudf::size_of(type), 0, mr},
                                           copy_bitmask(input, 0, mr),
                                           input.null_count());

    mutable_column_view output_mutable = *output;

    using Type       = device_storage_type_t<SourceT>;
    auto const scale = numeric::scale_type{input.type().scale()};

    thrust::transform(rmm::exec_policy(stream)->on(stream),
                      input.begin<Type>(),
                      input.end<Type>(),
                      output_mutable.begin<TargetT>(),
                      fixed_point_unary_cast<SourceT, TargetT>{scale});

    return output;
  }

  template <typename TargetT,
            typename std::enable_if_t<not is_supported_cast<SourceT, TargetT>()>* = nullptr>
  std::unique_ptr<column> operator()(data_type type,
                                     rmm::mr::device_memory_resource* mr,
                                     cudaStream_t stream)
  {
    if (!cudf::is_fixed_width<TargetT>())
      CUDF_FAIL("Column type must be numeric or chrono or decimal32/64");
    else if (cudf::is_fixed_point<SourceT>())
      CUDF_FAIL("Currently only decimal32/64 to floating point/integral is supported");
    else if (cudf::is_timestamp<SourceT>() && is_numeric<TargetT>())
      CUDF_FAIL("Timestamps can be created only from duration");
    else
      CUDF_FAIL("Timestamps cannot be converted to numeric without converting it to a duration");
  }
};

struct dispatch_unary_cast_from {
  column_view input;

  dispatch_unary_cast_from(column_view inp) : input(inp) {}

  template <typename T, typename std::enable_if_t<cudf::is_fixed_width<T>()>* = nullptr>
  std::unique_ptr<column> operator()(data_type type,
                                     rmm::mr::device_memory_resource* mr,
                                     cudaStream_t stream)
  {
    return type_dispatcher(type, dispatch_unary_cast_to<T>{input}, type, mr, stream);
  }

  template <typename T, typename std::enable_if_t<!cudf::is_fixed_width<T>()>* = nullptr>
  std::unique_ptr<column> operator()(data_type type,
                                     rmm::mr::device_memory_resource* mr,
                                     cudaStream_t stream)
  {
    CUDF_FAIL("Column type must be numeric or chrono or decimal32/64");
  }
};

std::unique_ptr<column> cast(column_view const& input,
                             data_type type,
                             rmm::mr::device_memory_resource* mr,
                             cudaStream_t stream)
{
  CUDF_EXPECTS(is_fixed_width(type), "Unary cast type must be fixed-width.");

  return type_dispatcher(input.type(), detail::dispatch_unary_cast_from{input}, type, mr, stream);
}

}  // namespace detail

std::unique_ptr<column> cast(column_view const& input,
                             data_type type,
                             rmm::mr::device_memory_resource* mr)
{
  CUDF_FUNC_RANGE();
  return detail::cast(input, type, mr);
}

}  // namespace cudf
