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

#include <cudf/column/column.hpp>
#include <cudf/fixed_point/fixed_point.hpp>
#include <cudf/scalar/scalar.hpp>
#include <cudf/strings/string_view.hpp>

#include <rmm/cuda_stream_view.hpp>
#include <rmm/device_buffer.hpp>

#include <string>

namespace cudf {

scalar::scalar(data_type type,
               bool is_valid,
               rmm::cuda_stream_view stream,
               rmm::mr::device_memory_resource* mr)
  : _type(type), _is_valid(is_valid, stream, mr)
{
}

data_type scalar::type() const noexcept { return _type; }

void scalar::set_valid(bool is_valid, rmm::cuda_stream_view stream)
{
  _is_valid.set_value(is_valid, stream);
}

bool scalar::is_valid(rmm::cuda_stream_view stream) const { return _is_valid.value(stream); }

bool* scalar::validity_data() { return _is_valid.data(); }

bool const* scalar::validity_data() const { return _is_valid.data(); }

string_scalar::string_scalar() : scalar(data_type(type_id::STRING)) {}

string_scalar::string_scalar(std::string const& string,
                             bool is_valid,
                             rmm::cuda_stream_view stream,
                             rmm::mr::device_memory_resource* mr)
  : scalar(data_type(type_id::STRING), is_valid), _data(string.data(), string.size(), stream, mr)
{
}

string_scalar::string_scalar(rmm::device_scalar<value_type>& data,
                             bool is_valid,
                             rmm::cuda_stream_view stream,
                             rmm::mr::device_memory_resource* mr)
  : string_scalar(data.value(stream), is_valid, stream, mr)
{
}

string_scalar::string_scalar(value_type const& source,
                             bool is_valid,
                             rmm::cuda_stream_view stream,
                             rmm::mr::device_memory_resource* mr)
  : scalar(data_type(type_id::STRING), is_valid),
    _data(source.data(), source.size_bytes(), stream, mr)
{
}

string_scalar::value_type string_scalar::value(rmm::cuda_stream_view stream) const
{
  return value_type{data(), size()};
}

size_type string_scalar::size() const { return _data.size(); }

const char* string_scalar::data() const { return static_cast<const char*>(_data.data()); }

string_scalar::operator std::string() const { return this->to_string(rmm::cuda_stream_default); }

std::string string_scalar::to_string(rmm::cuda_stream_view stream) const
{
  std::string result;
  result.resize(_data.size());
  CUDA_TRY(cudaMemcpyAsync(
    &result[0], _data.data(), _data.size(), cudaMemcpyDeviceToHost, stream.value()));
  stream.synchronize();
  return result;
}

template <typename T>
fixed_point_scalar<T>::fixed_point_scalar() : scalar(data_type(type_to_id<T>())){};

template <typename T>
fixed_point_scalar<T>::fixed_point_scalar(rep_type value,
                                          numeric::scale_type scale,
                                          bool is_valid,
                                          rmm::cuda_stream_view stream,
                                          rmm::mr::device_memory_resource* mr)
  : scalar{data_type{type_to_id<T>(), static_cast<int32_t>(scale)}, is_valid, stream, mr},
    _data{value}
{
}

template <typename T>
fixed_point_scalar<T>::fixed_point_scalar(rep_type value,
                                          bool is_valid,
                                          rmm::cuda_stream_view stream,
                                          rmm::mr::device_memory_resource* mr)
  : scalar{data_type{type_to_id<T>(), 0}, is_valid, stream, mr}, _data{value}
{
}

template <typename T>
fixed_point_scalar<T>::fixed_point_scalar(T value,
                                          bool is_valid,
                                          rmm::cuda_stream_view stream,
                                          rmm::mr::device_memory_resource* mr)
  : scalar{data_type{type_to_id<T>(), value.scale()}, is_valid, stream, mr}, _data{value.value()}
{
}

template <typename T>
fixed_point_scalar<T>::fixed_point_scalar(rmm::device_scalar<rep_type>&& data,
                                          numeric::scale_type scale,
                                          bool is_valid,
                                          rmm::cuda_stream_view stream,
                                          rmm::mr::device_memory_resource* mr)
  : scalar{data_type{type_to_id<T>(), scale}, is_valid, stream, mr},
    _data{std::forward<rmm::device_scalar<rep_type>>(data)}
{
}

template <typename T>
typename fixed_point_scalar<T>::rep_type fixed_point_scalar<T>::value(
  rmm::cuda_stream_view stream) const
{
  return _data.value(stream);
}

template <typename T>
T fixed_point_scalar<T>::fixed_point_value(rmm::cuda_stream_view stream) const
{
  return value_type{
    numeric::scaled_integer<rep_type>{_data.value(stream), numeric::scale_type{type().scale()}}};
}

template <typename T>
typename fixed_point_scalar<T>::rep_type* fixed_point_scalar<T>::data()
{
  return _data.data();
}

template <typename T>
typename fixed_point_scalar<T>::rep_type const* fixed_point_scalar<T>::data() const
{
  return _data.data();
}

template class fixed_point_scalar<numeric::decimal32>;
template class fixed_point_scalar<numeric::decimal64>;

namespace detail {

template <typename T>
fixed_width_scalar<T>::fixed_width_scalar() : scalar(data_type(type_to_id<T>()))
{
}

template <typename T>
fixed_width_scalar<T>::fixed_width_scalar(T value,
                                          bool is_valid,
                                          rmm::cuda_stream_view stream,
                                          rmm::mr::device_memory_resource* mr)
  : scalar(data_type(type_to_id<T>()), is_valid, stream, mr), _data(value, stream, mr)
{
}

template <typename T>
fixed_width_scalar<T>::fixed_width_scalar(rmm::device_scalar<T>&& data,
                                          bool is_valid,
                                          rmm::cuda_stream_view stream,
                                          rmm::mr::device_memory_resource* mr)
  : scalar(data_type(type_to_id<T>()), is_valid, stream, mr),
    _data{std::forward<rmm::device_scalar<T>>(data)}
{
}

template <typename T>
void fixed_width_scalar<T>::set_value(T value, rmm::cuda_stream_view stream)
{
  _data.set_value(value, stream);
  this->set_valid(true, stream);
}

template <typename T>
T fixed_width_scalar<T>::value(rmm::cuda_stream_view stream) const
{
  return _data.value(stream);
}

template <typename T>
T* fixed_width_scalar<T>::data()
{
  return _data.data();
}

template <typename T>
T const* fixed_width_scalar<T>::data() const
{
  return _data.data();
}

template <typename T>
fixed_width_scalar<T>::operator value_type() const
{
  return this->value(rmm::cuda_stream_default);
}

template class fixed_width_scalar<bool>;
template class fixed_width_scalar<int8_t>;
template class fixed_width_scalar<int16_t>;
template class fixed_width_scalar<int32_t>;
template class fixed_width_scalar<int64_t>;
template class fixed_width_scalar<uint8_t>;
template class fixed_width_scalar<uint16_t>;
template class fixed_width_scalar<uint32_t>;
template class fixed_width_scalar<uint64_t>;
template class fixed_width_scalar<float>;
template class fixed_width_scalar<double>;
template class fixed_width_scalar<timestamp_D>;
template class fixed_width_scalar<timestamp_s>;
template class fixed_width_scalar<timestamp_ms>;
template class fixed_width_scalar<timestamp_us>;
template class fixed_width_scalar<timestamp_ns>;
template class fixed_width_scalar<duration_D>;
template class fixed_width_scalar<duration_s>;
template class fixed_width_scalar<duration_ms>;
template class fixed_width_scalar<duration_us>;
template class fixed_width_scalar<duration_ns>;

}  // namespace detail

template <typename T>
numeric_scalar<T>::numeric_scalar(T value,
                                  bool is_valid,
                                  rmm::cuda_stream_view stream,
                                  rmm::mr::device_memory_resource* mr)
  : detail::fixed_width_scalar<T>(value, is_valid, stream, mr)
{
}

template <typename T>
numeric_scalar<T>::numeric_scalar(rmm::device_scalar<T>&& data,
                                  bool is_valid,
                                  rmm::cuda_stream_view stream,
                                  rmm::mr::device_memory_resource* mr)
  : detail::fixed_width_scalar<T>(std::forward<rmm::device_scalar<T>>(data), is_valid, stream, mr)
{
}

template class numeric_scalar<bool>;
template class numeric_scalar<int8_t>;
template class numeric_scalar<int16_t>;
template class numeric_scalar<int32_t>;
template class numeric_scalar<int64_t>;
template class numeric_scalar<uint8_t>;
template class numeric_scalar<uint16_t>;
template class numeric_scalar<uint32_t>;
template class numeric_scalar<uint64_t>;
template class numeric_scalar<float>;
template class numeric_scalar<double>;

template <typename T>
chrono_scalar<T>::chrono_scalar(T value,
                                bool is_valid,
                                rmm::cuda_stream_view stream,
                                rmm::mr::device_memory_resource* mr)
  : detail::fixed_width_scalar<T>(value, is_valid, stream, mr)
{
}

template <typename T>
chrono_scalar<T>::chrono_scalar(rmm::device_scalar<T>&& data,
                                bool is_valid,
                                rmm::cuda_stream_view stream,
                                rmm::mr::device_memory_resource* mr)
  : detail::fixed_width_scalar<T>(std::forward<rmm::device_scalar<T>>(data), is_valid, stream, mr)
{
}

template class chrono_scalar<timestamp_D>;
template class chrono_scalar<timestamp_s>;
template class chrono_scalar<timestamp_ms>;
template class chrono_scalar<timestamp_us>;
template class chrono_scalar<timestamp_ns>;
template class chrono_scalar<duration_D>;
template class chrono_scalar<duration_s>;
template class chrono_scalar<duration_ms>;
template class chrono_scalar<duration_us>;
template class chrono_scalar<duration_ns>;

template <typename T>
duration_scalar<T>::duration_scalar(rep_type value,
                                    bool is_valid,
                                    rmm::cuda_stream_view stream,
                                    rmm::mr::device_memory_resource* mr)
  : chrono_scalar<T>(T{value}, is_valid, stream, mr)
{
}

template <typename T>
typename duration_scalar<T>::rep_type duration_scalar<T>::count()
{
  return this->value().count();
}

template class duration_scalar<duration_D>;
template class duration_scalar<duration_s>;
template class duration_scalar<duration_ms>;
template class duration_scalar<duration_us>;
template class duration_scalar<duration_ns>;

template <typename T>
typename timestamp_scalar<T>::rep_type timestamp_scalar<T>::ticks_since_epoch()
{
  return this->value().time_since_epoch().count();
}

template class timestamp_scalar<timestamp_D>;
template class timestamp_scalar<timestamp_s>;
template class timestamp_scalar<timestamp_ms>;
template class timestamp_scalar<timestamp_us>;
template class timestamp_scalar<timestamp_ns>;

template <typename T>
template <typename D>
timestamp_scalar<T>::timestamp_scalar(D const& value,
                                      bool is_valid,
                                      rmm::cuda_stream_view stream,
                                      rmm::mr::device_memory_resource* mr)
  : chrono_scalar<T>(T{typename T::duration{value}}, is_valid, stream, mr)
{
}

template timestamp_scalar<timestamp_D>::timestamp_scalar(duration_D const& value,
                                                         bool is_valid,
                                                         rmm::cuda_stream_view stream,
                                                         rmm::mr::device_memory_resource* mr);
template timestamp_scalar<timestamp_D>::timestamp_scalar(int32_t const& value,
                                                         bool is_valid,
                                                         rmm::cuda_stream_view stream,
                                                         rmm::mr::device_memory_resource* mr);
template timestamp_scalar<timestamp_s>::timestamp_scalar(duration_D const& value,
                                                         bool is_valid,
                                                         rmm::cuda_stream_view stream,
                                                         rmm::mr::device_memory_resource* mr);
template timestamp_scalar<timestamp_s>::timestamp_scalar(duration_s const& value,
                                                         bool is_valid,
                                                         rmm::cuda_stream_view stream,
                                                         rmm::mr::device_memory_resource* mr);
template timestamp_scalar<timestamp_s>::timestamp_scalar(int64_t const& value,
                                                         bool is_valid,
                                                         rmm::cuda_stream_view stream,
                                                         rmm::mr::device_memory_resource* mr);
template timestamp_scalar<timestamp_ms>::timestamp_scalar(duration_D const& value,
                                                          bool is_valid,
                                                          rmm::cuda_stream_view stream,
                                                          rmm::mr::device_memory_resource* mr);
template timestamp_scalar<timestamp_ms>::timestamp_scalar(duration_s const& value,
                                                          bool is_valid,
                                                          rmm::cuda_stream_view stream,
                                                          rmm::mr::device_memory_resource* mr);
template timestamp_scalar<timestamp_ms>::timestamp_scalar(duration_ms const& value,
                                                          bool is_valid,
                                                          rmm::cuda_stream_view stream,
                                                          rmm::mr::device_memory_resource* mr);
template timestamp_scalar<timestamp_ms>::timestamp_scalar(int64_t const& value,
                                                          bool is_valid,
                                                          rmm::cuda_stream_view stream,
                                                          rmm::mr::device_memory_resource* mr);
template timestamp_scalar<timestamp_us>::timestamp_scalar(duration_D const& value,
                                                          bool is_valid,
                                                          rmm::cuda_stream_view stream,
                                                          rmm::mr::device_memory_resource* mr);
template timestamp_scalar<timestamp_us>::timestamp_scalar(duration_s const& value,
                                                          bool is_valid,
                                                          rmm::cuda_stream_view stream,
                                                          rmm::mr::device_memory_resource* mr);
template timestamp_scalar<timestamp_us>::timestamp_scalar(duration_ms const& value,
                                                          bool is_valid,
                                                          rmm::cuda_stream_view stream,
                                                          rmm::mr::device_memory_resource* mr);
template timestamp_scalar<timestamp_us>::timestamp_scalar(duration_us const& value,
                                                          bool is_valid,
                                                          rmm::cuda_stream_view stream,
                                                          rmm::mr::device_memory_resource* mr);
template timestamp_scalar<timestamp_us>::timestamp_scalar(int64_t const& value,
                                                          bool is_valid,
                                                          rmm::cuda_stream_view stream,
                                                          rmm::mr::device_memory_resource* mr);
template timestamp_scalar<timestamp_ns>::timestamp_scalar(duration_D const& value,
                                                          bool is_valid,
                                                          rmm::cuda_stream_view stream,
                                                          rmm::mr::device_memory_resource* mr);
template timestamp_scalar<timestamp_ns>::timestamp_scalar(duration_s const& value,
                                                          bool is_valid,
                                                          rmm::cuda_stream_view stream,
                                                          rmm::mr::device_memory_resource* mr);
template timestamp_scalar<timestamp_ns>::timestamp_scalar(duration_ms const& value,
                                                          bool is_valid,
                                                          rmm::cuda_stream_view stream,
                                                          rmm::mr::device_memory_resource* mr);
template timestamp_scalar<timestamp_ns>::timestamp_scalar(duration_us const& value,
                                                          bool is_valid,
                                                          rmm::cuda_stream_view stream,
                                                          rmm::mr::device_memory_resource* mr);
template timestamp_scalar<timestamp_ns>::timestamp_scalar(duration_ns const& value,
                                                          bool is_valid,
                                                          rmm::cuda_stream_view stream,
                                                          rmm::mr::device_memory_resource* mr);
template timestamp_scalar<timestamp_ns>::timestamp_scalar(int64_t const& value,
                                                          bool is_valid,
                                                          rmm::cuda_stream_view stream,
                                                          rmm::mr::device_memory_resource* mr);

list_scalar::list_scalar() : scalar(data_type(type_id::LIST)) {}

list_scalar::list_scalar(cudf::column_view const& elements,
                         bool is_valid,
                         rmm::cuda_stream_view stream,
                         rmm::mr::device_memory_resource* mr)
  : scalar(data_type(type_id::LIST), is_valid, stream, mr), _data(elements, stream, mr)
{
}

column_view list_scalar::view() const { return _data.view(); }

}  // namespace cudf
