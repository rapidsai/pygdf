# Copyright (c) 2020, NVIDIA CORPORATION.

import pyarrow as pa

import cudf
from cudf.core.column import ColumnBase


class StructColumn(ColumnBase):
    @property
    def base_size(self):
        if not self.base_children:
            return 0
        else:
            return len(self.base_children[0]) - 1

    @classmethod
    def from_arrow(self, data):
        size = len(data)
        dtype = cudf.core.dtypes.StructDtype.from_arrow(data.type)
        mask = data.buffers()[0]
        offset = data.offset
        null_count = data.null_count
        children = tuple(
            cudf.core.column.as_column(data.field(i))
            for i in range(data.type.num_fields)
        )
        return StructColumn(
            data=None,
            size=size,
            dtype=dtype,
            mask=mask,
            offset=offset,
            null_count=null_count,
            children=children,
        )

    def to_arrow(self):
        pa_type = self.dtype.to_arrow()

        if self.nullable:
            nbuf = self.mask.to_host_array().view("int8")
            nbuf = pa.py_buffer(nbuf)
            buffers = (nbuf,)
        else:
            buffers = (None,)

        return pa.StructArray.from_buffers(
            pa_type,
            len(self),
            buffers,
            children=tuple(col.to_arrow() for col in self.children),
        )
