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

#include <cudf/column/column_view.hpp>
#include <cudf/copying.hpp>
#include <cudf/detail/reverse.hpp>
#include <cudf/table/table.hpp>
#include <cudf/table/table_view.hpp>

#include <rmm/cuda_stream_view.hpp>

namespace cudf {
namespace detail {
std::unique_ptr<table> reverse(
  table_view const& source_table,
  rmm::mr::device_memory_resource* mr = rmm::mr::get_current_device_resource())
{
  return std::unique_ptr<table>{};
}

std::unique_ptr<column> reverse(
  column_view const& source_column,
  rmm::mr::device_memory_resource* mr = rmm::mr::get_current_device_resource())
{
  return std::unique_ptr<column>{};
}

}  // namespace detail
}  // namespace cudf