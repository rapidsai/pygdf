# Copyright (c) 2020-2021, NVIDIA CORPORATION.

import cudf

import pyarrow as pa

from cython.operator cimport dereference

from cudf._lib.column cimport Column
from cudf._lib.table cimport Table
from cudf._lib.cpp.column.column cimport column, column_view
from cudf._lib.cpp.table.table cimport table_view

from libc.stdint cimport uint8_t
from libcpp.memory cimport unique_ptr
from libcpp.string cimport string
from libcpp.utility cimport move
from libcpp.vector cimport vector

try:
    import ujson as json
except ImportError:
    import json

from cudf.utils.dtypes import (
    np_to_pa_dtype,
    is_categorical_dtype,
    is_list_dtype,
    is_struct_dtype,
    is_decimal_dtype,
)


cdef vector[column_view] make_column_views(object columns):
    cdef vector[column_view] views
    views.reserve(len(columns))
    for col in columns:
        views.push_back((<Column> col).view())
    return views


cdef vector[table_view] make_table_views(object tables):
    cdef vector[table_view] views
    views.reserve(len(tables))
    for tbl in tables:
        views.push_back((<Table> tbl).view())
    return views


cdef vector[table_view] make_table_data_views(object tables):
    cdef vector[table_view] views
    views.reserve(len(tables))
    for tbl in tables:
        views.push_back((<Table> tbl).data_view())
    return views


cdef vector[string] get_column_names(Table table, object index):
    cdef vector[string] column_names
    if index is not False:
        if isinstance(table._index, cudf.core.multiindex.MultiIndex):
            for idx_name in table._index.names:
                column_names.push_back(str.encode(idx_name))
        else:
            if table._index.name is not None:
                column_names.push_back(str.encode(table._index.name))

    for col_name in table._column_names:
        column_names.push_back(str.encode(col_name))

    return column_names


cpdef generate_pandas_metadata(Table table, index):
    col_names = []
    types = []
    index_levels = []
    index_descriptors = []

    # Columns
    for name, col in table._data.items():
        col_names.append(name)
        if is_categorical_dtype(col):
            raise ValueError(
                "'category' column dtypes are currently not "
                + "supported by the gpu accelerated parquet writer"
            )
        elif (
            is_list_dtype(col)
            or is_struct_dtype(col)
            or is_decimal_dtype(col)
        ):
            types.append(col.dtype.to_arrow())
        else:
            types.append(np_to_pa_dtype(col.dtype))

    # Indexes
    if index is not False:
        for level, name in enumerate(table._index.names):
            if isinstance(table._index, cudf.core.multiindex.MultiIndex):
                idx = table.index.get_level_values(level)
            else:
                idx = table.index

            if isinstance(idx, cudf.core.index.RangeIndex):
                if index is None:
                    descr = {
                        "kind": "range",
                        "name": table.index.name,
                        "start": table.index.start,
                        "stop": table.index.stop,
                        "step": table.index.step,
                    }
                else:
                    # When `index=True`, RangeIndex needs to be materialized.
                    materialized_idx = cudf.Index(idx._values, name=idx.name)
                    descr = \
                        _index_level_name(
                            index_name=materialized_idx.name,
                            level=level,
                            column_names=col_names
                        )
                    index_levels.append(materialized_idx)
            else:
                descr = \
                    _index_level_name(
                        index_name=idx.name,
                        level=level,
                        column_names=col_names
                    )
                if is_categorical_dtype(idx):
                    raise ValueError(
                        "'category' column dtypes are currently not "
                        + "supported by the gpu accelerated parquet writer"
                    )
                elif is_list_dtype(idx):
                    types.append(col.dtype.to_arrow())
                else:
                    types.append(np_to_pa_dtype(idx.dtype))
                index_levels.append(idx)
            col_names.append(name)
            index_descriptors.append(descr)

    metadata = pa.pandas_compat.construct_metadata(
        columns_to_convert=[
            col
            for col in table._columns
        ],
        df=table,
        column_names=col_names,
        index_levels=index_levels,
        index_descriptors=index_descriptors,
        preserve_index=index,
        types=types,
    )

    md_dict = json.loads(metadata[b"pandas"])

    # correct metadata for list and struct types
    for col_meta in md_dict["columns"]:
        if col_meta["numpy_type"] in ("list", "struct"):
            col_meta["numpy_type"] = "object"

    return json.dumps(md_dict)


def _index_level_name(index_name, level, column_names):
    """
    Return the name of an index level or a default name
    if `index_name` is None or is already a column name.

    Parameters
    ----------
    index_name : name of an Index object
    level : level of the Index object

    Returns
    -------
    name : str
    """
    if index_name is not None and index_name not in column_names:
        return index_name
    else:
        return f"__index_level_{level}__"


cdef columns_from_unique_ptr(unique_ptr[table] c_tbl):
    """Get a list of columns from a libcudf table.

    Since cuDF Python has an independent representation of a table as a
    collection of columns, this function simply returns a list of columns
    suitable for conversion into data to be passed to cuDF constructors.
    This method returns the columns of the table in the order they are
    stored in libcudf, but calling code is responsible for partitioning and
    labeling them as needed.

    Parameters
    ----------
    c_tbl : unique_ptr[cudf::table]
    index_names : iterable
    column_names : iterable

    Returns
    -------
    List[Column]
        A list of the columns in the output table.
    """
    cdef vector[unique_ptr[column]] columns = move(c_tbl.get().release())
    cdef vector[unique_ptr[column]].iterator it = columns.begin()

    # First construct the index, if any
    cdef int i

    return [Column.from_unique_ptr(move(dereference(it+i)))
            for i in range(columns.size())]


def table_inputs_from_list(columns, column_names, index_names=None):
    """Convert a list of columns into a dict with an index.

    This method is intended to provide the bridge between the columns returned
    from calls to libcudf APIs and the cuDF Python Table objects, which require
    named columns and a separate index.

    Parameters
    ----------
    c_tbl : unique_ptr[cudf::table]
    index_names : iterable
    column_names : iterable

    Returns
    -------
    List[Column]
        A list of the columns in the output table.
    """
    index = (
        cudf.Index._from_data(
            {
                name: columns[i]
                for i, name in enumerate(index_names)
            }
        )
        if index_names is not None
        else None
    )
    n_index_columns = len(index_names) if index_names is not None else 0
    data = {
        name: columns[i + n_index_columns]
        for i, name in enumerate(column_names)
    }
    return data, index
