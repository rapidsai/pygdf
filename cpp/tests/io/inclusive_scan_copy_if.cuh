#include "csv_test_new.cuh"

template <typename T,
          typename ReduceOp,
          typename UnaryPredicate,
          int BLOCK_DIM_X,
          int ITEMS_PER_THREAD>
__global__ void inclusive_scan_copy_if_kernel(device_span<T> input,
                                              device_span<uint32_t> block_temp,
                                              device_span<uint32_t> output,
                                              ReduceOp reduce_op,
                                              UnaryPredicate predicate_op)
{
  using BlockLoad   = typename cub::BlockLoad<  //
    T,
    BLOCK_DIM_X,
    ITEMS_PER_THREAD,
    cub::BlockLoadAlgorithm::BLOCK_LOAD_TRANSPOSE>;
  using BlockReduce = typename cub::BlockReduce<uint32_t, BLOCK_DIM_X>;
  using BlockScan   = typename cub::BlockScan<uint32_t, BLOCK_DIM_X>;

  __shared__ union {
    typename BlockLoad::TempStorage load;
    typename BlockReduce::TempStorage reduce;
    typename BlockScan::TempStorage scan;
  } temp_storage;

  T thread_data[ITEMS_PER_THREAD];

  uint32_t const block_offset  = (blockIdx.x * blockDim.x) * ITEMS_PER_THREAD;
  uint32_t const thread_offset = threadIdx.x * ITEMS_PER_THREAD;
  uint32_t valid_items         = input.size() - block_offset;

  BlockLoad(temp_storage.load).Load(input.data() + block_offset, thread_data, valid_items);

  uint32_t count_thread = 0;

  // incorperate, predicate, assign

  if (thread_offset < valid_items) {
    if (predicate_op(thread_data[0])) {  //
      count_thread++;
    }
  }

  for (auto i = 1; i < ITEMS_PER_THREAD; i++) {
    if (thread_offset + i >= valid_items) { break; }
    thread_data[i] = reduce_op(thread_data[i - 1], thread_data[i]);
    if (predicate_op(thread_data[i])) {  //
      count_thread++;
    }
  }

  if (output.data() == nullptr) {
    // This is the first pass, so just return the block sums.

    uint32_t count_block = BlockReduce(temp_storage.reduce).Sum(count_thread);

    if (threadIdx.x == 0) { block_temp[blockIdx.x + 1] = count_block; }

    return;
  }

  // This is the second pass.

  uint32_t const block_output_offset = block_temp[blockIdx.x];
  uint32_t thread_output_offset;

  BlockScan(temp_storage.scan).ExclusiveSum(count_thread, thread_output_offset);

  for (auto i = 0; i < ITEMS_PER_THREAD; i++) {
    if (thread_offset + i >= valid_items) { break; }
    if (predicate_op(thread_data[i])) {
      printf("b(%i) t(%i) [%i + %i] = %i + %i | tdata(%i)\n",
             blockIdx.x,
             threadIdx.x,
             block_output_offset,
             thread_output_offset,
             block_offset,
             thread_offset,
             thread_data[i]);
      output[block_output_offset + thread_output_offset++] = block_offset + thread_offset + i;
    }
  }
}

template <typename T, typename ReduceOp, typename UnaryPredicate>
rmm::device_vector<uint32_t>  //
inclusive_scan_copy_if(device_span<T> d_input,
                       ReduceOp reduce,
                       UnaryPredicate predicate,
                       cudaStream_t stream = 0)
{
  {
    enum { BLOCK_DIM_X = 3, ITEMS_PER_THREAD = 7 };

    cudf::detail::grid_1d grid(d_input.size(), BLOCK_DIM_X, ITEMS_PER_THREAD);

    // include leading zero in offsets
    auto d_block_temp = rmm::device_vector<uint32_t>(grid.num_blocks + 1);

    auto kernel =
      inclusive_scan_copy_if_kernel<T, ReduceOp, UnaryPredicate, BLOCK_DIM_X, ITEMS_PER_THREAD>;

    kernel<<<grid.num_blocks, grid.num_threads_per_block, 0, stream>>>(  //
      d_input,
      d_block_temp,
      device_span<uint32_t>(),
      reduce,
      predicate);

    // convert block result sizes to block result offsets.
    thrust::inclusive_scan(rmm::exec_policy(stream)->on(stream),
                           d_block_temp.begin(),
                           d_block_temp.end(),
                           d_block_temp.begin());

    auto d_output = rmm::device_vector<uint32_t>(d_block_temp.back());

    kernel<<<grid.num_blocks, grid.num_threads_per_block, 0, stream>>>(  //
      d_input,
      d_block_temp,
      d_output,
      reduce,
      predicate);

    cudaStreamSynchronize(stream);

    return d_output;

    return {};
  }
}
