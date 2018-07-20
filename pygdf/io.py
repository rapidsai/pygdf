from ._gdf import ffi, libgdf, np_to_gdf_dtype
from .column import Column
from .numerical import NumericalColumn
from .dataframe import DataFrame

def _wrap_string(text):
    return ffi.new("char[]", text.encode())


def read_csv(path, names, dtypes, delimiter=',', ):
    ncols = len(names)
    out = libgdf.read_csv(
        _wrap_string(path),
        delimiter.encode(),
        ncols,
        [_wrap_string(k) for k in names],
        list(map(lambda x: _wrap_string(str(x)), dtypes)),
    )
    if out == ffi.NULL:
        raise ValueError("Failed to parse CSV")

    # Extract parsed columns
    outcols = []
    for i in range(ncols):
        newcol = Column.from_cffi_view(out[i])
        # XXX: Bit mask is wrong? dropping it for now
        newcol = newcol.replace(mask=None)
        outcols.append(newcol.view(NumericalColumn, dtype=newcol.dtype))

    # Build dataframe
    df = DataFrame()
    for k, v in zip(names, outcols):
        df[k] = v

    return df
