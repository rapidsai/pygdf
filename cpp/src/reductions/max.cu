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
// The translation unit for reduction `max`

#include <cudf/detail/reduction_functions.hpp>
#include <cudf/dictionary/dictionary_column_view.hpp>
#include <reductions/simple.cuh>

std::unique_ptr<cudf::scalar> cudf::reduction::max(column_view const& col,
                                                   cudf::data_type const output_dtype,
                                                   rmm::mr::device_memory_resource* mr,
                                                   cudaStream_t stream)
{
  using reducer = cudf::reduction::simple::element_type_dispatcher<cudf::reduction::op::max>;
  auto col_type =
    cudf::is_dictionary(col.type()) ? dictionary_column_view(col).keys().type() : col.type();
  return cudf::type_dispatcher(col_type, reducer(), col, output_dtype, mr, stream);
}
