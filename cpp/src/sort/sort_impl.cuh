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

#include <cudf/column/column_factories.hpp>
#include <cudf/detail/gather.hpp>
#include <cudf/table/row_operators.cuh>
#include <cudf/table/table_device_view.cuh>
#include <cudf/utilities/error.hpp>

#include <rmm/cuda_stream_view.hpp>
#include <rmm/device_uvector.hpp>
#include <rmm/exec_policy.hpp>

#include <cub/cub.cuh>

#include <thrust/sequence.h>
#include <thrust/sort.h>

namespace cudf {
namespace detail {

/**
 * @brief Type-dispatched functor for sorting a single column.
 */
template <bool stable = false>
struct single_column_sort_fn {
  /**
   * @brief Comparator functor needed for stable sort.
   */
  template <typename T>
  struct comparator {
    __device__ bool operator()(size_type lhs, size_type rhs)
    {
      if (has_nulls) {
        bool lhs_null{d_column.is_null(lhs)};
        bool rhs_null{d_column.is_null(rhs)};
        if (lhs_null || rhs_null) {
          if (!ascending) thrust::swap(lhs_null, rhs_null);
          return (null_precedence == cudf::null_order::BEFORE ? !rhs_null : !lhs_null);
        }
      }
      auto const lh_elem = d_column.element<T>(lhs);
      auto const rh_elem = d_column.element<T>(rhs);
      return ascending ? lh_elem < rh_elem : rh_elem < lh_elem;
    }
    column_device_view const d_column;
    bool has_nulls;
    bool ascending;
    null_order null_precedence{};
  };

  /**
   * @brief Sorts numeric columns using the CUB Radix Sort.
   *
   * @param input Column to sort
   * @param indices Output sorted indices
   * @param ascending True if sort order is ascending
   * @param stream CUDA stream used for device memory operations and kernel launches
   */
  template <typename T, typename std::enable_if_t<cudf::is_numeric<T>()>* = nullptr>
  void fast_numeric_sort(column_view const& input,
                         mutable_column_view& indices,
                         bool ascending,
                         rmm::cuda_stream_view stream)
  {
    // A non-stable sort on a numeric column with no nulls can use the radix sort but
    // requires making a copy of the input data and the indices.
    auto temp_col = std::make_unique<column>(input, stream);
    auto d_col    = temp_col->mutable_view();
    auto temp_seq = std::make_unique<column>(indices, stream);
    auto d_seq    = temp_seq->view();
    if (ascending) {
      size_t tbytes = 0;
      cub::DeviceRadixSort::SortPairs(nullptr,
                                      tbytes,
                                      input.begin<T>(),
                                      d_col.begin<T>(),
                                      d_seq.begin<size_type>(),
                                      indices.begin<size_type>(),
                                      input.size(),
                                      0,
                                      sizeof(T) * 8,
                                      stream.value());
      rmm::device_uvector<int8_t> buf(tbytes, stream);
      cub::DeviceRadixSort::SortPairs(buf.data(),
                                      tbytes,
                                      input.begin<T>(),
                                      d_col.begin<T>(),
                                      d_seq.begin<size_type>(),
                                      indices.begin<size_type>(),
                                      input.size(),
                                      0,
                                      sizeof(T) * 8,
                                      stream.value());
    } else {
      size_t tbytes = 0;
      cub::DeviceRadixSort::SortPairsDescending(nullptr,
                                                tbytes,
                                                input.begin<T>(),
                                                d_col.begin<T>(),
                                                d_seq.begin<size_type>(),
                                                indices.begin<size_type>(),
                                                input.size(),
                                                0,
                                                sizeof(T) * 8,
                                                stream.value());
      rmm::device_uvector<int8_t> buf(tbytes, stream);
      cub::DeviceRadixSort::SortPairsDescending(buf.data(),
                                                tbytes,
                                                input.begin<T>(),
                                                d_col.begin<T>(),
                                                d_seq.begin<size_type>(),
                                                indices.begin<size_type>(),
                                                input.size(),
                                                0,
                                                sizeof(T) * 8,
                                                stream.value());
    }
  }
  template <typename T, typename std::enable_if_t<!cudf::is_numeric<T>()>* = nullptr>
  void fast_numeric_sort(column_view const&, mutable_column_view&, bool, rmm::cuda_stream_view)
  {
    CUDF_FAIL("Only numeric types are suitable for radix sorting");
  }

  template <typename T, typename std::enable_if_t<cudf::is_numeric<T>()>* = nullptr>
  void fast_numeric_stable_sort(column_view const& input,
                                mutable_column_view& indices,
                                rmm::cuda_stream_view stream)
  {
    auto temp_col = std::make_unique<column>(input, stream);
    auto d_col    = temp_col->mutable_view();
    thrust::stable_sort_by_key(
      rmm::exec_policy(stream), d_col.begin<T>(), d_col.end<T>(), indices.begin<size_type>());
  }
  template <typename T, typename std::enable_if_t<!cudf::is_numeric<T>()>* = nullptr>
  void fast_numeric_stable_sort(column_view const&, mutable_column_view&, rmm::cuda_stream_view)
  {
    CUDF_FAIL("Only numeric types are suitable for radix sorting");
  }

