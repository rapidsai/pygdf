/*
 * Copyright (c) 2019-2021, NVIDIA CORPORATION.
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

/**
 * @file writer_impl.cu
 * @brief cuDF-IO ORC writer class implementation
 */

#include "writer_impl.hpp"

#include <io/utilities/column_utils.cuh>

#include <cudf/detail/iterator.cuh>
#include <cudf/detail/utilities/cuda.cuh>
#include <cudf/detail/utilities/vector_factories.hpp>
#include <cudf/null_mask.hpp>
#include <cudf/strings/strings_column_view.hpp>
#include <cudf/utilities/bit.hpp>
#include <cudf/utilities/span.hpp>

#include <rmm/cuda_stream_view.hpp>
#include <rmm/device_buffer.hpp>
#include <rmm/device_uvector.hpp>

#include <algorithm>
#include <cstring>
#include <numeric>
#include <utility>

namespace cudf {
namespace io {
namespace detail {
namespace orc {
using namespace cudf::io::orc;
using namespace cudf::io;
using gpu::orc_column_device_view;

struct row_group_index_info {
  int32_t pos       = -1;  // Position
  int32_t blk_pos   = -1;  // Block Position
  int32_t comp_pos  = -1;  // Compressed Position
  int32_t comp_size = -1;  // Compressed size
};

namespace {
/**
 * @brief Helper for pinned host memory
 */
template <typename T>
using pinned_buffer = std::unique_ptr<T, decltype(&cudaFreeHost)>;

/**
 * @brief Function that translates GDF compression to ORC compression
 */
orc::CompressionKind to_orc_compression(compression_type compression)
{
  switch (compression) {
    case compression_type::AUTO:
    case compression_type::SNAPPY: return orc::CompressionKind::SNAPPY;
    case compression_type::NONE: return orc::CompressionKind::NONE;
    default: CUDF_EXPECTS(false, "Unsupported compression type"); return orc::CompressionKind::NONE;
  }
}

/**
 * @brief Function that translates GDF dtype to ORC datatype
 */
constexpr orc::TypeKind to_orc_type(cudf::type_id id)
{
  switch (id) {
    case cudf::type_id::INT8: return TypeKind::BYTE;
    case cudf::type_id::INT16: return TypeKind::SHORT;
    case cudf::type_id::INT32: return TypeKind::INT;
    case cudf::type_id::INT64: return TypeKind::LONG;
    case cudf::type_id::FLOAT32: return TypeKind::FLOAT;
    case cudf::type_id::FLOAT64: return TypeKind::DOUBLE;
    case cudf::type_id::BOOL8: return TypeKind::BOOLEAN;
    case cudf::type_id::TIMESTAMP_DAYS: return TypeKind::DATE;
    case cudf::type_id::TIMESTAMP_SECONDS:
    case cudf::type_id::TIMESTAMP_MICROSECONDS:
    case cudf::type_id::TIMESTAMP_MILLISECONDS:
    case cudf::type_id::TIMESTAMP_NANOSECONDS: return TypeKind::TIMESTAMP;
    case cudf::type_id::STRING: return TypeKind::STRING;
    case cudf::type_id::DECIMAL32:
    case cudf::type_id::DECIMAL64: return TypeKind::DECIMAL;
    case cudf::type_id::LIST: return TypeKind::LIST;
    default: return TypeKind::INVALID_TYPE_KIND;
  }
}

/**
 * @brief Translates time unit to nanoscale multiple.
 */
constexpr int32_t to_clockscale(cudf::type_id timestamp_id)
{
  switch (timestamp_id) {
    case cudf::type_id::TIMESTAMP_SECONDS: return 9;
    case cudf::type_id::TIMESTAMP_MILLISECONDS: return 6;
    case cudf::type_id::TIMESTAMP_MICROSECONDS: return 3;
    case cudf::type_id::TIMESTAMP_NANOSECONDS:
    default: return 0;
  }
}

/**
 * @brief Returns the precision of the given decimal type.
 */
constexpr auto orc_precision(cudf::type_id decimal_id)
{
  switch (decimal_id) {
    case cudf::type_id::DECIMAL32: return 9;
    case cudf::type_id::DECIMAL64: return 18;
    default: return 0;
  }
}

}  // namespace

/**
 * @brief Helper class that adds ORC-specific column info
 */
class orc_column_view {
 public:
  /**
   * @brief Constructor that extracts out the string position + length pairs
   * for building dictionaries for string columns
   */
  explicit orc_column_view(uint32_t index,
                           uint32_t str_id,
                           column_view const &col,
                           const table_metadata *metadata)
    : cudf_column{col},
      _index{index},
      _str_id{str_id},
      _type_width{cudf::is_fixed_width(col.type()) ? cudf::size_of(col.type()) : 0},
      _scale{(to_orc_type(col.type().id()) == TypeKind::DECIMAL) ? -col.type().scale()
                                                                 : to_clockscale(col.type().id())},
      _precision{orc_precision(col.type().id())},
      _type_kind{to_orc_type(col.type().id())}
  {
    // Generating default name if name isn't present in metadata
    if (metadata && _index < metadata->column_names.size()) {
      _name = metadata->column_names[_index];
    } else {
      _name = "_col" + std::to_string(_index);
    }
  }

  auto is_string() const noexcept { return cudf_column.type().id() == type_id::STRING; }
  void set_dict_stride(size_t stride) noexcept { dict_stride = stride; }
  auto get_dict_stride() const noexcept { return dict_stride; }

  /**
   * @brief Function that associates an existing dictionary chunk allocation
   */
  void attach_dict_chunk(gpu::DictionaryChunk *host_dict, gpu::DictionaryChunk *dev_dict)
  {
    dict   = host_dict;
    d_dict = dev_dict;
  }
  auto host_dict_chunk(size_t rowgroup) const
  {
    CUDF_EXPECTS(cudf_column.type().id() == type_id::STRING,
                 "Dictionary chunks are only present in string columns.");
    return &dict[rowgroup * dict_stride + _str_id];
  }
  auto device_dict_chunk() const { return d_dict; }

  auto const &decimal_offsets() const { return d_decimal_offsets; }
  void attach_decimal_offsets(uint32_t *sizes_ptr) { d_decimal_offsets = sizes_ptr; }

  /**
   * @brief Function that associates an existing stripe dictionary allocation
   */
  void attach_stripe_dict(gpu::StripeDictionary *host_stripe_dict,
                          gpu::StripeDictionary *dev_stripe_dict)
  {
    stripe_dict   = host_stripe_dict;
    d_stripe_dict = dev_stripe_dict;
  }
  auto host_stripe_dict(size_t stripe) const
  {
    CUDF_EXPECTS(cudf_column.type().id() == type_id::STRING,
                 "Stripe dictionary is only present in string columns.");
    return &stripe_dict[stripe * dict_stride + _str_id];
  }
  auto device_stripe_dict() const { return d_stripe_dict; }

  // Index in the table
  auto flat_index() const noexcept { return _index; }
  // Id in the ORC file
  auto id() const noexcept { return _index + 1; }
  auto type_width() const noexcept { return _type_width; }
  auto size() const noexcept { return cudf_column.size(); }
  auto null_count() const noexcept { return cudf_column.null_count(); }
  auto null_mask() const noexcept { return cudf_column.null_mask(); }
  bool nullable() const noexcept { return null_mask() != nullptr; }

  auto scale() const noexcept { return _scale; }
  auto precision() const noexcept { return _precision; }

  void set_orc_encoding(ColumnEncodingKind e) noexcept { _encoding_kind = e; }
  auto orc_kind() const noexcept { return _type_kind; }
  auto orc_encoding() const noexcept { return _encoding_kind; }
  auto orc_name() const noexcept { return _name; }

 private:
  column_view cudf_column;

  // Identifier within set of columns and string columns, respectively
  uint32_t _index  = 0;
  uint32_t _str_id = 0;

  size_t _type_width = 0;
  int32_t _scale     = 0;
  int32_t _precision = 0;

  // ORC-related members
  std::string _name{};
  TypeKind _type_kind;
  ColumnEncodingKind _encoding_kind;

  // String dictionary-related members
  size_t dict_stride                       = 0;
  gpu::DictionaryChunk const *dict         = nullptr;
  gpu::StripeDictionary const *stripe_dict = nullptr;
  gpu::DictionaryChunk *d_dict             = nullptr;
  gpu::StripeDictionary *d_stripe_dict     = nullptr;

