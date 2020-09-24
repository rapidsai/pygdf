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

#pragma once

#include <cudf/column/column.hpp>

namespace cudf {

namespace jni {

  std::unique_ptr<column> map_lookup(
    column_view const& map_column,
    string_scalar lookup_key,
    rmm::mr::device_memory_resource* mr = rmm::mr::get_current_device_resource(),
    cudaStream_t stream                 = 0);

} // namespace jni;

} // namespace cudf;