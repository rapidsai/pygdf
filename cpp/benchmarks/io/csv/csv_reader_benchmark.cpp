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

#include <benchmark/benchmark.h>

#include <benchmarks/common/generate_benchmark_input.hpp>
#include <benchmarks/fixture/benchmark_fixture.hpp>
#include <benchmarks/io/cuio_benchmark_common.hpp>
#include <benchmarks/synchronization/synchronization.hpp>

#include <cudf/io/csv.hpp>

// to enable, run cmake with -DBUILD_BENCHMARKS=ON

constexpr size_t data_size         = 256 << 20;
constexpr cudf::size_type num_cols = 64;

namespace cudf_io = cudf::io;

class CsvRead : public cudf::benchmark {
};

void BM_csv_read_varying_input(benchmark::State& state)
{
  auto const data_types     = get_type_or_group(state.range(0));
  io_type const source_type = static_cast<io_type>(state.range(1));

  auto const tbl  = create_random_table(data_types, num_cols, table_size_bytes{data_size});
  auto const view = tbl->view();

  cuio_source_sink_pair source_sink(source_type);
  cudf_io::csv_writer_options options =
    cudf_io::csv_writer_options::builder(source_sink.make_sink_info(), view)
      .include_header(false)
      .rows_per_chunk(1 << 30);
  cudf_io::write_csv(options);

  cudf_io::csv_reader_options read_options =
    cudf_io::csv_reader_options::builder(source_sink.make_source_info());

  for (auto _ : state) {
    cuda_event_timer raii(state, true);  // flush_l2_cache = true, stream = 0
    cudf_io::read_csv(read_options);
  }

  state.SetBytesProcessed(data_size * state.iterations());
}

// Arrange columns such that total size of selected columns is half of the total table size
std::vector<cudf::type_id> opts_bm_data_types(std::vector<int32_t> const& ids, column_selection cs)
{
  auto data_types          = get_type_or_group(ids);
  auto const orig_type_cnt = data_types.size();
  data_types.resize(2 * orig_type_cnt);
  switch (cs) {
    case column_selection::ALL:
    case column_selection::HALF:
      std::copy(
        data_types.begin(), data_types.begin() + orig_type_cnt, data_types.begin() + orig_type_cnt);
      break;
    case column_selection::ALTERNATE:
      for (int i = orig_type_cnt - 1; i >= 0; --i)
        data_types[2 * i] = data_types[2 * i + 1] = data_types[i];
      break;
  }
  return data_types;
}

std::vector<int> select_columns(column_selection cs, int num_cols)
{
  std::vector<int> col_idxs(num_cols / 2);
  switch (cs) {
    case column_selection::ALL: col_idxs.resize(num_cols);
    case column_selection::HALF: std::iota(std::begin(col_idxs), std::end(col_idxs), 0); break;
    case column_selection::ALTERNATE:
      for (size_t i = 0; i < col_idxs.size(); ++i) col_idxs[i] = 2 * i;
      break;
  }
  return col_idxs;
}

void BM_csv_read_varying_options(benchmark::State& state)
{
  auto const col_selection = static_cast<column_selection>(state.range(0));
  auto const data_types    = opts_bm_data_types({int32_t(type_group_id::INTEGRAL),
                                              int32_t(type_group_id::FLOATING_POINT),
                                              int32_t(type_group_id::TIMESTAMP),
                                              int32_t(cudf::type_id::STRING)},
                                             col_selection);

  auto const tbl  = create_random_table(data_types, num_cols, table_size_bytes{data_size});
  auto const view = tbl->view();

  auto cols_to_read = select_columns(col_selection, view.num_columns());

  cuio_source_sink_pair source_sink(io_type::HOST_BUFFER);
  cudf_io::csv_writer_options options =
    cudf_io::csv_writer_options::builder(source_sink.make_sink_info(), view)
      .include_header(false)
      .rows_per_chunk(1 << 30);
  cudf_io::write_csv(options);

  cudf_io::csv_reader_options read_options =
    cudf_io::csv_reader_options::builder(source_sink.make_source_info())
      .use_cols_indexes(cols_to_read)
      .thousands('\'')
      .comment('#')
      .prefix("BM_");

  for (auto _ : state) {
    cuda_event_timer raii(state, true);  // flush_l2_cache = true, stream = 0
    cudf_io::read_csv(read_options);
  }
  auto const data_processed = data_size * cols_to_read.size() / view.num_columns();
  state.SetBytesProcessed(data_processed * state.iterations());
}

#define CSV_RD_BM_INPUTS_DEFINE(name, type_or_group, src_type)       \
  BENCHMARK_DEFINE_F(CsvRead, name)                                  \
  (::benchmark::State & state) { BM_csv_read_varying_input(state); } \
  BENCHMARK_REGISTER_F(CsvRead, name)                                \
    ->Args({int32_t(type_or_group), src_type})                       \
    ->Unit(benchmark::kMillisecond)                                  \
    ->UseManualTime();

// RD_BENCHMARK_DEFINE_ALL_SOURCES(CSV_RD_BM_INPUTS_DEFINE, integral, type_group_id::INTEGRAL);
// RD_BENCHMARK_DEFINE_ALL_SOURCES(CSV_RD_BM_INPUTS_DEFINE, floats, type_group_id::FLOATING_POINT);
// RD_BENCHMARK_DEFINE_ALL_SOURCES(CSV_RD_BM_INPUTS_DEFINE, timestamps, type_group_id::TIMESTAMP);
// RD_BENCHMARK_DEFINE_ALL_SOURCES(CSV_RD_BM_INPUTS_DEFINE, string, cudf::type_id::STRING);

#define CSV_RD_BM_OPTIONS_DEFINE(name)                                 \
  BENCHMARK_DEFINE_F(CsvRead, name)                                    \
  (::benchmark::State & state) { BM_csv_read_varying_options(state); } \
  BENCHMARK_REGISTER_F(CsvRead, name)                                  \
    ->Args({int32_t(column_selection::ALTERNATE), 1, false})           \
    ->Args({int32_t(column_selection::HALF), 1, false})                \
    ->Args({int32_t(column_selection::ALL), 1, false})                 \
    ->Unit(benchmark::kMillisecond)                                    \
    ->UseManualTime();

CSV_RD_BM_OPTIONS_DEFINE(reader_options)
