/*
 * Copyright (c) 2020, NVIDIA CORPORATION.
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
// The translation unit for reduction `max`

#include <cudf/column/column_device_view.cuh>
#include <cudf/column/column_view.hpp>
#include <cudf/copying.hpp>
#include <cudf/detail/iterator.cuh>
#include <cudf/detail/reduction_functions.hpp>

#include <thrust/binary_search.h>
#include <rmm/device_uvector.hpp>

std::unique_ptr<cudf::scalar> cudf::reduction::nth_element(column_view const& col,
                                                           size_type n,
                                                           null_policy null_handling,
                                                           rmm::mr::device_memory_resource* mr,
                                                           cudaStream_t stream)
{
  CUDF_EXPECTS(n >= -col.size() and n < col.size(), "Index out of bounds");
  if (null_handling == null_policy::EXCLUDE and col.has_nulls()) {
    auto valid_count = col.size() - col.null_count();
    n                = (n < 0 ? valid_count + n : n);
    CUDF_EXPECTS(n >= 0 and n < valid_count, "Index out of bounds");
    auto dcol = column_device_view::create(col);
    auto bitmask_iterator =
      thrust::make_transform_iterator(cudf::detail::make_validity_iterator(*dcol),
                                      [] __device__(auto b) { return static_cast<size_type>(b); });
    rmm::device_uvector<size_type> null_skipped_index(col.size(), stream);
    // null skipped index for valids only.
    thrust::inclusive_scan(rmm::exec_policy(stream)->on(stream),
                           bitmask_iterator,
                           bitmask_iterator + col.size(),
                           null_skipped_index.begin());
    auto n_pos          = thrust::upper_bound(rmm::exec_policy(stream)->on(stream),
                                     null_skipped_index.begin(),
                                     null_skipped_index.end(),
                                     n);
    auto null_skipped_n = n_pos - null_skipped_index.begin();
    return get_element(col, null_skipped_n, mr);
  } else {
    n = (n < 0 ? col.size() + n : n);
    return get_element(col, n, mr);
  }
}