  // Offsets for encoded decimal elements. Used to enable direct writing of encoded decimal elements
  // into the output stream.
  uint32_t *d_decimal_offsets = nullptr;
};

size_type orc_table_view::num_rows() const { return columns.empty() ? 0 : columns.front().size(); }

std::vector<stripe_rowgroups> writer::impl::gather_stripe_info(
  host_span<orc_column_view const> columns, size_t num_rowgroups)
{
  auto const is_any_column_string =
    std::any_of(columns.begin(), columns.end(), [](auto const &col) { return col.is_string(); });
  // Apply rows per stripe limit to limit string dictionaries
  size_t const max_stripe_rows = is_any_column_string ? 1000000 : 5000000;

  std::vector<stripe_rowgroups> infos;
  for (size_t rowgroup = 0, stripe_start = 0, stripe_size = 0; rowgroup < num_rowgroups;
       ++rowgroup) {
    auto const rowgroup_size =
      std::accumulate(columns.begin(), columns.end(), 0ul, [&](size_t total_size, auto const &col) {
        if (col.is_string()) {
          const auto dt = col.host_dict_chunk(rowgroup);
          return total_size + row_index_stride_ + dt->string_char_count;
        } else {
          return total_size + col.type_width() * row_index_stride_;
        }
      });

    if ((rowgroup > stripe_start) &&
        (stripe_size + rowgroup_size > max_stripe_size_ ||
         (rowgroup + 1 - stripe_start) * row_index_stride_ > max_stripe_rows)) {
      infos.emplace_back(infos.size(), stripe_start, rowgroup - stripe_start);
      stripe_start = rowgroup;
      stripe_size  = 0;
    }
    stripe_size += rowgroup_size;
    if (rowgroup + 1 == num_rowgroups) {
      infos.emplace_back(infos.size(), stripe_start, num_rowgroups - stripe_start);
    }
  }

  return infos;
}

void writer::impl::init_dictionaries(orc_table_view &orc_table,
                                     device_span<device_span<uint32_t>> dict_data,
                                     device_span<device_span<uint32_t>> dict_index,
                                     hostdevice_vector<gpu::DictionaryChunk> *dict)
{
  const size_t num_rowgroups = dict->size() / orc_table.num_string_columns();

  // Setup per-rowgroup dictionary indexes for each dictionary-aware column
  for (size_t i = 0; i < orc_table.num_string_columns(); ++i) {
    auto &str_column = orc_table.string_column(i);
    str_column.set_dict_stride(orc_table.num_string_columns());
    str_column.attach_dict_chunk(dict->host_ptr(), dict->device_ptr());
  }

  gpu::InitDictionaryIndices(
    orc_table.d_columns,
    dict->device_ptr(),
    dict_data,
    dict_index,
    row_index_stride_,
    cudf::detail::make_device_uvector_async(orc_table.string_column_indices, stream),
    num_rowgroups,
    stream);
  dict->device_to_host(stream, true);
}

void writer::impl::build_dictionaries(orc_table_view &orc_table,
                                      host_span<stripe_rowgroups const> stripe_bounds,
                                      hostdevice_vector<gpu::DictionaryChunk> const &dict,
                                      host_span<rmm::device_uvector<uint32_t>> dict_index,
                                      hostdevice_vector<gpu::StripeDictionary> &stripe_dict)
{
  const auto num_rowgroups = dict.size() / orc_table.num_string_columns();

  for (size_t dict_idx = 0; dict_idx < orc_table.num_string_columns(); ++dict_idx) {
    auto &str_column = orc_table.string_column(dict_idx);
    str_column.attach_stripe_dict(stripe_dict.host_ptr(), stripe_dict.device_ptr());

    for (auto const &stripe : stripe_bounds) {
      auto &sd           = stripe_dict[stripe.id * orc_table.num_string_columns() + dict_idx];
      sd.dict_data       = str_column.host_dict_chunk(stripe.first)->dict_data;
      sd.dict_index      = dict_index[dict_idx].data();  // Indexed by abs row
      sd.column_id       = orc_table.string_column_indices[dict_idx];
      sd.start_chunk     = stripe.first;
      sd.num_chunks      = stripe.size;
      sd.dict_char_count = 0;
      sd.num_strings =
        std::accumulate(stripe.cbegin(), stripe.cend(), 0, [&](auto dt_str_cnt, auto rg_idx) {
          const auto &dt = dict[rg_idx * orc_table.num_string_columns() + dict_idx];
          return dt_str_cnt + dt.num_dict_strings;
        });
      sd.leaf_column = dict[dict_idx].leaf_column;
    }

    if (enable_dictionary_) {
      struct string_column_cost {
        size_t direct     = 0;
        size_t dictionary = 0;
      };
      auto const col_cost =
        std::accumulate(stripe_bounds.front().cbegin(),
                        stripe_bounds.back().cend(),
                        string_column_cost{},
                        [&](auto cost, auto rg_idx) -> string_column_cost {
                          const auto &dt = dict[rg_idx * orc_table.num_string_columns() + dict_idx];
                          return {cost.direct + dt.string_char_count,
                                  cost.dictionary + dt.dict_char_count + dt.num_dict_strings};
                        });
      // Disable dictionary if it does not reduce the output size
      if (col_cost.dictionary >= col_cost.direct) {
        for (auto const &stripe : stripe_bounds) {
          stripe_dict[stripe.id * orc_table.num_string_columns() + dict_idx].dict_data = nullptr;
        }
      }
    }
  }

  stripe_dict.host_to_device(stream);
  gpu::BuildStripeDictionaries(stripe_dict.device_ptr(),
                               stripe_dict.host_ptr(),
                               dict.device_ptr(),
                               stripe_bounds.size(),
                               num_rowgroups,
                               orc_table.string_column_indices.size(),
                               stream);
  stripe_dict.device_to_host(stream, true);
}

orc_streams writer::impl::create_streams(host_span<orc_column_view> columns,
                                         host_span<stripe_rowgroups const> stripe_bounds,
                                         std::map<uint32_t, size_t> const &decimal_column_sizes)
{
  // 'column 0' row index stream
  std::vector<Stream> streams{{ROW_INDEX, 0}};  // TODO: Separate index and data streams?
  // First n + 1 streams are row index streams
  streams.reserve(columns.size() + 1);
  std::transform(columns.begin(), columns.end(), std::back_inserter(streams), [](auto const &col) {
    return Stream{ROW_INDEX, col.id()};
  });

  std::vector<int32_t> ids(columns.size() * gpu::CI_NUM_STREAMS, -1);

  for (auto &column : columns) {
    TypeKind kind                    = column.orc_kind();
    StreamKind data_kind             = DATA;
    StreamKind data2_kind            = LENGTH;
    ColumnEncodingKind encoding_kind = DIRECT;

    int64_t present_stream_size = 0;
    int64_t data_stream_size    = 0;
    int64_t data2_stream_size   = 0;
    int64_t dict_stream_size    = 0;

    auto const is_nullable = [&]() -> bool {
      if (single_write_mode) {
        return column.nullable();
      } else {
        if (user_metadata_with_nullability.column_nullable.empty()) return true;
        CUDF_EXPECTS(user_metadata_with_nullability.column_nullable.size() > column.flat_index(),
                     "When passing values in user_metadata_with_nullability, data for all columns "
                     "must be specified");
        return user_metadata_with_nullability.column_nullable[column.flat_index()];
      }
    }();
    if (is_nullable) {
      present_stream_size = ((row_index_stride_ + 7) >> 3);
      present_stream_size += (present_stream_size + 0x7f) >> 7;
    }
    switch (kind) {
      case TypeKind::BOOLEAN:
        data_stream_size = div_rowgroups_by<int64_t>(1024) * (128 + 1);
        encoding_kind    = DIRECT;
        break;
      case TypeKind::BYTE:
        data_stream_size = div_rowgroups_by<int64_t>(128) * (128 + 1);
        encoding_kind    = DIRECT;
        break;
      case TypeKind::SHORT:
        data_stream_size = div_rowgroups_by<int64_t>(512) * (512 * 2 + 2);
        encoding_kind    = DIRECT_V2;
        break;
      case TypeKind::FLOAT:
        // Pass through if no nulls (no RLE encoding for floating point)
        data_stream_size =
          (column.null_count() != 0) ? div_rowgroups_by<int64_t>(512) * (512 * 4 + 2) : INT64_C(-1);
        encoding_kind = DIRECT;
        break;
      case TypeKind::INT:
      case TypeKind::DATE:
        data_stream_size = div_rowgroups_by<int64_t>(512) * (512 * 4 + 2);
        encoding_kind    = DIRECT_V2;
        break;
      case TypeKind::DOUBLE:
        // Pass through if no nulls (no RLE encoding for floating point)
        data_stream_size =
          (column.null_count() != 0) ? div_rowgroups_by<int64_t>(512) * (512 * 8 + 2) : INT64_C(-1);
        encoding_kind = DIRECT;
        break;
      case TypeKind::LONG:
        data_stream_size = div_rowgroups_by<int64_t>(512) * (512 * 8 + 2);
        encoding_kind    = DIRECT_V2;
        break;
      case TypeKind::STRING: {
        bool enable_dict           = enable_dictionary_;
        size_t dict_data_size      = 0;
        size_t dict_strings        = 0;
        size_t dict_lengths_div512 = 0;
        for (auto const &stripe : stripe_bounds) {
          const auto sd = column.host_stripe_dict(stripe.id);
          enable_dict   = (enable_dict && sd->dict_data != nullptr);
          if (enable_dict) {
            dict_strings += sd->num_strings;
            dict_lengths_div512 += (sd->num_strings + 0x1ff) >> 9;
            dict_data_size += sd->dict_char_count;
          }
        }

        auto const direct_data_size =
          std::accumulate(stripe_bounds.front().cbegin(),
                          stripe_bounds.back().cend(),
                          size_t{0},
                          [&](auto data_size, auto rg_idx) {
                            return data_size + column.host_dict_chunk(rg_idx)->string_char_count;
                          });
        if (enable_dict) {
          uint32_t dict_bits = 0;
          for (dict_bits = 1; dict_bits < 32; dict_bits <<= 1) {
            if (dict_strings <= (1ull << dict_bits)) break;
          }
          const auto valid_count = column.size() - column.null_count();
          dict_data_size += (dict_bits * valid_count + 7) >> 3;
        }

        // Decide between direct or dictionary encoding
        if (enable_dict && dict_data_size < direct_data_size) {
          data_stream_size  = div_rowgroups_by<int64_t>(512) * (512 * 4 + 2);
          data2_stream_size = dict_lengths_div512 * (512 * 4 + 2);
          dict_stream_size  = std::max<size_t>(dict_data_size, 1);
          encoding_kind     = DICTIONARY_V2;
        } else {
          data_stream_size  = std::max<size_t>(direct_data_size, 1);
          data2_stream_size = div_rowgroups_by<int64_t>(512) * (512 * 4 + 2);
          encoding_kind     = DIRECT_V2;
        }
        break;
      }
      case TypeKind::TIMESTAMP:
        data_stream_size  = ((row_index_stride_ + 0x1ff) >> 9) * (512 * 4 + 2);
        data2_stream_size = data_stream_size;
        data2_kind        = SECONDARY;
        encoding_kind     = DIRECT_V2;
        break;
      case TypeKind::DECIMAL:
        // varint values (NO RLE)
        data_stream_size = decimal_column_sizes.at(column.flat_index());
        // scale stream TODO: compute exact size since all elems are equal
        data2_stream_size = div_rowgroups_by<int64_t>(512) * (512 * 4 + 2);
        data2_kind        = SECONDARY;
        encoding_kind     = DIRECT_V2;
        break;
      case TypeKind::LIST:
        // no data streams, only present
        break;
      default: std::cout << kind << std::endl; CUDF_FAIL("Unsupported ORC type kind");
    }

    // Initialize the column's metadata (this is the only reason columns is in/out param)
    column.set_orc_encoding(encoding_kind);

    // Initialize the column's data stream(s)
    const auto base = column.flat_index() * gpu::CI_NUM_STREAMS;
    if (present_stream_size != 0) {
      auto len                    = static_cast<uint64_t>(present_stream_size);
      ids[base + gpu::CI_PRESENT] = streams.size();
      streams.push_back(orc::Stream{PRESENT, column.id(), len});
    }
    if (data_stream_size != 0) {
      auto len                 = static_cast<uint64_t>(std::max<int64_t>(data_stream_size, 0));
      ids[base + gpu::CI_DATA] = streams.size();
      streams.push_back(orc::Stream{data_kind, column.id(), len});
    }
    if (data2_stream_size != 0) {
      auto len                  = static_cast<uint64_t>(std::max<int64_t>(data2_stream_size, 0));
      ids[base + gpu::CI_DATA2] = streams.size();
      streams.push_back(orc::Stream{data2_kind, column.id(), len});
    }
    if (dict_stream_size != 0) {
      auto len                       = static_cast<uint64_t>(dict_stream_size);
      ids[base + gpu::CI_DICTIONARY] = streams.size();
      streams.push_back(orc::Stream{DICTIONARY_DATA, column.id(), len});
    }
  }
  return {std::move(streams), std::move(ids)};
}

orc_streams::orc_stream_offsets orc_streams::compute_offsets(
  host_span<orc_column_view const> columns, size_t num_rowgroups) const
{
  std::vector<size_t> strm_offsets(streams.size());
  size_t non_rle_data_size = 0;
  size_t rle_data_size     = 0;
  for (size_t i = 0; i < streams.size(); ++i) {
    const auto &stream = streams[i];

    auto const is_rle_data = [&]() {
      // First stream is an index stream, don't check types, etc.
      if (!stream.column_index().has_value()) return true;

      auto const &column = columns[stream.column_index().value()];
      // Dictionary encoded string column - dictionary characters or
      // directly encoded string - column characters
      if (column.orc_kind() == TypeKind::STRING &&
          ((stream.kind == DICTIONARY_DATA && column.orc_encoding() == DICTIONARY_V2) ||
           (stream.kind == DATA && column.orc_encoding() == DIRECT_V2)))
        return false;
      // Decimal data
      if (column.orc_kind() == TypeKind::DECIMAL && stream.kind == DATA) return false;

      // Everything else uses RLE
      return true;
    }();
    if (is_rle_data) {
      strm_offsets[i] = rle_data_size;
      rle_data_size += (stream.length * num_rowgroups + 7) & ~7;
    } else {
      strm_offsets[i] = non_rle_data_size;
      non_rle_data_size += stream.length;
    }
  }
  non_rle_data_size = (non_rle_data_size + 7) & ~7;

  return {std::move(strm_offsets), non_rle_data_size, rle_data_size};
}

struct segmented_valid_cnt_input {
  bitmask_type const *mask;
  std::vector<size_type> indices;
};

encoded_data writer::impl::encode_columns(orc_table_view const &orc_table,
                                          string_dictionaries &&dictionaries,
                                          encoder_decimal_info &&dec_chunk_sizes,
                                          host_span<stripe_rowgroups const> stripe_bounds,
                                          orc_streams const &streams)
{
  auto const num_columns   = orc_table.num_columns();
  auto const num_rowgroups = stripes_size(stripe_bounds);
  hostdevice_2dvector<gpu::EncChunk> chunks(num_columns, num_rowgroups, stream);
  hostdevice_2dvector<gpu::encoder_chunk_streams> chunk_streams(num_columns, num_rowgroups, stream);
  auto const stream_offsets = streams.compute_offsets(orc_table.columns, num_rowgroups);
  rmm::device_uvector<uint8_t> encoded_data(stream_offsets.data_size(), stream);

  // Initialize column chunks' descriptions
  std::map<size_type, segmented_valid_cnt_input> validity_check_inputs;

  for (auto const &column : orc_table.columns) {
    for (auto const &stripe : stripe_bounds) {
      for (auto rg_idx_it = stripe.cbegin(); rg_idx_it < stripe.cend(); ++rg_idx_it) {
        auto const rg_idx = *rg_idx_it;
        auto &ck          = chunks[column.flat_index()][rg_idx];

        ck.start_row     = (rg_idx * row_index_stride_);
        ck.num_rows      = std::min<uint32_t>(row_index_stride_, column.size() - ck.start_row);
        ck.encoding_kind = column.orc_encoding();
        ck.type_kind     = column.orc_kind();
        if (ck.type_kind == TypeKind::STRING) {
          ck.dict_index = (ck.encoding_kind == DICTIONARY_V2)
                            ? column.host_stripe_dict(stripe.id)->dict_index
                            : nullptr;
          ck.dtype_len = 1;
        } else {
          ck.dtype_len = column.type_width();
        }
        ck.scale = column.scale();
        if (ck.type_kind == TypeKind::DECIMAL) {
          ck.decimal_offsets = device_span<uint32_t>{column.decimal_offsets(), ck.num_rows};
        }
      }
    }
  }

  auto validity_check_indices = [&](size_t col_idx) {
    std::vector<size_type> indices;
    for (auto const &stripe : stripe_bounds) {
      for (auto rg_idx_it = stripe.cbegin(); rg_idx_it < stripe.cend() - 1; ++rg_idx_it) {
        auto const &chunk = chunks[col_idx][*rg_idx_it];
        indices.push_back(chunk.start_row);
        indices.push_back(chunk.start_row + chunk.num_rows);
      }
    }
    return indices;
  };
  for (auto const &column : orc_table.columns) {
    if (column.orc_kind() == TypeKind::BOOLEAN && column.nullable()) {
      validity_check_inputs[column.flat_index()] = {column.null_mask(),
                                                    validity_check_indices(column.flat_index())};
    }
  }
  for (auto &cnt_in : validity_check_inputs) {
    auto const valid_counts = segmented_count_set_bits(cnt_in.second.mask, cnt_in.second.indices);
    CUDF_EXPECTS(
      std::none_of(valid_counts.cbegin(),
                   valid_counts.cend(),
                   [](auto valid_count) { return valid_count % 8; }),
      "There's currently a bug in encoding boolean columns. Suggested workaround is to convert "
      "to int8 type."
      " Please see https://github.com/rapidsai/cudf/issues/6763 for more information.");
  }

  for (size_t col_idx = 0; col_idx < num_columns; col_idx++) {
    auto const &column = orc_table.column(col_idx);
    auto col_streams   = chunk_streams[col_idx];
    for (auto const &stripe : stripe_bounds) {
      for (auto rg_idx_it = stripe.cbegin(); rg_idx_it < stripe.cend(); ++rg_idx_it) {
        auto const rg_idx = *rg_idx_it;
        auto const &ck    = chunks[col_idx][rg_idx];
        auto &strm        = col_streams[rg_idx];

        for (int strm_type = 0; strm_type < gpu::CI_NUM_STREAMS; ++strm_type) {
          auto const strm_id = streams.id(col_idx * gpu::CI_NUM_STREAMS + strm_type);

          strm.ids[strm_type] = strm_id;
          if (strm_id >= 0) {
            if ((strm_type == gpu::CI_DICTIONARY) ||
                (strm_type == gpu::CI_DATA2 && ck.encoding_kind == DICTIONARY_V2)) {
              if (rg_idx_it == stripe.cbegin()) {
                const int32_t dict_stride = column.get_dict_stride();
                const auto stripe_dict    = column.host_stripe_dict(stripe.id);
                strm.lengths[strm_type] =
                  (strm_type == gpu::CI_DICTIONARY)
                    ? stripe_dict->dict_char_count
                    : (((stripe_dict->num_strings + 0x1ff) >> 9) * (512 * 4 + 2));
                if (stripe.id == 0) {
                  strm.data_ptrs[strm_type] = encoded_data.data() + stream_offsets.offsets[strm_id];
                } else {
                  auto const &strm_up = col_streams[stripe_dict[-dict_stride].start_chunk];
                  strm.data_ptrs[strm_type] =
                    strm_up.data_ptrs[strm_type] + strm_up.lengths[strm_type];
                }
              } else {
                strm.lengths[strm_type]   = 0;
                strm.data_ptrs[strm_type] = col_streams[rg_idx - 1].data_ptrs[strm_type];
              }
            } else if (strm_type == gpu::CI_DATA && ck.type_kind == TypeKind::STRING &&
                       ck.encoding_kind == DIRECT_V2) {
              strm.lengths[strm_type]   = column.host_dict_chunk(rg_idx)->string_char_count;
              strm.data_ptrs[strm_type] = (rg_idx == 0)
                                            ? encoded_data.data() + stream_offsets.offsets[strm_id]
                                            : (col_streams[rg_idx - 1].data_ptrs[strm_type] +
                                               col_streams[rg_idx - 1].lengths[strm_type]);
            } else if (strm_type == gpu::CI_DATA && streams[strm_id].length == 0 &&
                       (ck.type_kind == DOUBLE || ck.type_kind == FLOAT)) {
              // Pass-through
              strm.lengths[strm_type]   = ck.num_rows * ck.dtype_len;
              strm.data_ptrs[strm_type] = nullptr;

            } else if (ck.type_kind == DECIMAL && strm_type == gpu::CI_DATA) {
              strm.lengths[strm_type]   = dec_chunk_sizes.rg_sizes.at(col_idx)[rg_idx];
              strm.data_ptrs[strm_type] = (rg_idx == 0)
                                            ? encoded_data.data() + stream_offsets.offsets[strm_id]
                                            : (col_streams[rg_idx - 1].data_ptrs[strm_type] +
                                               col_streams[rg_idx - 1].lengths[strm_type]);
            } else {
              strm.lengths[strm_type]   = streams[strm_id].length;
              strm.data_ptrs[strm_type] = encoded_data.data() + stream_offsets.non_rle_data_size +
                                          stream_offsets.offsets[strm_id] +
                                          streams[strm_id].length * rg_idx;
            }
          } else {
            strm.lengths[strm_type]   = 0;
            strm.data_ptrs[strm_type] = nullptr;
          }
        }
      }
    }
  }

  chunks.host_to_device(stream);
  chunk_streams.host_to_device(stream);

  gpu::set_chunk_columns(orc_table.d_columns, chunks, stream);

  if (orc_table.num_string_columns() != 0) {
    auto d_stripe_dict = orc_table.string_column(0).device_stripe_dict();
    gpu::EncodeStripeDictionaries(d_stripe_dict,
                                  chunks,
                                  orc_table.num_string_columns(),
                                  stripe_bounds.size(),
                                  chunk_streams,
                                  stream);
  }

  gpu::EncodeOrcColumnData(chunks, chunk_streams, stream);
  dictionaries.data.clear();
  dictionaries.index.clear();
  stream.synchronize();

  return {std::move(encoded_data), std::move(chunk_streams)};
}

std::vector<StripeInformation> writer::impl::gather_stripes(
  size_t num_rows,
  size_t num_index_streams,
  host_span<stripe_rowgroups const> stripe_bounds,
  hostdevice_2dvector<gpu::encoder_chunk_streams> *enc_streams,
  hostdevice_2dvector<gpu::StripeStream> *strm_desc)
{
  std::vector<StripeInformation> stripes(stripe_bounds.size());
  for (auto const &stripe : stripe_bounds) {
    for (size_t col_idx = 0; col_idx < enc_streams->size().first; col_idx++) {
      const auto &strm = (*enc_streams)[col_idx][stripe.first];

      // Assign stream data of column data stream(s)
      for (int k = 0; k < gpu::CI_INDEX; k++) {
        const auto stream_id = strm.ids[k];
        if (stream_id != -1) {
          auto *ss           = &(*strm_desc)[stripe.id][stream_id - num_index_streams];
          ss->stream_size    = 0;
          ss->first_chunk_id = stripe.first;
          ss->num_chunks     = stripe.size;
          ss->column_id      = col_idx;
          ss->stream_type    = k;
        }
      }
    }

    auto const stripe_group_end     = *stripe.cend();
    auto const stripe_end           = std::min(stripe_group_end * row_index_stride_, num_rows);
    stripes[stripe.id].numberOfRows = stripe_end - stripe.first * row_index_stride_;
  }

  strm_desc->host_to_device(stream);
  gpu::CompactOrcDataStreams(*strm_desc, *enc_streams, stream);
  strm_desc->device_to_host(stream);
  enc_streams->device_to_host(stream, true);

  return stripes;
}

std::vector<std::vector<uint8_t>> writer::impl::gather_statistic_blobs(
  const table_device_view &table,
  host_span<orc_column_view const> columns,
  host_span<stripe_rowgroups const> stripe_bounds)
{
  auto const num_rowgroups = stripes_size(stripe_bounds);
  size_t num_stat_blobs    = (1 + stripe_bounds.size()) * columns.size();
  size_t num_chunks        = num_rowgroups * columns.size();

  std::vector<std::vector<uint8_t>> stat_blobs(num_stat_blobs);
  hostdevice_vector<stats_column_desc> stat_desc(columns.size(), stream);
  hostdevice_vector<statistics_merge_group> stat_merge(num_stat_blobs, stream);
  rmm::device_uvector<statistics_chunk> stat_chunks(num_chunks + num_stat_blobs, stream);
  rmm::device_uvector<statistics_group> stat_groups(num_chunks, stream);

  for (auto const &column : columns) {
    stats_column_desc *desc = &stat_desc[column.flat_index()];
    switch (column.orc_kind()) {
      case TypeKind::BYTE: desc->stats_dtype = dtype_int8; break;
      case TypeKind::SHORT: desc->stats_dtype = dtype_int16; break;
      case TypeKind::INT: desc->stats_dtype = dtype_int32; break;
      case TypeKind::LONG: desc->stats_dtype = dtype_int64; break;
      case TypeKind::FLOAT: desc->stats_dtype = dtype_float32; break;
      case TypeKind::DOUBLE: desc->stats_dtype = dtype_float64; break;
      case TypeKind::BOOLEAN: desc->stats_dtype = dtype_bool; break;
      case TypeKind::DATE: desc->stats_dtype = dtype_int32; break;
      case TypeKind::DECIMAL: desc->stats_dtype = dtype_decimal64; break;
      case TypeKind::TIMESTAMP: desc->stats_dtype = dtype_timestamp64; break;
      case TypeKind::STRING: desc->stats_dtype = dtype_string; break;
      default: desc->stats_dtype = dtype_none; break;
    }
    desc->num_rows   = column.size();
    desc->num_values = column.size();
    if (desc->stats_dtype == dtype_timestamp64) {
      // Timestamp statistics are in milliseconds
      switch (column.scale()) {
        case 9: desc->ts_scale = 1000; break;
        case 6: desc->ts_scale = 0; break;
        case 3: desc->ts_scale = -1000; break;
        case 0: desc->ts_scale = -1000000; break;
        default: desc->ts_scale = 0; break;
      }
    } else {
      desc->ts_scale = 0;
    }
    for (auto const &stripe : stripe_bounds) {
      auto grp         = &stat_merge[column.flat_index() * stripe_bounds.size() + stripe.id];
      grp->col         = stat_desc.device_ptr(column.flat_index());
      grp->start_chunk = static_cast<uint32_t>(column.flat_index() * num_rowgroups + stripe.first);
      grp->num_chunks  = stripe.size;
    }
    statistics_merge_group *col_stats =
      &stat_merge[stripe_bounds.size() * columns.size() + column.flat_index()];
    col_stats->col         = stat_desc.device_ptr(column.flat_index());
    col_stats->start_chunk = static_cast<uint32_t>(column.flat_index() * stripe_bounds.size());
    col_stats->num_chunks  = static_cast<uint32_t>(stripe_bounds.size());
  }
  stat_desc.host_to_device(stream);
  stat_merge.host_to_device(stream);

  rmm::device_uvector<column_device_view> leaf_column_views =
    create_leaf_column_device_views<stats_column_desc>(
      stat_desc, table, stream);  // what needs to be passed here?

  gpu::orc_init_statistics_groups(stat_groups.data(),
                                  stat_desc.device_ptr(),
                                  columns.size(),
                                  num_rowgroups,
                                  row_index_stride_,
                                  stream);

  GatherColumnStatistics(stat_chunks.data(), stat_groups.data(), num_chunks, stream);
  MergeColumnStatistics(stat_chunks.data() + num_chunks,
                        stat_chunks.data(),
                        stat_merge.device_ptr(),
                        stripe_bounds.size() * columns.size(),
                        stream);

  MergeColumnStatistics(stat_chunks.data() + num_chunks + stripe_bounds.size() * columns.size(),
                        stat_chunks.data() + num_chunks,
                        stat_merge.device_ptr(stripe_bounds.size() * columns.size()),
                        columns.size(),
                        stream);
  gpu::orc_init_statistics_buffersize(
    stat_merge.device_ptr(), stat_chunks.data() + num_chunks, num_stat_blobs, stream);
  stat_merge.device_to_host(stream, true);

  hostdevice_vector<uint8_t> blobs(
    stat_merge[num_stat_blobs - 1].start_chunk + stat_merge[num_stat_blobs - 1].num_chunks, stream);
  gpu::orc_encode_statistics(blobs.device_ptr(),
                             stat_merge.device_ptr(),
                             stat_chunks.data() + num_chunks,
                             num_stat_blobs,
                             stream);
  stat_merge.device_to_host(stream);
  blobs.device_to_host(stream, true);

  for (size_t i = 0; i < num_stat_blobs; i++) {
    const uint8_t *stat_begin = blobs.host_ptr(stat_merge[i].start_chunk);
    const uint8_t *stat_end   = stat_begin + stat_merge[i].num_chunks;
    stat_blobs[i].assign(stat_begin, stat_end);
  }

  return stat_blobs;
}

void writer::impl::write_index_stream(int32_t stripe_id,
                                      int32_t stream_id,
                                      host_span<orc_column_view const> columns,
                                      stripe_rowgroups const &rowgroups_range,
                                      host_2dspan<gpu::encoder_chunk_streams const> enc_streams,
                                      host_2dspan<gpu::StripeStream const> strm_desc,
                                      host_span<gpu_inflate_status_s const> comp_out,
                                      StripeInformation *stripe,
                                      orc_streams *streams,
                                      ProtobufWriter *pbw)
{
  row_group_index_info present;
  row_group_index_info data;
  row_group_index_info data2;
  auto kind            = TypeKind::STRUCT;
  auto const column_id = stream_id - 1;

  auto find_record = [=, &strm_desc](gpu::encoder_chunk_streams const &stream,
                                     gpu::StreamIndexType type) {
    row_group_index_info record;
    if (stream.ids[type] > 0) {
      record.pos = 0;
      if (compression_kind_ != NONE) {
        auto const &ss   = strm_desc[stripe_id][stream.ids[type] - (columns.size() + 1)];
        record.blk_pos   = ss.first_block;
        record.comp_pos  = 0;
        record.comp_size = ss.stream_size;
      }
    }
    return record;
  };
  auto scan_record = [=, &comp_out](gpu::encoder_chunk_streams const &stream,
                                    gpu::StreamIndexType type,
                                    row_group_index_info &record) {
    if (record.pos >= 0) {
      record.pos += stream.lengths[type];
      while ((record.pos >= 0) && (record.blk_pos >= 0) &&
             (static_cast<size_t>(record.pos) >= compression_blocksize_) &&
             (record.comp_pos + 3 + comp_out[record.blk_pos].bytes_written <
              static_cast<size_t>(record.comp_size))) {
        record.pos -= compression_blocksize_;
        record.comp_pos += 3 + comp_out[record.blk_pos].bytes_written;
        record.blk_pos += 1;
      }
    }
  };

  // TBD: Not sure we need an empty index stream for column 0
  if (stream_id != 0) {
    const auto &strm = enc_streams[column_id][0];
    present          = find_record(strm, gpu::CI_PRESENT);
    data             = find_record(strm, gpu::CI_DATA);
    data2            = find_record(strm, gpu::CI_DATA2);

    // Change string dictionary to int from index point of view
    kind = columns[column_id].orc_kind();
    if (kind == TypeKind::STRING && columns[column_id].orc_encoding() == DICTIONARY_V2) {
      kind = TypeKind::INT;
    }
  }

  buffer_.resize((compression_kind_ != NONE) ? 3 : 0);

  // Add row index entries
  std::for_each(rowgroups_range.cbegin(), rowgroups_range.cend(), [&](auto rowgroup) {
    pbw->put_row_index_entry(
      present.comp_pos, present.pos, data.comp_pos, data.pos, data2.comp_pos, data2.pos, kind);

    if (stream_id != 0) {
      const auto &strm = enc_streams[column_id][rowgroup];
      scan_record(strm, gpu::CI_PRESENT, present);
      scan_record(strm, gpu::CI_DATA, data);
      scan_record(strm, gpu::CI_DATA2, data2);
    }
  });

  (*streams)[stream_id].length = buffer_.size();
  if (compression_kind_ != NONE) {
    uint32_t uncomp_ix_len = (uint32_t)((*streams)[stream_id].length - 3) * 2 + 1;
    buffer_[0]             = static_cast<uint8_t>(uncomp_ix_len >> 0);
    buffer_[1]             = static_cast<uint8_t>(uncomp_ix_len >> 8);
    buffer_[2]             = static_cast<uint8_t>(uncomp_ix_len >> 16);
  }
  out_sink_->host_write(buffer_.data(), buffer_.size());
  stripe->indexLength += buffer_.size();
}

void writer::impl::write_data_stream(gpu::StripeStream const &strm_desc,
                                     gpu::encoder_chunk_streams const &enc_stream,
                                     uint8_t const *compressed_data,
                                     uint8_t *stream_out,
                                     StripeInformation *stripe,
                                     orc_streams *streams)
{
  const auto length                                        = strm_desc.stream_size;
  (*streams)[enc_stream.ids[strm_desc.stream_type]].length = length;
  if (length == 0) { return; }

  const auto *stream_in = (compression_kind_ == NONE) ? enc_stream.data_ptrs[strm_desc.stream_type]
                                                      : (compressed_data + strm_desc.bfr_offset);

  if (out_sink_->is_device_write_preferred(length)) {
    out_sink_->device_write(stream_in, length, stream);
  } else {
    CUDA_TRY(
      cudaMemcpyAsync(stream_out, stream_in, length, cudaMemcpyDeviceToHost, stream.value()));
    stream.synchronize();

    out_sink_->host_write(stream_out, length);
  }
  stripe->dataLength += length;
}

void writer::impl::add_uncompressed_block_headers(std::vector<uint8_t> &v)
{
  if (compression_kind_ != NONE) {
    size_t uncomp_len = v.size() - 3, pos = 0, block_len;
    while (uncomp_len > compression_blocksize_) {
      block_len  = compression_blocksize_ * 2 + 1;
      v[pos + 0] = static_cast<uint8_t>(block_len >> 0);
      v[pos + 1] = static_cast<uint8_t>(block_len >> 8);
      v[pos + 2] = static_cast<uint8_t>(block_len >> 16);
      pos += 3 + compression_blocksize_;
      v.insert(v.begin() + pos, 3, 0);
      uncomp_len -= compression_blocksize_;
    }
    block_len  = uncomp_len * 2 + 1;
    v[pos + 0] = static_cast<uint8_t>(block_len >> 0);
    v[pos + 1] = static_cast<uint8_t>(block_len >> 8);
    v[pos + 2] = static_cast<uint8_t>(block_len >> 16);
  }
}

writer::impl::impl(std::unique_ptr<data_sink> sink,
                   orc_writer_options const &options,
                   SingleWriteMode mode,
                   rmm::cuda_stream_view stream,
                   rmm::mr::device_memory_resource *mr)
  : compression_kind_(to_orc_compression(options.get_compression())),
    enable_statistics_(options.enable_statistics()),
    out_sink_(std::move(sink)),
    single_write_mode(mode == SingleWriteMode::YES),
    user_metadata(options.get_metadata()),
    stream(stream),
    _mr(mr)
{
  init_state();
}

writer::impl::impl(std::unique_ptr<data_sink> sink,
                   chunked_orc_writer_options const &options,
                   SingleWriteMode mode,
                   rmm::cuda_stream_view stream,
                   rmm::mr::device_memory_resource *mr)
  : compression_kind_(to_orc_compression(options.get_compression())),
    enable_statistics_(options.enable_statistics()),
    out_sink_(std::move(sink)),
    single_write_mode(mode == SingleWriteMode::YES),
    stream(stream),
    _mr(mr)
{
  if (options.get_metadata() != nullptr) {
    user_metadata_with_nullability = *options.get_metadata();
    user_metadata                  = &user_metadata_with_nullability;
  }

  init_state();
}

writer::impl::~impl() { close(); }

void writer::impl::init_state()
{
  // Write file header
  out_sink_->host_write(MAGIC, std::strlen(MAGIC));
}

/**
 * @brief Iterates over row indexes but returns the corresponding rowgroup index.
 *
 */
struct rowgroup_iterator {
  using difference_type   = long;
  using value_type        = int;
  using pointer           = int *;
  using reference         = int &;
  using iterator_category = thrust::output_device_iterator_tag;
  size_type idx;
  size_type rowgroup_size;

