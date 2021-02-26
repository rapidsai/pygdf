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
#include <io/utilities/file_utils.hpp>

#include <dlfcn.h>
#include <fcntl.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include <rmm/device_buffer.hpp>

namespace cudf {
namespace io {

file_wrapper::file_wrapper(std::string const &filepath, int flags)
  : fd(open(filepath.c_str(), flags))
{
  CUDF_EXPECTS(fd != -1, "Cannot open file");
}

file_wrapper::file_wrapper(std::string const &filepath, int flags, mode_t mode)
  : fd(open(filepath.c_str(), flags, mode))
{
  CUDF_EXPECTS(fd != -1, "Cannot open file");
}

/**
 * Returns the directory from which the libcudf.so is loaded.
 */
std::string get_libcudf_dir_path()
{
  Dl_info dl_info{};
  dladdr((void *)get_libcudf_dir_path, &dl_info);
  std::string full_path{dl_info.dli_fname};
  auto const dir_path = full_path.substr(0, full_path.find_last_of('/') + 1);
  return dir_path;
}

file_wrapper::~file_wrapper() { close(fd); }

long file_wrapper::size() const
{
  if (_size < 0) {
    struct stat st;
    CUDF_EXPECTS(fstat(fd, &st) != -1, "Cannot query file size");
    _size = static_cast<size_t>(st.st_size);
  }
  return _size;
}

#ifdef CUFILE_INSTALLED
/**
 * @brief Class that provides RAII for cuFile driver management.
 *
 * Should be used as a singleton. Sets the environment path to point to cudf cuFile config file
 * (enables compatilibity mode).
 */
class cufile_driver {
 private:
  cufile_driver()
  {
    // dlopen
    CUDF_EXPECTS(cuFileDriverOpen().err == CU_FILE_SUCCESS, "Failed to initialize cuFile driver");
    // dlsym for each used API
  }

 public:
  static auto const *get_instance()
  {
    static bool first_call = true;
    static std::unique_ptr<cufile_driver> instance;
    if (first_call) {
      try {
        instance = std::unique_ptr<cufile_driver>(new cufile_driver());
      } catch (...) {
        first_call = false;
        throw;
      }
      first_call = false;
    } else if (!instance) {
      CUDF_FAIL("Failed to initialize cuFile driver");
    }
    return instance.get();
  }
  ~cufile_driver() { cuFileDriverClose(); }
  // forwards cufile APIs
};

void cufile_registered_file::register_handle()
{
  CUfileDescr_t cufile_desc{};
  cufile_desc.handle.fd = _file.desc();
  cufile_desc.type      = CU_FILE_HANDLE_TYPE_OPAQUE_FD;
  CUDF_EXPECTS(cuFileHandleRegister(&_handle, &cufile_desc).err == CU_FILE_SUCCESS,
               "Cannot register file handle with cuFile");
}

cufile_registered_file::~cufile_registered_file() { cuFileHandleDeregister(_handle); }

cufile_input_impl::cufile_input_impl(std::string const &filepath)
  : driver{cufile_driver::get_instance()}, cf_file(driver, filepath, O_RDONLY | O_DIRECT)
{
}

std::unique_ptr<datasource::buffer> cufile_input_impl::read(size_t offset,
                                                            size_t size,
                                                            rmm::cuda_stream_view stream)
{
  rmm::device_buffer out_data(size, stream);
  CUDF_EXPECTS(cuFileRead(cf_file.handle(), out_data.data(), size, offset, 0) != -1,
               "cuFile error reading from a file");

  return datasource::buffer::create(std::move(out_data));
}

size_t cufile_input_impl::read(size_t offset,
                               size_t size,
                               uint8_t *dst,
                               rmm::cuda_stream_view stream)
{
  CUDF_EXPECTS(cuFileRead(cf_file.handle(), dst, size, offset, 0) != -1,
               "cuFile error reading from a file");
  // have to read the requested size for now
  return size;
}

cufile_output_impl::cufile_output_impl(std::string const &filepath)
  : driver{cufile_driver::get_instance()},
    cf_file(driver, filepath, O_CREAT | O_RDWR | O_DIRECT, 0664)
{
}

void cufile_output_impl::write(void const *data, size_t offset, size_t size)
{
  CUDF_EXPECTS(cuFileWrite(cf_file.handle(), data, size, offset, 0) != -1,
               "cuFile error writing to a file");
}
#endif

std::unique_ptr<cufile_input_impl> make_cufile_input(std::string const &filepath)
{
#ifdef CUFILE_INSTALLED
  try {
    return std::make_unique<cufile_input_impl>(filepath);
  } catch (...) {
  }
#endif
  return nullptr;
}

std::unique_ptr<cufile_output_impl> make_cufile_output(std::string const &filepath)
{
#ifdef CUFILE_INSTALLED
  try {
    return std::make_unique<cufile_output_impl>(filepath);
  } catch (...) {
  }
#endif
  return nullptr;
}

};  // namespace io
};  // namespace cudf