  /**
   * @brief Sorts a single column with a relationally comparable type.
   *
   * This includes numeric, timestamp, duration, and string types.
   *
   * @param input Column to sort
   * @param indices Output sorted indices
   * @param ascending True if sort order is ascending
   * @param null_precedence How null rows are to be ordered
   * @param stream CUDA stream used for device memory operations and kernel launches
   */
  template <typename T,
            typename std::enable_if_t<cudf::is_relationally_comparable<T, T>()>* = nullptr>
  void operator()(column_view const& input,
                  mutable_column_view& indices,
                  bool ascending,
                  null_order null_precedence,
                  rmm::cuda_stream_view stream)
  {
    if (stable) {
      if (!ascending || input.has_nulls() || !cudf::is_numeric<T>()) {
        auto keys = column_device_view::create(input, stream);
        thrust::stable_sort(rmm::exec_policy(stream),
                            indices.begin<size_type>(),
                            indices.end<size_type>(),
                            comparator<T>{*keys, input.has_nulls(), ascending, null_precedence});
      } else {
        fast_numeric_stable_sort<T>(input, indices, stream);
      }
    } else {
      // column with nulls or non-numeric column will also use a comparator
      if (input.has_nulls() || !cudf::is_numeric<T>()) {
        auto keys = column_device_view::create(input, stream);
        thrust::sort(rmm::exec_policy(stream),
                     indices.begin<size_type>(),
                     indices.end<size_type>(),
                     comparator<T>{*keys, input.has_nulls(), ascending, null_precedence});
      } else {
        // wicked fast sort for a non-stable, non-null, numeric column
        fast_numeric_sort<T>(input, indices, ascending, stream);
      }
    }
  }

  template <typename T,
            typename std::enable_if_t<!cudf::is_relationally_comparable<T, T>()>* = nullptr>
  void operator()(column_view const&, mutable_column_view&, bool, null_order, rmm::cuda_stream_view)
  {
    CUDF_FAIL("Column type must be relationally comparable");
  }
};

/**
 * @brief Sort indices of a single column.
 *
 * @param input Column to sort. The column data is not modified.
 * @param column_order Ascending or descending sort order
 * @param null_precedence How null rows are to be ordered
 * @param stream CUDA stream used for device memory operations and kernel launches
 * @param mr Device memory resource used to allocate the returned column's device memory
 * @return Sorted indices for the input column.
 */
template <bool stable = false>
std::unique_ptr<column> sorted_order(column_view const& input,
                                     order column_order,
                                     null_order null_precedence,
                                     rmm::cuda_stream_view stream,
                                     rmm::mr::device_memory_resource* mr)
{
  auto sorted_indices = cudf::make_numeric_column(
    data_type(type_to_id<size_type>()), input.size(), mask_state::UNALLOCATED, stream, mr);
  mutable_column_view indices_view = sorted_indices->mutable_view();
  thrust::sequence(
    rmm::exec_policy(stream), indices_view.begin<size_type>(), indices_view.end<size_type>(), 0);
  cudf::type_dispatcher(input.type(),
                        single_column_sort_fn<stable>{},
                        input,
                        indices_view,
                        column_order == order::ASCENDING,
                        null_precedence,
                        stream);
  return sorted_indices;
}

template <bool stable = false>
std::unique_ptr<column> sorted_order(table_view input,
                                     std::vector<order> const& column_order,
                                     std::vector<null_order> const& null_precedence,
                                     rmm::cuda_stream_view stream,
                                     rmm::mr::device_memory_resource* mr)
{
  if (input.num_rows() == 0 or input.num_columns() == 0) {
    return cudf::make_numeric_column(data_type(type_to_id<size_type>()), 0);
  }

  if (not column_order.empty()) {
    CUDF_EXPECTS(static_cast<std::size_t>(input.num_columns()) == column_order.size(),
                 "Mismatch between number of columns and column order.");
  }

  if (not null_precedence.empty()) {
    CUDF_EXPECTS(static_cast<std::size_t>(input.num_columns()) == null_precedence.size(),
                 "Mismatch between number of columns and null_precedence size.");
  }

  std::unique_ptr<column> sorted_indices = cudf::make_numeric_column(
    data_type(type_to_id<size_type>()), input.num_rows(), mask_state::UNALLOCATED, stream, mr);
  mutable_column_view mutable_indices_view = sorted_indices->mutable_view();
  thrust::sequence(rmm::exec_policy(stream),
                   mutable_indices_view.begin<size_type>(),
                   mutable_indices_view.end<size_type>(),
                   0);

  // fast-path for single column sort
  if (input.num_columns() == 1) {
    return sorted_order<stable>(
      input.column(0),
      column_order.empty() ? order::ASCENDING : column_order.front(),
      null_precedence.empty() ? null_order::BEFORE : null_precedence.front(),
      stream,
      mr);
  }

  auto device_table = table_device_view::create(input, stream);
  rmm::device_vector<order> d_column_order(column_order);

  if (has_nulls(input)) {
    rmm::device_vector<null_order> d_null_precedence(null_precedence);
    auto comparator = row_lexicographic_comparator<true>(
      *device_table, *device_table, d_column_order.data().get(), d_null_precedence.data().get());
    if (stable) {
      thrust::stable_sort(rmm::exec_policy(stream),
                          mutable_indices_view.begin<size_type>(),
                          mutable_indices_view.end<size_type>(),
                          comparator);
    } else {
      thrust::sort(rmm::exec_policy(stream),
                   mutable_indices_view.begin<size_type>(),
                   mutable_indices_view.end<size_type>(),
                   comparator);
    }
  } else {
    auto comparator = row_lexicographic_comparator<false>(
      *device_table, *device_table, d_column_order.data().get());
    if (stable) {
      thrust::stable_sort(rmm::exec_policy(stream),
                          mutable_indices_view.begin<size_type>(),
                          mutable_indices_view.end<size_type>(),
                          comparator);
    } else {
      thrust::sort(rmm::exec_policy(stream),
                   mutable_indices_view.begin<size_type>(),
                   mutable_indices_view.end<size_type>(),
                   comparator);
    }
  }

  return sorted_indices;
}

}  // namespace detail
}  // namespace cudf
