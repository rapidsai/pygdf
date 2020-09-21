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
#include <cudf/scalar/scalar.hpp>
#include <cudf/strings/strings_column_view.hpp>

namespace nvtext
{

/**
 * @brief Returns a single column of strings by tokenizing the input strings
 * column using the provided characters as delimiters.
 *
 * The `delimiter` may be zero or more characters. If the `delimiter` is empty,
 * whitespace (character code-point <= ' ') is used for identifying tokens.
 * Also, any consecutive delimiters found in a string are ignored.
 * This means only non-empty tokens are returned.
 *
 * Tokens are found by locating delimiter(s) starting at the beginning of each string.
 * As each string is tokenized, the tokens are appended using input column row order
 * to build the output column. That is, tokens found in input row[i] will be placed in
 * the output column directly before tokens found in input row[i+1].
 *
 * Example:
 * ```
 * s = ["a", "b c", "d  e f "]
 * t = tokenize(s)
 * t is now ["a", "b", "c", "d", "e", "f"]
 * ```
 *
 * All null row entries are ignored and the output contains all valid rows.
 *
 * @param strings Strings column tokenize.
 * @param delimiter UTF-8 characters used to separate each string into tokens.
 *                  The default of empty string will separate tokens using whitespace.
 * @param mr Resource for allocating device memory.
 * @return New strings columns of tokens.
 */
std::unique_ptr<cudf::column> tokenize( cudf::strings_column_view const& strings,
                                        cudf::string_scalar const& delimiter = cudf::string_scalar{""},
                                        rmm::mr::device_memory_resource* mr = rmm::mr::get_default_resource());

/**
 * @brief Returns a single column of strings by tokenizing the input strings
 * column using multiple strings as delimiters.
 *
 * Tokens are found by locating delimiter(s) starting at the beginning of each string.
 * Any consecutive delimiters found in a string are ignored.
 * This means only non-empty tokens are returned.
 *
 * As each string is tokenized, the tokens are appended using input column row order
 * to build the output column. That is, tokens found in input row[i] will be placed in
 * the output column directly before tokens found in input row[i+1].
 *
 * Example:
 * ```
 * s = ["a", "b c", "d.e:f;"]
 * d = [".", ":", ";"]
 * t = tokenize(s,d)
 * t is now ["a", "b c", "d", "e", "f"]
 * ```
 *
 * All null row entries are ignored and the output contains all valid rows.
 *
 * @throw cudf::logic_error if the delimiters column is empty or contains nulls.
 *
 * @param strings Strings column to tokenize.
 * @param delimiters Strings used to separate individual strings into tokens.
 * @param mr Resource for allocating device memory.
 * @return New strings columns of tokens.
 */
std::unique_ptr<cudf::column> tokenize( cudf::strings_column_view const& strings,
                                        cudf::strings_column_view const& delimiters,
                                        rmm::mr::device_memory_resource* mr = rmm::mr::get_default_resource());

/**
 * @brief Returns the number of tokens in each string of a strings column.
 *
 * The `delimiter` may be zero or more characters. If the `delimiter` is empty,
 * whitespace (character code-point <= ' ') is used for identifying tokens.
 * Also, any consecutive delimiters found in a string are ignored.
 * This means that only empty strings or null rows will result in a token count of 0.
 *
 * Example:
 * ```
 * s = ["a", "b c", " ", "d e f"]
 * t = count_tokens(s)
 * t is now [1, 2, 0, 3]
 * ```
 *
 * All null row entries are ignored and the output contains all valid rows.
 * The number of tokens for a null element is set to 0 in the output column.
 *
 * @param strings Strings column to use for this operation.
 * @param delimiter Strings used to separate each string into tokens.
 *                  The default of empty string will separate tokens using whitespace.
 * @param mr Resource for allocating device memory.
 * @return New INT32 column of token counts.
 */
std::unique_ptr<cudf::column> count_tokens( cudf::strings_column_view const& strings,
                                            cudf::string_scalar const& delimiter = cudf::string_scalar{""},
                                            rmm::mr::device_memory_resource* mr = rmm::mr::get_default_resource());

/**
 * @brief Returns the number of tokens in each string of a strings column
 * by using multiple strings delimiters to identify tokens in each string.
 *
 * Also, any consecutive delimiters found in a string are ignored.
 * This means that only empty strings or null rows will result in a token count of 0.
 *
 * Example:
 * ```
 * s = ["a", "b c", "d.e:f;"]
 * d = [".", ":", ";"]
 * t = count_tokens(s,d)
 * t is now [1, 1, 3]
 * ```
 *
 * All null row entries are ignored and the output contains all valid rows.
 * The number of tokens for a null element is set to 0 in the output column.
 *
 * @throw cudf::logic_error if the delimiters column is empty or contains nulls.
 *
 * @param strings Strings column to use for this operation.
 * @param delimiters Strings used to separate each string into tokens.
 * @param mr Resource for allocating device memory.
 * @return New INT32 column of token counts.
 */
std::unique_ptr<cudf::column> count_tokens( cudf::strings_column_view const& strings,
                                            cudf::strings_column_view const& delimiters,
                                            rmm::mr::device_memory_resource* mr = rmm::mr::get_default_resource());

} // namespace nvtext
