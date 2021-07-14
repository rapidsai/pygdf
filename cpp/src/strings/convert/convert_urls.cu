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

#include <cudf/column/column_device_view.cuh>
#include <cudf/column/column_factories.hpp>
#include <cudf/detail/get_value.cuh>
#include <cudf/detail/null_mask.hpp>
#include <cudf/detail/nvtx/ranges.hpp>
#include <cudf/detail/utilities/cuda.cuh>
#include <cudf/strings/convert/convert_urls.hpp>
#include <cudf/strings/detail/utilities.cuh>
#include <cudf/strings/detail/utilities.hpp>
#include <cudf/strings/string_view.cuh>
#include <cudf/strings/strings_column_view.hpp>
#include <cudf/utilities/span.hpp>

#include <rmm/cuda_stream_view.hpp>
#include <rmm/device_uvector.hpp>

#include <cub/cub.cuh>

#include <thrust/binary_search.h>
#include <thrust/count.h>
#include <thrust/iterator/counting_iterator.h>
#include <thrust/scan.h>

#include <algorithm>

using cudf::device_span;

namespace cudf {
namespace strings {
namespace detail {
namespace {
//
// This is the functor for the url_encode() method below.
// Specific requirements are documented in custrings issue #321.
// In summary it converts mostly non-ascii characters and control characters into UTF-8 hex
// characters prefixed with '%'. For example, the space character must be converted to characters
// '%20' where the '20' indicates the hex value for space in UTF-8. Likewise, multi-byte characters
// are converted to multiple hex characters. For example, the é character is converted to characters
// '%C3%A9' where 'C3A9' is the UTF-8 bytes xc3a9 for this character.
//
struct url_encoder_fn {
  column_device_view const d_strings;
  int32_t const* d_offsets{};
  char* d_chars{};

  // utility to create 2-byte hex characters from single binary byte
  __device__ void byte_to_hex(uint8_t byte, char* hex)
  {
    hex[0] = '0';
    if (byte >= 16) {
      uint8_t hibyte = byte / 16;
      hex[0]         = hibyte < 10 ? '0' + hibyte : 'A' + (hibyte - 10);
      byte           = byte - (hibyte * 16);
    }
    hex[1] = byte < 10 ? '0' + byte : 'A' + (byte - 10);
  }

  __device__ bool should_not_url_encode(char ch)
  {
    return (
      (ch >= '0' && ch <= '9') ||  // these are the characters
      (ch >= 'A' && ch <= 'Z') ||  // that are not to be url encoded
      (ch >= 'a' &&
       ch <= 'z') ||  // reference: docs.python.org/3/library/urllib.parse.html#urllib.parse.quote
      (ch == '.') ||
      (ch == '_') || (ch == '~') || (ch == '-'));
  }