  CUDA_HOST_DEVICE_CALLABLE rowgroup_iterator(int offset, size_type rg_size)
    : idx{offset}, rowgroup_size{rg_size}
  {
  }
  CUDA_HOST_DEVICE_CALLABLE value_type operator*() const { return idx / rowgroup_size; }
  CUDA_HOST_DEVICE_CALLABLE auto operator+(int i) const
  {
    return rowgroup_iterator{idx + i, rowgroup_size};
  }
  CUDA_HOST_DEVICE_CALLABLE rowgroup_iterator &operator++()
  {
    ++idx;
    return *this;
  }
  CUDA_HOST_DEVICE_CALLABLE value_type operator[](int offset)
  {
    return (idx + offset) / rowgroup_size;
  }
  CUDA_HOST_DEVICE_CALLABLE bool operator!=(rowgroup_iterator const &other)
  {
    return idx != other.idx;
  }
};

void __device__ preorder_append(uint32_t &idx,
                                int32_t parent_idx,
                                device_span<orc_column_device_view> cols,
                                column_device_view col)
{
  auto const current_idx = idx;
  cols[current_idx]      = orc_column_device_view{idx, col, parent_idx};
  idx++;
  if (col.type().id() == type_id::LIST) preorder_append(idx, current_idx, cols, col.child(1));
  if (col.type().id() == type_id::STRUCT)
    for (auto child_idx = 0; child_idx < col.num_child_columns(); ++child_idx)
      preorder_append(idx, current_idx, cols, col.child(child_idx));
};

orc_table_view get_columns_info(table_view const &table,
                                table_device_view const &d_table,
                                table_metadata const *user_metadata,
                                rmm::cuda_stream_view stream)
{
  std::vector<orc_column_view> orc_columns;
  std::vector<int> str_col_flat_indexes;

  std::function<void(column_view const &)> append_orc_column = [&](column_view const &col) {
    orc_columns.emplace_back(orc_columns.size(), str_col_flat_indexes.size(), col, user_metadata);
    if (orc_columns.back().is_string()) {
      str_col_flat_indexes.push_back(orc_columns.back().flat_index());
    }
    if (col.type().id() == type_id::LIST) append_orc_column(col.child(1));
    if (col.type().id() == type_id::STRUCT)
      std::for_each(col.child_begin(), col.child_end(), append_orc_column);
  };

  for (auto const &column : table) { append_orc_column(column); }

  rmm::device_uvector<orc_column_device_view> d_orc_columns(orc_columns.size(), stream);

  cudf::detail::device_single_thread(
    [d_orc_cols = device_span<orc_column_device_view>{d_orc_columns},
     d_table    = d_table] __device__() mutable {
      uint32_t idx = 0;
      for (auto const &column : d_table) { preorder_append(idx, -1, d_orc_cols, column); }
    },
    stream);

  return {std::move(orc_columns), std::move(d_orc_columns), std::move(str_col_flat_indexes)};
}

hostdevice_2dvector<rows_range> calculate_rowgroup_sizes(orc_table_view const &orc_table,
                                                         uint32_t rowgroup_size,
                                                         rmm::cuda_stream_view stream)
{
  auto const num_rowgroups =
    cudf::util::div_rounding_up_unsafe<size_t, size_t>(orc_table.num_rows(), rowgroup_size);

  hostdevice_2dvector<rows_range> rowgroup_bounds(num_rowgroups, orc_table.num_columns(), stream);
  thrust::for_each_n(
    rmm::exec_policy(stream),
    thrust::make_counting_iterator(0ul),
    num_rowgroups,
    [cols      = device_span<orc_column_device_view const>{orc_table.d_columns},
     rg_bounds = device_2dspan<rows_range>{rowgroup_bounds},
     rowgroup_size] __device__(auto rg_idx) mutable {
      thrust::transform(
        thrust::seq, cols.begin(), cols.end(), rg_bounds[rg_idx].begin(), [&](auto const &col) {
          if (col.parent_index < 0) {
            size_type const rows_begin = rg_idx * rowgroup_size;
            auto const rows_end =
              thrust::min<uint32_t>((rg_idx + 1) * rowgroup_size, col.cudf_column.size());
            return rows_range{rows_begin, rows_end};
          }

          column_device_view parent_col = cols[col.parent_index].cudf_column;
          if (parent_col.type().id() != type_id::LIST) return rg_bounds[rg_idx][col.parent_index];

          auto parent_offsets           = parent_col.child(lists_column_view::offsets_column_index);
          auto const &parent_rows_range = rg_bounds[rg_idx][col.parent_index];
          auto const rows_begin = parent_offsets.element<size_type>(parent_rows_range.begin);
          auto const rows_end   = parent_offsets.element<size_type>(parent_rows_range.end);
          return rows_range{rows_begin, rows_end};
        });
    });
  rowgroup_bounds.device_to_host(stream, true);

  return rowgroup_bounds;
}

// returns host vector of per-rowgroup sizes
encoder_decimal_info decimal_chunk_sizes(orc_table_view &orc_table,
                                         size_type rowgroup_size,
                                         host_span<stripe_rowgroups const> stripes,
                                         rmm::cuda_stream_view stream)
{
  std::map<uint32_t, rmm::device_uvector<uint32_t>> elem_sizes;
  // Compute per-element offsets (within each row group) on the device
  for (auto &orc_col : orc_table.columns) {
    if (orc_col.orc_kind() == DECIMAL) {
      auto &current_sizes =
        elem_sizes
          .insert({orc_col.flat_index(), rmm::device_uvector<uint32_t>(orc_col.size(), stream)})
          .first->second;
      thrust::tabulate(rmm::exec_policy(stream),
                       current_sizes.begin(),
                       current_sizes.end(),
                       [d_cols  = device_span<orc_column_device_view const>{orc_table.d_columns},
                        col_idx = orc_col.flat_index()] __device__(auto idx) {
                         auto const &col = d_cols[col_idx].cudf_column;
                         if (col.is_null(idx)) return 0u;
                         int64_t const element = (col.type().id() == type_id::DECIMAL32)
                                                   ? col.element<int32_t>(idx)
                                                   : col.element<int64_t>(idx);
                         int64_t const sign      = (element < 0) ? 1 : 0;
                         uint64_t zigzaged_value = ((element ^ -sign) * 2) + sign;

                         uint32_t encoded_length = 1;
                         while (zigzaged_value > 127) {
                           zigzaged_value >>= 7u;
                           ++encoded_length;
                         }
                         return encoded_length;
                       });

      // Compute element offsets within each row group
      thrust::inclusive_scan_by_key(rmm::exec_policy(stream),
                                    rowgroup_iterator{0, rowgroup_size},
                                    rowgroup_iterator{orc_col.size(), rowgroup_size},
                                    current_sizes.begin(),
                                    current_sizes.begin());

      orc_col.attach_decimal_offsets(current_sizes.data());
    }
  }
  if (elem_sizes.empty()) return {};

  // Gather the row group sizes and copy to host
  auto const num_rowgroups  = stripes_size(stripes);
  auto d_tmp_rowgroup_sizes = rmm::device_uvector<uint32_t>(num_rowgroups, stream);
  std::map<uint32_t, std::vector<uint32_t>> rg_sizes;
  for (auto const &[col_idx, esizes] : elem_sizes) {
    // Copy last elem in each row group - equal to row group size
    thrust::tabulate(
      rmm::exec_policy(stream),
      d_tmp_rowgroup_sizes.begin(),
      d_tmp_rowgroup_sizes.end(),
      [src = esizes.data(), num_rows = esizes.size(), rg_size = rowgroup_size] __device__(
        auto idx) { return src[thrust::min<size_type>(num_rows, rg_size * (idx + 1)) - 1]; });

    rg_sizes[col_idx] = cudf::detail::make_std_vector_async(d_tmp_rowgroup_sizes, stream);
  }

  return {std::move(elem_sizes), std::move(rg_sizes)};
}

std::map<uint32_t, size_t> decimal_column_sizes(
  std::map<uint32_t, std::vector<uint32_t>> const &chunk_sizes)
{
  std::map<uint32_t, size_t> column_sizes;
  std::transform(chunk_sizes.cbegin(),
                 chunk_sizes.cend(),
                 std::inserter(column_sizes, column_sizes.end()),
                 [](auto const &chunk_size) -> std::pair<uint32_t, size_t> {
                   return {
                     chunk_size.first,
                     std::accumulate(chunk_size.second.cbegin(), chunk_size.second.cend(), 0lu)};
                 });
  return column_sizes;
}

string_dictionaries allocate_dictionaries(orc_table_view const &orc_table,
                                          rmm::cuda_stream_view stream)
{
  std::vector<rmm::device_uvector<uint32_t>> data;
  std::transform(orc_table.string_column_indices.begin(),
                 orc_table.string_column_indices.end(),
                 std::back_inserter(data),
                 [&](auto &idx) {
                   return rmm::device_uvector<uint32_t>(orc_table.columns[idx].size(), stream);
                 });
  std::vector<rmm::device_uvector<uint32_t>> index;
  std::transform(orc_table.string_column_indices.begin(),
                 orc_table.string_column_indices.end(),
                 std::back_inserter(index),
                 [&](auto &idx) {
                   return rmm::device_uvector<uint32_t>(orc_table.columns[idx].size(), stream);
                 });
  stream.synchronize();

  std::vector<device_span<uint32_t>> data_ptrs;
  std::transform(data.begin(), data.end(), std::back_inserter(data_ptrs), [](auto &uvec) {
    return device_span<uint32_t>{uvec};
  });
  std::vector<device_span<uint32_t>> index_ptrs;
  std::transform(index.begin(), index.end(), std::back_inserter(index_ptrs), [](auto &uvec) {
    return device_span<uint32_t>{uvec};
  });

  return {std::move(data),
          std::move(index),
          cudf::detail::make_device_uvector_sync(data_ptrs, stream),
          cudf::detail::make_device_uvector_sync(index_ptrs, stream)};
}

void writer::impl::write(table_view const &table)
{
  CUDF_EXPECTS(not closed, "Data has already been flushed to out and closed");
  auto const num_rows = table.num_rows();

  auto const d_table = table_device_view::create(table, stream);

  auto orc_table = get_columns_info(table, *d_table, user_metadata, stream);

  auto const rowgroup_bounds = calculate_rowgroup_sizes(orc_table, row_index_stride_, stream);
  auto const num_rowgroups   = rowgroup_bounds.size().first;

  auto dictionaries = allocate_dictionaries(orc_table, stream);

  // Build per-column dictionary indices
  const auto num_dict_chunks = num_rowgroups * orc_table.num_string_columns();
  hostdevice_vector<gpu::DictionaryChunk> dict(num_dict_chunks, stream);
  if (orc_table.num_string_columns() != 0) {
    init_dictionaries(orc_table, dictionaries.d_data, dictionaries.d_index, &dict);
  }

  // Decide stripe boundaries early on, based on uncompressed size
  auto const stripe_bounds = gather_stripe_info(orc_table.columns, num_rowgroups);

  // Build stripe-level dictionaries
  const auto num_stripe_dict = stripe_bounds.size() * orc_table.num_string_columns();
  hostdevice_vector<gpu::StripeDictionary> stripe_dict(num_stripe_dict, stream);
  if (orc_table.num_string_columns() != 0) {
    build_dictionaries(orc_table, stripe_bounds, dict, dictionaries.index, stripe_dict);
  }

  auto dec_chunk_sizes = decimal_chunk_sizes(orc_table, row_index_stride_, stripe_bounds, stream);

  auto streams = create_streams(
    orc_table.columns, stripe_bounds, decimal_column_sizes(dec_chunk_sizes.rg_sizes));
  auto enc_data = encode_columns(
    orc_table, std::move(dictionaries), std::move(dec_chunk_sizes), stripe_bounds, streams);

  // Assemble individual disparate column chunks into contiguous data streams
  size_type const num_index_streams = (orc_table.num_columns() + 1);
  const auto num_data_streams       = streams.size() - num_index_streams;
  hostdevice_2dvector<gpu::StripeStream> strm_descs(stripe_bounds.size(), num_data_streams, stream);
  auto stripes =
    gather_stripes(num_rows, num_index_streams, stripe_bounds, &enc_data.streams, &strm_descs);

  // Gather column statistics
  std::vector<ColStatsBlob> column_stats;
  if (enable_statistics_ && table.num_columns() > 0 && num_rows > 0) {
    column_stats = gather_statistic_blobs(*d_table, orc_table.columns, stripe_bounds);
  }

  // Allocate intermediate output stream buffer
  size_t compressed_bfr_size   = 0;
  size_t num_compressed_blocks = 0;
  auto stream_output           = [&]() {
    size_t max_stream_size = 0;
    bool all_device_write  = true;

    for (size_t stripe_id = 0; stripe_id < stripe_bounds.size(); stripe_id++) {
      for (size_t i = 0; i < num_data_streams; i++) {  // TODO range for (at least)
        gpu::StripeStream *ss = &strm_descs[stripe_id][i];
        if (!out_sink_->is_device_write_preferred(ss->stream_size)) { all_device_write = false; }
        size_t stream_size = ss->stream_size;
        if (compression_kind_ != NONE) {
          ss->first_block = num_compressed_blocks;
          ss->bfr_offset  = compressed_bfr_size;

          auto num_blocks = std::max<uint32_t>(
            (stream_size + compression_blocksize_ - 1) / compression_blocksize_, 1);
          stream_size += num_blocks * 3;
          num_compressed_blocks += num_blocks;
          compressed_bfr_size += stream_size;
        }
        max_stream_size = std::max(max_stream_size, stream_size);
      }
    }

    if (all_device_write) {
      return pinned_buffer<uint8_t>{nullptr, cudaFreeHost};
    } else {
      return pinned_buffer<uint8_t>{[](size_t size) {
                                      uint8_t *ptr = nullptr;
                                      CUDA_TRY(cudaMallocHost(&ptr, size));
                                      return ptr;
                                    }(max_stream_size),
                                    cudaFreeHost};
    }
  }();

  // Compress the data streams
  rmm::device_buffer compressed_data(compressed_bfr_size, stream);
  hostdevice_vector<gpu_inflate_status_s> comp_out(num_compressed_blocks, stream);
  hostdevice_vector<gpu_inflate_input_s> comp_in(num_compressed_blocks, stream);
  if (compression_kind_ != NONE) {
    strm_descs.host_to_device(stream);
    gpu::CompressOrcDataStreams(static_cast<uint8_t *>(compressed_data.data()),
                                num_compressed_blocks,
                                compression_kind_,
                                compression_blocksize_,
                                strm_descs,
                                enc_data.streams,
                                comp_in.device_ptr(),
                                comp_out.device_ptr(),
                                stream);
    strm_descs.device_to_host(stream);
    comp_out.device_to_host(stream, true);
  }

  ProtobufWriter pbw_(&buffer_);

  // Write stripes
  for (size_t stripe_id = 0; stripe_id < stripes.size(); ++stripe_id) {
    auto const &rowgroups_range = stripe_bounds[stripe_id];
    auto &stripe                = stripes[stripe_id];

    stripe.offset = out_sink_->bytes_written();

    // Column (skippable) index streams appear at the start of the stripe
    for (size_type stream_id = 0; stream_id < num_index_streams; ++stream_id) {
      write_index_stream(stripe_id,
                         stream_id,
                         orc_table.columns,
                         rowgroups_range,
                         enc_data.streams,
                         strm_descs,
                         comp_out,
                         &stripe,
                         &streams,
                         &pbw_);
    }

    // Column data consisting one or more separate streams
    for (auto const &strm_desc : strm_descs[stripe_id]) {
      write_data_stream(strm_desc,
                        enc_data.streams[strm_desc.column_id][rowgroups_range.first],
                        static_cast<uint8_t *>(compressed_data.data()),
                        stream_output.get(),
                        &stripe,
                        &streams);
    }

    // Write stripefooter consisting of stream information
    StripeFooter sf;
    sf.streams = streams;
    sf.columns.resize(orc_table.num_columns() + 1);
    sf.columns[0].kind = DIRECT;
    for (size_t i = 1; i < sf.columns.size(); ++i) {
      sf.columns[i].kind = orc_table.column(i - 1).orc_encoding();
      sf.columns[i].dictionarySize =
        (sf.columns[i].kind == DICTIONARY_V2)
          ? orc_table.column(i - 1).host_stripe_dict(stripe_id)->num_strings
          : 0;
      if (orc_table.column(i - 1).orc_kind() == TIMESTAMP) { sf.writerTimezone = "UTC"; }
    }
    buffer_.resize((compression_kind_ != NONE) ? 3 : 0);
    pbw_.write(sf);
    stripe.footerLength = buffer_.size();
    if (compression_kind_ != NONE) {
      uint32_t uncomp_sf_len = (stripe.footerLength - 3) * 2 + 1;
      buffer_[0]             = static_cast<uint8_t>(uncomp_sf_len >> 0);
      buffer_[1]             = static_cast<uint8_t>(uncomp_sf_len >> 8);
      buffer_[2]             = static_cast<uint8_t>(uncomp_sf_len >> 16);
    }
    out_sink_->host_write(buffer_.data(), buffer_.size());
  }

  if (column_stats.size() != 0) {
    // File-level statistics
    // NOTE: Excluded from chunked write mode to avoid the need for merging stats across calls
    if (single_write_mode) {
      // First entry contains total number of rows
      buffer_.resize(0);
      pbw_.putb(1 * 8 + PB_TYPE_VARINT);
      pbw_.put_uint(num_rows);
      ff.statistics.reserve(1 + orc_table.num_columns());
      ff.statistics.emplace_back(std::move(buffer_));
      // Add file stats, stored after stripe stats in `column_stats`
      ff.statistics.insert(
        ff.statistics.end(),
        std::make_move_iterator(column_stats.begin()) + stripes.size() * orc_table.num_columns(),
        std::make_move_iterator(column_stats.end()));
    }
    // Stripe-level statistics
    size_t first_stripe = md.stripeStats.size();
    md.stripeStats.resize(first_stripe + stripes.size());
    for (size_t stripe_id = 0; stripe_id < stripes.size(); stripe_id++) {
      md.stripeStats[first_stripe + stripe_id].colStats.resize(1 + orc_table.num_columns());
      buffer_.resize(0);
      pbw_.putb(1 * 8 + PB_TYPE_VARINT);
      pbw_.put_uint(stripes[stripe_id].numberOfRows);
      md.stripeStats[first_stripe + stripe_id].colStats[0] = std::move(buffer_);
      for (size_t col_idx = 0; col_idx < orc_table.num_columns(); col_idx++) {
        size_t idx = stripes.size() * col_idx + stripe_id;
        if (idx < column_stats.size()) {
          md.stripeStats[first_stripe + stripe_id].colStats[1 + col_idx] =
            std::move(column_stats[idx]);
        }
      }
    }
  }
  if (ff.headerLength == 0) {
    // First call
    ff.headerLength   = std::strlen(MAGIC);
    ff.rowIndexStride = row_index_stride_;
    ff.types.resize(1 + orc_table.num_columns());
    ff.types[0].kind = STRUCT;
    ff.types[0].subtypes.resize(table.num_columns());
    ff.types[0].fieldNames.resize(table.num_columns());
    for (auto const &column : orc_table.columns) {
      ff.types[column.id()].kind = column.orc_kind();
      if (column.orc_kind() == DECIMAL) {
        ff.types[column.id()].scale     = static_cast<uint32_t>(column.scale());
        ff.types[column.id()].precision = column.precision();
      }
      ff.types[0].subtypes[column.flat_index()]   = column.id();
      ff.types[0].fieldNames[column.flat_index()] = column.orc_name();
    }
  } else {
    // verify the user isn't passing mismatched tables
    CUDF_EXPECTS(ff.types.size() == 1 + orc_table.num_columns(),
                 "Mismatch in table structure between multiple calls to write");
    CUDF_EXPECTS(
      std::all_of(orc_table.columns.cbegin(),
                  orc_table.columns.cend(),
                  [&](auto const &col) { return ff.types[col.id()].kind == col.orc_kind(); }),
      "Mismatch in column types between multiple calls to write");
  }
  ff.stripes.insert(ff.stripes.end(),
                    std::make_move_iterator(stripes.begin()),
                    std::make_move_iterator(stripes.end()));
  ff.numberOfRows += num_rows;
}

void writer::impl::close()
{
  if (closed) { return; }
  closed = true;
  ProtobufWriter pbw_(&buffer_);
  PostScript ps;

  ff.contentLength = out_sink_->bytes_written();
  if (user_metadata) {
    for (auto it = user_metadata->user_data.begin(); it != user_metadata->user_data.end(); it++) {
      ff.metadata.push_back({it->first, it->second});
    }
  }
  // Write statistics metadata
  if (md.stripeStats.size() != 0) {
    buffer_.resize((compression_kind_ != NONE) ? 3 : 0);
    pbw_.write(md);
    add_uncompressed_block_headers(buffer_);
    ps.metadataLength = buffer_.size();
    out_sink_->host_write(buffer_.data(), buffer_.size());
  } else {
    ps.metadataLength = 0;
  }
  buffer_.resize((compression_kind_ != NONE) ? 3 : 0);
  pbw_.write(ff);
  add_uncompressed_block_headers(buffer_);

  // Write postscript metadata
  ps.footerLength         = buffer_.size();
  ps.compression          = compression_kind_;
  ps.compressionBlockSize = compression_blocksize_;
  ps.version              = {0, 12};
  ps.magic                = MAGIC;
  const auto ps_length    = static_cast<uint8_t>(pbw_.write(ps));
  buffer_.push_back(ps_length);
  out_sink_->host_write(buffer_.data(), buffer_.size());
  out_sink_->flush();
}

// Forward to implementation
writer::writer(std::unique_ptr<data_sink> sink,
               orc_writer_options const &options,
               SingleWriteMode mode,
               rmm::cuda_stream_view stream,
               rmm::mr::device_memory_resource *mr)
  : _impl(std::make_unique<impl>(std::move(sink), options, mode, stream, mr))
{
}

// Forward to implementation
writer::writer(std::unique_ptr<data_sink> sink,
               chunked_orc_writer_options const &options,
               SingleWriteMode mode,
               rmm::cuda_stream_view stream,
               rmm::mr::device_memory_resource *mr)
  : _impl(std::make_unique<impl>(std::move(sink), options, mode, stream, mr))
{
}

// Destructor within this translation unit
writer::~writer() = default;

// Forward to implementation
void writer::write(table_view const &table) { _impl->write(table); }

// Forward to implementation
void writer::close() { _impl->close(); }

}  // namespace orc
}  // namespace detail
}  // namespace io
}  // namespace cudf
