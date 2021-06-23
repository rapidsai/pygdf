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

#include <cudf/dictionary/dictionary_column_view.hpp>
#include <cudf/lists/lists_column_view.hpp>
#include <cudf/types.hpp>
#include <cudf/utilities/traits.hpp>

#include <thrust/iterator/counting_iterator.h>

#include <algorithm>

namespace cudf {

bool column_types_equal(column_view const& lhs, column_view const& rhs);

struct columns_equal_fn {
  template <typename T, typename... Arg>
  bool operator()(Arg&&...)
  {
    return true;
  }

  template <typename T, CUDF_ENABLE_IF(is_dictionary<T>())>
  bool operator()(column_view lhs, column_view rhs)
  {
    auto const kidx = dictionary_column_view::keys_column_index;
    return lhs.num_children() > 0 and rhs.num_children() > 0
             ? lhs.child(kidx).type() == rhs.child(kidx).type()
             : lhs.is_empty() and rhs.is_empty();
  }

  template <typename T, CUDF_ENABLE_IF(is_list<T>())>
  bool operator()(column_view lhs, column_view rhs)
  {
    auto const& ci = lists_column_view::child_column_index;
    return column_types_equal(lhs.child(ci), rhs.child(ci));
  }

  template <typename T, CUDF_ENABLE_IF(is_struct<T>())>
  bool operator()(column_view lhs, column_view rhs)
  {
    return lhs.num_children() == rhs.num_children() and
           std::all_of(thrust::make_counting_iterator(0),
                       thrust::make_counting_iterator(lhs.num_children()),
                       [&](auto i) { return column_types_equal(lhs.child(i), rhs.child(i)); });
  }
};

// Implementation note: avoid using double dispatch for this function
// as it increases code paths to NxN for N types.
bool column_types_equal(column_view const& lhs, column_view const& rhs)
{
  if (lhs.type() != rhs.type()) { return false; }
  return type_dispatcher(lhs.type(), columns_equal_fn{}, lhs, rhs);
}

}  // namespace cudf
