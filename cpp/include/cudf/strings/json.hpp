/*
<<<<<<< HEAD
 * Copyright (c) 2019-2021, BAIDU CORPORATION.
=======
 * Copyright (c) 2019-2021, NVIDIA CORPORATION.
>>>>>>> 58f395b15524309b36bcc1480eb4d186764df7dd
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
<<<<<<< HEAD

#pragma once

#include <cudf/column/column.hpp>
#include <cudf/scalar/scalar.hpp>
=======
#pragma once

>>>>>>> 58f395b15524309b36bcc1480eb4d186764df7dd
#include <cudf/strings/strings_column_view.hpp>

namespace cudf {
namespace strings {

/**
 * @addtogroup strings_json
 * @{
 * @file
 */

/**
<<<<<<< HEAD
 * @brief Convert input json strings column to lists.
 *
 * Parse input json strings to a list column, which is combined by struct columns of two column, key
 * and value. and when input json string element type is OBJECT, the list size is 1, while when element
 * type is ARRAY, the list size is euqal to number of json object in the json arrray.
 *
 * @param col The input strings column. Each row must contain a valid json string
 * @param mr Resource for allocating device memory.
 * @return A LIST column of STRUCT column of a pair of string columns, key and value.
 */
std::unique_ptr<cudf::column> json_to_array(
  cudf::strings_column_view const& col,
=======
 * @brief Apply a JSONPath string to all rows in an input strings column.
 *
 * Applies a JSONPath string to an incoming strings column where each row in the column
 * is a valid json string.  The output is returned by row as a strings column.
 *
 * https://tools.ietf.org/id/draft-goessner-dispatch-jsonpath-00.html
 * Implements only the operators: $ . [] *
 *
 * @param col The input strings column. Each row must contain a valid json string
 * @param json_path The JSONPath string to be applied to each row
 * @param mr Resource for allocating device memory.
 * @return New strings column containing the retrieved json object strings
 */
std::unique_ptr<cudf::column> get_json_object(
  cudf::strings_column_view const& col,
  cudf::string_scalar const& json_path,
>>>>>>> 58f395b15524309b36bcc1480eb4d186764df7dd
  rmm::mr::device_memory_resource* mr = rmm::mr::get_current_device_resource());

/** @} */  // end of doxygen group
}  // namespace strings
}  // namespace cudf
