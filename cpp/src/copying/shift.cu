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
 
#include <cudf/cudf.h>
#include <cudf/legacy/table.hpp>
#include <cudf/copying.hpp>
#include <cudf/filling.hpp>

#include <copying/copy_range.cuh>
#include <filling/scalar_factory.cuh>

#include <vector>

namespace cudf {

namespace detail {

  void shift(
    gdf_column *out_column,
    gdf_column const &in_column,
    gdf_index_type periods,
    gdf_scalar const *fill_value
  )
  {
    gdf_index_type in_start = 0;
    gdf_index_type out_start = periods;
    gdf_index_type out_end = out_column->size;
    gdf_index_type fill_start = 0;
    gdf_index_type fill_end = out_start;
  
    if (periods < 0) {
      in_start = -periods;
      out_start = 0;
      out_end = out_column->size + periods;
      fill_start = out_end;
      fill_end = out_column->size;
    }

    detail::copy_range(out_column, detail::column_range_factory{in_column, in_start}, out_start, out_end);

    if (fill_value != nullptr) {
      detail::copy_range(out_column, detail::scalar_factory{*fill_value}, fill_start, fill_end);
    }
  }

}; // namespace detail

table shift(
  const table& in_table,
  gdf_index_type periods,
  const gdf_scalar* fill_value
)
{
  table out_table = allocate_like(in_table, ALWAYS);

  for (gdf_index_type i = 0; i < out_table.num_columns(); i++)
  {
      auto out_column = const_cast<gdf_column*>(out_table.get_column(i));
      auto in_column = const_cast<gdf_column*>(in_table.get_column(i));

      detail::shift(out_column, *in_column, periods, fill_value);
  }

  return out_table;
}

}; // namespace cudf