  // main part of the functor the performs the url-encoding
  __device__ size_type operator()(size_type idx)
  {
    if (d_strings.is_null(idx)) return 0;
    string_view d_str = d_strings.element<string_view>(idx);
    //
    char* out_ptr    = d_chars ? d_chars + d_offsets[idx] : nullptr;
    size_type nbytes = 0;
    char hex[2];  // two-byte hex max
    for (auto itr = d_str.begin(); itr != d_str.end(); ++itr) {
      auto ch = *itr;
      if (ch < 128) {
        if (should_not_url_encode(static_cast<char>(ch))) {
          nbytes++;
          if (out_ptr) out_ptr = copy_and_increment(out_ptr, d_str.data() + itr.byte_offset(), 1);
        } else  // url-encode everything else
        {
          nbytes += 3;
          if (out_ptr) {
            out_ptr = copy_and_increment(out_ptr, "%", 1);  // add the '%' prefix
            byte_to_hex(static_cast<uint8_t>(ch), hex);     // convert to 2 hex chars
            out_ptr = copy_and_increment(out_ptr, hex, 2);  // add them to the output
          }
        }
      } else  // these are to be utf-8 url-encoded
      {
        uint8_t char_bytes[4];  // holds utf-8 bytes for one character
        size_type char_width = from_char_utf8(ch, reinterpret_cast<char*>(char_bytes));
        nbytes += char_width * 3;  // '%' plus 2 hex chars per byte (example: é is %C3%A9)
        // process each byte in this current character
        for (size_type chidx = 0; out_ptr && (chidx < char_width); ++chidx) {
          out_ptr = copy_and_increment(out_ptr, "%", 1);  // add '%' prefix
          byte_to_hex(char_bytes[chidx], hex);            // convert to 2 hex chars
          out_ptr = copy_and_increment(out_ptr, hex, 2);  // add them to the output
        }
      }
    }
    return nbytes;
  }
};

}  // namespace

//
std::unique_ptr<column> url_encode(
  strings_column_view const& strings,
  rmm::cuda_stream_view stream,
  rmm::mr::device_memory_resource* mr = rmm::mr::get_current_device_resource())
{
  size_type strings_count = strings.size();
  if (strings_count == 0) return make_empty_column(data_type{type_id::STRING});

  auto strings_column = column_device_view::create(strings.parent(), stream);
  auto d_strings      = *strings_column;

  // copy null mask
  rmm::device_buffer null_mask = cudf::detail::copy_bitmask(strings.parent(), stream, mr);
  // build offsets column
  auto offsets_transformer_itr = thrust::make_transform_iterator(
    thrust::make_counting_iterator<size_type>(0), url_encoder_fn{d_strings});
  auto offsets_column = make_offsets_child_column(
    offsets_transformer_itr, offsets_transformer_itr + strings_count, stream, mr);
  auto d_offsets = offsets_column->view().data<int32_t>();
  auto const bytes =
    cudf::detail::get_value<int32_t>(offsets_column->view(), strings_count, stream);
  // build chars column
  auto chars_column = create_chars_child_column(bytes, stream, mr);
  auto d_chars      = chars_column->mutable_view().data<char>();
  thrust::for_each_n(rmm::exec_policy(stream),
                     thrust::make_counting_iterator<size_type>(0),
                     strings_count,
                     url_encoder_fn{d_strings, d_offsets, d_chars});

  return make_strings_column(strings_count,
                             std::move(offsets_column),
                             std::move(chars_column),
                             strings.null_count(),
                             std::move(null_mask),
                             stream,
                             mr);
}

}  // namespace detail

// external API
std::unique_ptr<column> url_encode(strings_column_view const& strings,
                                   rmm::mr::device_memory_resource* mr)
{
  CUDF_FUNC_RANGE();
  return detail::url_encode(strings, rmm::cuda_stream_default, mr);
}

namespace detail {
namespace {

// utility to convert a hex char into a single byte
constexpr uint8_t hex_char_to_byte(char ch)
{
  if (ch >= '0' && ch <= '9') return (ch - '0');
  if (ch >= 'A' && ch <= 'F') return (ch - 'A' + 10);  // in hex A=10,B=11,...,F=15
  if (ch >= 'a' && ch <= 'f') return (ch - 'a' + 10);  // same for lower case
  return 0;
}

constexpr bool is_hex_digit(char ch)
{
  return (ch >= '0' && ch <= '9') || (ch >= 'A' && ch <= 'F') || (ch >= 'a' && ch <= 'f');
}

__forceinline__ __device__ bool is_escape_char(char const* const ptr)
{
  return (ptr[0] == '%' && is_hex_digit(ptr[1]) && is_hex_digit(ptr[2]));
}

/**
 * @brief Count the number of characters of each string after URL decoding.
 *
 * @tparam threadblock_size Number of threads in a threadblock. This template argument must be a
 * multiple of `cudf::detail::warp_size`.
 * @tparam block_size Number of characters which will be loaded into the shared memory at a time.
 *
 * @param[in] in_chars Character buffer for the input string column.
 * @param[in] in_offsets Offset value of each string associated with `in_chars`.
 * @param[out] out_counts Number of characters in each decode URL.
 * @param[in] num_strings Number of strings to count the number of decoded characters.
 */
template <int threadblock_size, int block_size>
__global__ void url_decode_char_counter(char const* const in_chars,
                                        int32_t const* const in_offsets,
                                        int32_t* const out_counts,
                                        int32_t const num_strings)
{
  constexpr int warps_per_threadblock = threadblock_size / cudf::detail::warp_size;
  __shared__ char temporary_buffer[warps_per_threadblock][block_size + 2];
  __shared__ typename cub::WarpReduce<int8_t>::TempStorage cub_storage[warps_per_threadblock];

  int global_thread_id  = blockIdx.x * blockDim.x + threadIdx.x;
  int global_warp_id    = global_thread_id / cudf::detail::warp_size;
  int local_warp_id     = threadIdx.x / cudf::detail::warp_size;
  int warp_lane         = threadIdx.x % cudf::detail::warp_size;
  int nwarps            = gridDim.x * blockDim.x / cudf::detail::warp_size;
  char* in_chars_shared = temporary_buffer[local_warp_id];

  // Loop through strings, and assign each string to a warp.
  for (size_type row_idx = global_warp_id; row_idx < num_strings; row_idx += nwarps) {
    auto in_chars_string      = in_chars + in_offsets[row_idx];
    auto string_length        = in_offsets[row_idx + 1] - in_offsets[row_idx];
    int nblocks               = (string_length + block_size - 1) / block_size;
    int32_t escape_char_count = 0;

    for (int block_idx = 0; block_idx < nblocks; block_idx++) {
      int string_length_block = std::min(block_size, string_length - block_size * block_idx);

      // Each warp collectively loads input characters of the current block to the shared memory.
      // Two halo cells with 0s are added after the input characters to avoid branches when testing
      // escape characters.
      for (int char_idx = warp_lane; char_idx < string_length_block + 2;
           char_idx += cudf::detail::warp_size) {
        char ch    = 0;
        int in_idx = block_idx * block_size + char_idx;
        if (in_idx < string_length) ch = in_chars_string[in_idx];
        in_chars_shared[char_idx] = ch;
      }

      __syncwarp();

      // `char_idx_start` represents the start character index of the current warp.
      for (int char_idx_start = 0; char_idx_start < string_length_block;
           char_idx_start += cudf::detail::warp_size) {
        int char_idx = char_idx_start + warp_lane;
        int8_t is_ichar_escape_char =
          (char_idx < string_length_block && is_escape_char(in_chars_shared + char_idx)) ? 1 : 0;

        // Warp-wise reduction to calculate the number of escape characters.
        // All threads in the warp participate in the reduction, even if `char_idx` is beyond
        // `string_length_block`.
        int8_t total_escape_char =
          cub::WarpReduce<int8_t>(cub_storage[local_warp_id]).Sum(is_ichar_escape_char);

        if (warp_lane == 0) { escape_char_count += total_escape_char; }

        __syncwarp();
      }
    }
    // URL decoding replaces 3 bytes with 1 for each escape character.
    if (warp_lane == 0) { out_counts[row_idx] = string_length - escape_char_count * 2; }
  }
}

/**
 * @brief Decode and copy from the input char column to the output char column.
 *
 * @tparam threadblock_size Number of threads in a threadblock. This template argument must be a
 * multiple of `cudf::detail::warp_size`.
 * @tparam block_size Number of characters which will be loaded into the shared memory at a time.
 *
 * @param[in] in_chars Character buffer for the input string column.
 * @param[in] in_offsets Offset value of each string associated with `in_chars`.
 * @param[out] out_chars Character buffer for the output string column.
 * @param[in] out_offsets Offset value of each string associated with `out_chars`.
 * @param[in] num_strings Number of strings to decode and copy.
 */
template <int threadblock_size, int block_size>
__global__ void url_decode_char_replacer(char const* const in_chars,
                                         int32_t const* const in_offsets,
                                         char* const out_chars,
                                         int32_t const* const out_offsets,
                                         int32_t const num_strings)
{
  constexpr int warps_per_threadblock = threadblock_size / cudf::detail::warp_size;
  __shared__ char temporary_buffer[warps_per_threadblock][block_size + 4];
  __shared__ typename cub::WarpScan<int8_t>::TempStorage cub_storage[warps_per_threadblock];
  __shared__ int out_idx[warps_per_threadblock];

  int global_thread_id  = blockIdx.x * blockDim.x + threadIdx.x;
  int global_warp_id    = global_thread_id / cudf::detail::warp_size;
  int local_warp_id     = threadIdx.x / cudf::detail::warp_size;
  int warp_lane         = threadIdx.x % cudf::detail::warp_size;
  int nwarps            = gridDim.x * blockDim.x / cudf::detail::warp_size;
  char* in_chars_shared = temporary_buffer[local_warp_id];

  // Loop through strings, and assign each string to a warp
  for (size_type row_idx = global_warp_id; row_idx < num_strings; row_idx += nwarps) {
    auto in_chars_string  = in_chars + in_offsets[row_idx];
    auto out_chars_string = out_chars + out_offsets[row_idx];
    auto string_length    = in_offsets[row_idx + 1] - in_offsets[row_idx];
    int nblocks           = (string_length + block_size - 1) / block_size;

    if (warp_lane == cudf::detail::warp_size - 1) { out_idx[local_warp_id] = 0; }

    for (int block_idx = 0; block_idx < nblocks; block_idx++) {
      int string_length_block = std::min(block_size, string_length - block_size * block_idx);

      // Each warp collectively loads input characters of the current block to shared memory.
      // Two halo cells with 0s before and after the input characters are added. The halo cells are
      // used to test whether the current location as well as the previous two locations are escape
      // characters, without branches.
      for (int char_idx = warp_lane; char_idx < string_length_block + 4;
           char_idx += cudf::detail::warp_size) {
        char ch    = 0;
        int in_idx = block_idx * block_size + char_idx - 2;
        if (in_idx >= 0 && in_idx < string_length) ch = in_chars_string[in_idx];
        in_chars_shared[char_idx] = ch;
      }

      __syncwarp();

      // `char_idx_start` represents the start character index of the current warp.
      for (int char_idx_start = 0; char_idx_start < string_length_block;
           char_idx_start += cudf::detail::warp_size) {
        int char_idx = char_idx_start + warp_lane;
        // The current thread should output a character if it is not part of an escape sequence
        // starting at the previous two locations.
        int8_t out_size =
          (char_idx >= string_length_block || is_escape_char(in_chars_shared + char_idx) ||
           is_escape_char(in_chars_shared + char_idx + 1))
            ? 0
            : 1;

        // Warp-wise prefix sum to establish output location of the current thread.
        // All threads in the warp participate in the prefix sum, even if `char_idx` is beyond
        // `string_length_block`.
        int8_t out_offset;
        cub::WarpScan<int8_t>(cub_storage[local_warp_id]).ExclusiveSum(out_size, out_offset);

        if (out_size == 1) {
          char ch;
          if (is_escape_char(in_chars_shared + char_idx + 2)) {
            // If the current location is the start of an escape sequence, load and decode.
            ch = (hex_char_to_byte(in_chars_shared[char_idx + 3]) << 4) |
                 hex_char_to_byte(in_chars_shared[char_idx + 4]);
          } else {
            // If the current location is not the start of an escape sequence, load directly.
            ch = in_chars_shared[char_idx + 2];
          }
          out_chars_string[out_idx[local_warp_id] + out_offset] = ch;
        }

        if (warp_lane == cudf::detail::warp_size - 1) {
          out_idx[local_warp_id] += (out_offset + out_size);
        };

        __syncwarp();
      }
    }
  }
}

}  // namespace

//
std::unique_ptr<column> url_decode(
  strings_column_view const& strings,
  rmm::cuda_stream_view stream,
  rmm::mr::device_memory_resource* mr = rmm::mr::get_current_device_resource())
{
  constexpr int threadblock_size = 128;
  constexpr int block_size       = 256;
  constexpr int num_threadblocks = 65536;

  size_type strings_count = strings.size();
  if (strings_count == 0) return make_empty_column(data_type{type_id::STRING});

  auto offset_count = strings_count + 1;
  auto d_in_offsets = strings.offsets().data<int32_t>() + strings.offset();
  auto d_in_chars   = strings.chars().data<char>();

  // build offsets column
  auto offsets_column = make_numeric_column(
    data_type{type_id::INT32}, offset_count, mask_state::UNALLOCATED, stream, mr);

  // count number of bytes in each string after decoding and store it in offsets_column
  auto offsets_view         = offsets_column->view();
  auto offsets_mutable_view = offsets_column->mutable_view();
  url_decode_char_counter<threadblock_size, block_size>
    <<<num_threadblocks, threadblock_size, 0, stream.value()>>>(
      d_in_chars, d_in_offsets, offsets_mutable_view.begin<int32_t>() + 1, strings_count);

  // use inclusive_scan to transform number of bytes into offsets
  thrust::inclusive_scan(rmm::exec_policy(stream),
                         offsets_view.begin<int32_t>() + 1,
                         offsets_view.begin<int32_t>() + offset_count,
                         offsets_mutable_view.begin<int32_t>() + 1);

  // set the first element of the offset column to 0
  CUDA_TRY(
    cudaMemsetAsync(offsets_mutable_view.begin<int32_t>(), 0, sizeof(int32_t), stream.value()));

  // copy the total number of characters of all strings combined (last element of the offset column)
  // to the host memory
  int32_t out_chars_bytes;
  CUDA_TRY(cudaMemcpyAsync(&out_chars_bytes,
                           offsets_view.begin<int32_t>() + offset_count - 1,
                           sizeof(int32_t),
                           cudaMemcpyDeviceToHost,
                           stream.value()));
  stream.synchronize();

  // create the chars column
  auto chars_column = create_chars_child_column(out_chars_bytes, stream, mr);
  auto d_out_chars  = chars_column->mutable_view().data<char>();

  // decode and copy the characters from the input column to the output column
  url_decode_char_replacer<threadblock_size, block_size>
    <<<num_threadblocks, threadblock_size, 0, stream.value()>>>(
      d_in_chars,
      d_in_offsets,
      d_out_chars,
      offsets_column->view().begin<int32_t>(),
      strings_count);

  // copy null mask
  rmm::device_buffer null_mask = cudf::detail::copy_bitmask(strings.parent(), stream, mr);

  return make_strings_column(strings_count,
                             std::move(offsets_column),
                             std::move(chars_column),
                             strings.null_count(),
                             std::move(null_mask),
                             stream,
                             mr);
}

}  // namespace detail

// external API

std::unique_ptr<column> url_decode(strings_column_view const& strings,
                                   rmm::mr::device_memory_resource* mr)
{
  CUDF_FUNC_RANGE();
  return detail::url_decode(strings, rmm::cuda_stream_default, mr);
}

}  // namespace strings
}  // namespace cudf
