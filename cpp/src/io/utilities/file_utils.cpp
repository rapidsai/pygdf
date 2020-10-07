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

/**
 * @brief Class that provides RAII for cuFile driver management.
 *
 * Should be used as a singleton. Sets the environment path to point to cudf cuFile config file
 * (enables compatilibity mode).
 */
struct cufile_driver {
  cufile_driver()
  {
    // Unless CUFILE_ENV_PATH_JSON is already set, set the env var to point to a config file with
    // enabled compatiblity mode
    auto const cufile_config_path = get_libcudf_dir_path() + "config/cufile.json";
    CUDF_EXPECTS(setenv("CUFILE_ENV_PATH_JSON", cufile_config_path.c_str(), 0) == 0,
                 "Failed to set the cuFile config file environment variable.");

    CUDF_EXPECTS(cuFileDriverOpen().err == CU_FILE_SUCCESS, "Failed to initialize cuFile driver");
  }
  ~cufile_driver() { cuFileDriverClose(); }
};

/**
 * @brief Initializes the cuFile driver.
 *
 * Needs to be called before any cuFile operation.
 */
void init_cufile_driver() { static cufile_driver driver; }

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

cufile_registered_file::cufile_registered_file(int fd)
{
  init_cufile_driver();

  CUfileDescr_t cufile_desc{};
  cufile_desc.handle.fd = fd;
  cufile_desc.type      = CU_FILE_HANDLE_TYPE_OPAQUE_FD;
  CUDF_EXPECTS(cuFileHandleRegister(&handle, &cufile_desc).err == CU_FILE_SUCCESS,
               "Cannot register file handle with cuFile");
}

cufile_registered_file::~cufile_registered_file() { cuFileHandleDeregister(handle); }

cufile_input::cufile_input(std::string const &filepath)
  : cufile_io_base(filepath, O_RDONLY | O_DIRECT)
{
  init_cufile_driver();
}

std::unique_ptr<datasource::buffer> cufile_input::read(size_t offset, size_t size)
{
  rmm::device_buffer out_data(size);
  CUDF_EXPECTS(cuFileRead(cf_file.handle, out_data.data(), size, offset, 0) != -1,
               "cuFile error reading from a file");

  return datasource::buffer::create(std::move(out_data));
}

size_t cufile_input::read(size_t offset, size_t size, uint8_t *dst)
{
  CUDF_EXPECTS(cuFileRead(cf_file.handle, dst, size, offset, 0) != -1,
               "cuFile error reading from a file");
  // have to read the requested size for now
  return size;
}

cufile_output::cufile_output(std::string const &filepath)
  : cufile_io_base(filepath, O_CREAT | O_RDWR | O_DIRECT, 0664)
{
  init_cufile_driver();
}

void cufile_output::write(void const *data, size_t offset, size_t size)
{
  CUDF_EXPECTS(cuFileWrite(cf_file.handle, data, size, offset, 0) != -1,
               "cuFile error writing to a file");
}

};  // namespace io
};  // namespace cudf