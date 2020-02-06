import functools
import operator
import pickle

import numpy as np

import rmm
from rmm import DeviceBuffer, _DevicePointer


class Buffer:
    def __init__(self, data=None, size=None, owner=None):
        """
        A Buffer represents a device memory allocation.

        Parameters
        ----------
        data : Buffer, rmm._DevicePointer, array_like, int
            An array-like object or integer representing a
            device or host pointer to pre-allocated memory.
        size : int, optional
            Size of memory allocation. Required if a pointer
            is passed for `data`.
        owner : object, optional
            Python object to which the lifetime of the memory
            allocation is tied. If provided, a reference to this
            object is kept in this Buffer.
        """
        if isinstance(data, Buffer):
            self.ptr = data.ptr
            self.size = data.size
            self._owner = owner or data
        elif isinstance(data, _DevicePointer):
            self.ptr = data.ptr
            self.size = size
            self._owner = data
        elif hasattr(data, "__array_interface__") or hasattr(
            data, "__cuda_array_interface__"
        ):

            self._init_from_array_like(data)
        elif isinstance(data, memoryview):
            self._init_from_array_like(np.asarray(data))
        elif isinstance(data, int):
            if not isinstance(size, int):
                raise TypeError("size must be integer")
            self.ptr = data
            self.size = size
            self._owner = owner
        elif data is None:
            self.ptr = 0
            self.size = 0
            self._owner = None
        else:
            try:
                data = memoryview(data)
            except TypeError:
                raise TypeError("data must be Buffer, array-like or integer")
            self._init_from_array_like(np.asarray(data))

    def __reduce__(self):
        return self.__class__, (self.to_host_array(),)

    def to_host_array(self):
        return rmm.device_array_from_ptr(
            self.ptr, nelem=self.size, dtype="int8"
        ).copy_to_host()

    def _init_from_array_like(self, data):
        if hasattr(data, "__cuda_array_interface__"):
            ptr, size = _buffer_data_from_array_interface(
                data.__cuda_array_interface__
            )
            self.ptr = ptr
            self.size = size
            self._owner = data
        elif hasattr(data, "__array_interface__"):
            ptr, size = _buffer_data_from_array_interface(
                data.__array_interface__
            )
            dbuf = DeviceBuffer(ptr=ptr, size=size)
            self._init_from_array_like(dbuf)
        else:
            raise TypeError(
                f"Cannot construct Buffer from {data.__class__.__name__}"
            )

    @classmethod
    def empty(cls, size):
        dbuf = DeviceBuffer(size=size)
        return Buffer(dbuf)

    def serialize(self):
        from distributed.protocol.cuda import cuda_dumps

        # Rely on existing serializers with fallback to Numba array
        try:
            header, frames = cuda_dumps(self._owner)
        except NotImplementedError:
            header, frames = cuda_dumps(
                rmm.device_array_from_ptr(
                    self.ptr, nelem=self.size, dtype="int8"
                )
            )

        # Patch header to load data with `Buffer`
        header["original-type-serialized"] = header["type-serialized"]
        header["type-serialized"] = pickle.dumps(type(self))
        header["type"] = pickle.dumps(type(self))

        return header, frames

    @classmethod
    def deserialize(cls, header, frames):
        from distributed.protocol.cuda import cuda_loads

        # Revert patch to load data with owner's type
        header = dict(header)
        header["type-serialized"] = header.pop("original-type-serialized")
        del header["type"]

        return cls(data=cuda_loads(header, frames))


def _buffer_data_from_array_interface(array_interface):
    ptr = array_interface["data"][0]
    if ptr is None:
        ptr = 0
    itemsize = np.dtype(array_interface["typestr"]).itemsize
    size = functools.reduce(operator.mul, array_interface["shape"])
    return ptr, size * itemsize
