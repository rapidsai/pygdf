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

#pragma once

#include <rmm/mr/device/device_memory_resource.hpp>

namespace cudf {

/**
 * @brief Resource that uses `Upstream` to allocate memory and tracks the current and peak memory
 * allocated using this resource
 *
 * An instance of this resource can be constructed with an existing, upstream resource in order to
 * satisfy allocation requests and track memory use.
 *
 * @tparam Upstream Type of the upstream resource used for allocation/deallocation.
 */
template <typename Upstream>
class memory_tracking_resource final : public rmm::mr::device_memory_resource {
 public:
  /**
   * @brief Construct a new tracking resource adaptor using `upstream` to satisfy allocation
   * requests and tracking information about each allocation/free to the members
   * current_allocated_size_ and max_allocated_size_.
   *
   * @throws `rmm::logic_error` if `upstream == nullptr`
   *
   * @param upstream The resource used for allocating/deallocating device memory
   */
  memory_tracking_resource(Upstream* upstream) : upstream_{upstream}
  {
    RMM_EXPECTS(nullptr != upstream, "Unexpected null upstream resource pointer.");
  }

  memory_tracking_resource()                                = delete;
  ~memory_tracking_resource()                               = default;
  memory_tracking_resource(memory_tracking_resource const&) = delete;
  memory_tracking_resource(memory_tracking_resource&&)      = default;
  memory_tracking_resource& operator=(memory_tracking_resource const&) = delete;
  memory_tracking_resource& operator=(memory_tracking_resource&&) = default;

  /**
   * @brief Return pointer to the upstream resource.
   *
   * @return Upstream* Pointer to the upstream resource.
   */
  Upstream* get_upstream() const noexcept { return upstream_; }

  /**
   * @brief Checks whether the upstream resource supports streams.
   *
   * @return true The upstream resource supports streams
   * @return false The upstream resource does not support streams.
   */
  bool supports_streams() const noexcept override { return upstream_->supports_streams(); }

  /**
   * @brief Query whether the resource supports the get_mem_info API.
   *
   * @return bool true if the upstream resource supports get_mem_info, false otherwise.
   */
  bool supports_get_mem_info() const noexcept override
  {
    return upstream_->supports_get_mem_info();
  }

  size_t max_allocated_size() const noexcept { return max_allocated_size_; }
  size_t current_allocated_size() const noexcept { return current_allocated_size_; }

 private:
  /**
   * @brief Allocates memory of size at least `bytes` using the upstream resource and updates the
   * size of memory in use.
   *
   * If the upstream allocation is successful updates the current total memory and peak memory
   * allocated with this resource
   *
   * The returned pointer has at least 256B alignment.
   *
   * @throws `rmm::bad_alloc` if the requested allocation could not be fulfilled
   * by the upstream resource.
   *
   * @param bytes The size, in bytes, of the allocation
   * @param stream Stream on which to perform the allocation
   * @return void* Pointer to the newly allocated memory
   */
  void* do_allocate(std::size_t bytes, rmm::cuda_stream_view stream) override
  {
    auto const p = upstream_->allocate(bytes, stream);
    current_allocated_size_ += bytes;
    max_allocated_size_ = std::max(current_allocated_size_, max_allocated_size_);
    return p;
  }

  /**
   * @brief Free allocation of size `bytes` pointed to by `p` and log the deallocation.
   *
   * Updates the current total memory and peak memory allocated with this resource
   *
   * @throws Nothing.
   *
   * @param p Pointer to be deallocated
   * @param bytes Size of the allocation
   * @param stream Stream on which to perform the deallocation
   */
  void do_deallocate(void* p, std::size_t bytes, rmm::cuda_stream_view stream) override
  {
    current_allocated_size_ -= bytes;
    upstream_->deallocate(p, bytes, stream);
  }

  /**
   * @brief Compare the upstream resource to another.
   *
   * @throws Nothing.
   *
   * @param other The other resource to compare to
   * @return true If the two resources are equivalent
   * @return false If the two resources are not equal
   */
  bool do_is_equal(device_memory_resource const& other) const noexcept override
  {
    if (this == &other)
      return true;
    else {
      memory_tracking_resource<Upstream> const* cast =
        dynamic_cast<memory_tracking_resource<Upstream> const*>(&other);
      if (cast != nullptr)
        return upstream_->is_equal(*cast->get_upstream());
      else
        return upstream_->is_equal(other);
    }
  }

  /**
   * @brief Get free and available memory from upstream resource.
   *
   * @throws `rmm::cuda_error` if unable to retrieve memory info.
   *
   * @param stream Stream on which to get the mem info.
   * @return std::pair contaiing free_size and total_size of memory
   */
  std::pair<size_t, size_t> do_get_mem_info(rmm::cuda_stream_view stream) const override
  {
    return upstream_->get_mem_info(stream);
  }

  size_t current_allocated_size_ = 0;
  size_t max_allocated_size_     = 0;

  Upstream* upstream_;  ///< The upstream resource used for satisfying
                        ///< allocation requests
};

}  // namespace cudf
