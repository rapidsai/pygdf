import pickle

import cudf
import cudf.core.groupby.groupby

# all (de-)serializtion are attached to cudf Objects:
# Series/DataFrame/Index/Column/Buffer/etc
serializable_classes = (
    cudf.CategoricalDtype,
    cudf.DataFrame,
    cudf.Index,
    cudf.MultiIndex,
    cudf.Series,
    cudf.core.groupby.groupby.GroupBy,
    cudf.core.groupby.groupby._Grouping,
    cudf.core.column.column.ColumnBase,
    cudf.core.buffer.Buffer,
)

try:
    from distributed.protocol import dask_deserialize, dask_serialize
    from distributed.protocol.cuda import cuda_deserialize, cuda_serialize
    from distributed.utils import log_errors

    @cuda_serialize.register(serializable_classes)
    def cuda_serialize_cudf_object(x):
        with log_errors():
            header, frames = x.serialize()
            header["lengths"] = [f.nbytes for f in frames]
            return header, frames

    # all (de-)serializtion are attached to cudf Objects:
    # Series/DataFrame/Index/Column/Buffer/etc
    @dask_serialize.register(serializable_classes)
    def dask_serialize_cudf_object(x):
        header, frames = cuda_serialize_cudf_object(x)
        with log_errors():
            for i, f in enumerate(frames):
                if hasattr(f, "__cuda_array_interface__"):
                    frames[i] = cudf.core.buffer.Buffer(f).to_host_array().data
            return header, frames

    @cuda_deserialize.register(serializable_classes)
    @dask_deserialize.register(serializable_classes)
    def deserialize_cudf_object(header, frames):
        with log_errors():
            if header["serializer"] == "dask":
                frames = [memoryview(f) for f in frames]
            cudf_typ = pickle.loads(header["type-serialized"])
            cudf_obj = cudf_typ.deserialize(header, frames)
            return cudf_obj


except ImportError:
    # distributed is probably not installed on the system
    pass
