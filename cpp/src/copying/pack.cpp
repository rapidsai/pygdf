#include <cudf/detail/copy.hpp>
#include <cudf/detail/nvtx/ranges.hpp>

#include <jit/type.h>

namespace cudf {
namespace detail {

namespace {

/**
 * @brief Deserialize a single column into a column_view
 *
 * Deserializes a single column (it's children are assumed to be already deserialized)
 * non-recursively.
 *
 * @param serial_column Serialized column information
 * @param children Children for the column
 * @param base_ptr Base pointer for the entire contiguous buffer from which all columns
 * were serialized into
 * @return Fully formed column_view
 */
column_view deserialize_column(serialized_column serial_column,
                               std::vector<column_view> const& children,
                               uint8_t const* base_ptr)
{
  auto const data_ptr = serial_column.data_offset != -1 ? base_ptr + serial_column.data_offset : 0;
  auto const null_mask_ptr =
    serial_column.null_mask_offset != -1
      ? reinterpret_cast<bitmask_type const*>(base_ptr + serial_column.null_mask_offset)
      : 0;

  return column_view(serial_column.type,
                     serial_column.size,
                     data_ptr,
                     null_mask_ptr,
                     serial_column.null_count,
                     0,
                     children);
}

}  // anonymous namespace

/**
 * @copydoc cudf::detail::pack
 */
packed_columns pack(cudf::table_view const& input,
                    cudaStream_t stream,
                    rmm::mr::device_memory_resource* mr)
{
  // do a contiguous_split with no splits to get the memory for the table
  // arranged as we want it
  auto contig_split_result = cudf::detail::contiguous_split(input, {}, stream, mr);
  return std::move(contig_split_result[0].data);
}

/**
 * @copydoc cudf::detail::unpack
 */
table_view unpack(uint8_t const* metadata, uint8_t const* gpu_data)
{
  // gpu data can be null if everything is empty but the metadata must always be valid
  CUDF_EXPECTS(metadata != nullptr, "Encountered invalid packed column input");
  auto serialized_columns = reinterpret_cast<serialized_column const*>(metadata);
  uint8_t const* base_ptr = gpu_data;
  // first entry is a stub where size == the total # of top level columns (see contiguous_split.cu)
  auto const num_columns = serialized_columns[0].size;
  size_t current_index   = 1;

  std::function<std::vector<column_view>(size_type)> get_columns;
  get_columns = [&serialized_columns, &current_index, base_ptr, &get_columns](size_t num_columns) {
    std::vector<column_view> cols;
    for (size_t i = 0; i < num_columns; i++) {
      auto serial_column = serialized_columns[current_index];
      current_index++;

      std::vector<column_view> children = get_columns(serial_column.num_children);

      cols.emplace_back(deserialize_column(serial_column, children, base_ptr));
    }

    return cols;
  };

  return table_view{get_columns(num_columns)};
}

}  // namespace detail

/**
 * @copydoc cudf::pack
 */
packed_columns pack(cudf::table_view const& input, rmm::mr::device_memory_resource* mr)
{
  CUDF_FUNC_RANGE();
  return detail::pack(input, 0, mr);
}

/**
 * @copydoc cudf::unpack
 */
table_view unpack(packed_columns const& input)
{
  CUDF_FUNC_RANGE();
  return detail::unpack(input.metadata->data(),
                        reinterpret_cast<uint8_t const*>(input.gpu_data->data()));
}

/**
 * @copydoc cudf::unpack
 */
table_view unpack(uint8_t const* metadata, uint8_t const* gpu_data)
{
  CUDF_FUNC_RANGE();
  return detail::unpack(metadata, gpu_data);
}

}  // namespace cudf