# Copyright (c) 2021, NVIDIA CORPORATION.
"""Define common type operations."""

import datetime as dt
from collections.abc import Sequence
from numbers import Number

import cupy as cp
import numpy as np
import pandas as pd
from pandas.api import types as pd_types
from pandas.core.dtypes.dtypes import (
    CategoricalDtype as pd_CategoricalDtype,
    CategoricalDtypeType as pd_CategoricalDtypeType,
)

import cudf
from cudf._lib.scalar import DeviceScalar


def is_categorical_dtype(obj):
    """Infer whether a given pandas, numpy, or cuDF Column, Series, or dtype
    is a pandas CategoricalDtype.
    """
    if obj is None:
        return False
    if isinstance(obj, cudf.CategoricalDtype):
        return True
    if obj is cudf.CategoricalDtype:
        return True
    if isinstance(obj, np.dtype):
        return False
    if isinstance(obj, pd_CategoricalDtype):
        return True
    if obj is pd_CategoricalDtype:
        return True
    if obj is pd_CategoricalDtypeType:
        return True
    if isinstance(obj, str) and obj == "category":
        return True
    if isinstance(
        obj,
        (
            pd_CategoricalDtype,
            cudf.core.index.CategoricalIndex,
            cudf.core.column.CategoricalColumn,
            pd.Categorical,
            pd.CategoricalIndex,
        ),
    ):
        return True
    if isinstance(obj, np.ndarray):
        return False
    if isinstance(
        obj,
        (
            cudf.Index,
            cudf.Series,
            cudf.core.column.ColumnBase,
            pd.Index,
            pd.Series,
        ),
    ):
        return is_categorical_dtype(obj.dtype)
    if hasattr(obj, "type"):
        if obj.type is pd_CategoricalDtypeType:
            return True
    # TODO: A lot of the above checks are probably redundant and should be
    # farmed out to this function here instead.
    return pd_types.is_categorical_dtype(obj)


def is_numeric_dtype(obj):
    # TODO: we should handle objects with a `.dtype` attribute,
    # e.g., arrays, here.
    try:
        dtype = np.dtype(obj)
    except TypeError:
        return False
    return dtype.kind in "biuf"


"""
TODO: There a number of things we need to check:
    1. Should any of the following methods be falling back to pd.api.types
       functions: is_integer_dtype, is_integer, is_string_dtype,
       is_datetime_dtype, is_timedelta_dtype, is_interval_dtype, is_scalar.
    2. The following methods have implementations, but could possibly just
       alias pd.api.types functions directly: is_list_like
    3. The following methods in pd.api.types probably need to be overridden:
       is_interval, is_number, infer_dtype, pandas_dtype (maybe as cudf_dtype?)
    2. For datetime/timedelta, do we need to be more general than pandas with
       respect to the different time resolutions?
"""


def is_integer_dtype(obj):
    try:
        dtype = np.dtype(obj)
    except TypeError:
        return pd.api.types.is_integer_dtype(obj)
    return dtype.kind in "iu"


def is_integer(obj):
    if isinstance(obj, cudf.Scalar):
        return is_integer_dtype(obj.dtype)
    return pd.api.types.is_integer(obj)


def is_string_dtype(obj):
    return (
        pd.api.types.is_string_dtype(obj)
        # Reject all cudf extension types.
        and not is_categorical_dtype(obj)
        and not is_decimal_dtype(obj)
        and not is_list_dtype(obj)
        and not is_struct_dtype(obj)
        and not is_interval_dtype(obj)
    )


def is_datetime_dtype(obj):
    if obj is None:
        return False
    if not hasattr(obj, "str"):
        return False
    return "M8" in obj.str


def is_timedelta_dtype(obj):
    if obj is None:
        return False
    if not hasattr(obj, "str"):
        return False
    return "m8" in obj.str


def is_list_dtype(obj):
    return (
        type(obj) is cudf.core.dtypes.ListDtype
        or obj is cudf.core.dtypes.ListDtype
        or type(obj) is cudf.core.column.ListColumn
        or obj is cudf.core.column.ListColumn
        or (isinstance(obj, str) and obj == cudf.core.dtypes.ListDtype.name)
        or (hasattr(obj, "dtype") and is_list_dtype(obj.dtype))
    )


def is_struct_dtype(obj):
    return (
        isinstance(obj, cudf.core.dtypes.StructDtype)
        or obj is cudf.core.dtypes.StructDtype
        or (isinstance(obj, str) and obj == cudf.core.dtypes.StructDtype.name)
        or (hasattr(obj, "dtype") and is_struct_dtype(obj.dtype))
    )


def is_interval_dtype(obj):
    # TODO: Should there be any branch in this function that calls
    # pd.api.types.is_interval_dtype?
    return (
        isinstance(obj, cudf.core.dtypes.IntervalDtype)
        or isinstance(obj, pd.core.dtypes.dtypes.IntervalDtype)
        or obj is cudf.core.dtypes.IntervalDtype
        or (
            isinstance(obj, str) and obj == cudf.core.dtypes.IntervalDtype.name
        )
        or (hasattr(obj, "dtype") and is_interval_dtype(obj.dtype))
    )


def is_decimal_dtype(obj):
    return (
        type(obj) is cudf.core.dtypes.Decimal64Dtype
        or obj is cudf.core.dtypes.Decimal64Dtype
        or (
            isinstance(obj, str)
            and obj == cudf.core.dtypes.Decimal64Dtype.name
        )
        or (hasattr(obj, "dtype") and is_decimal_dtype(obj.dtype))
    )


def is_scalar(val):
    return (
        val is None
        or isinstance(val, DeviceScalar)
        or isinstance(val, cudf.Scalar)
        or isinstance(val, str)
        or isinstance(val, Number)
        or np.isscalar(val)
        or (isinstance(val, (np.ndarray, cp.ndarray)) and val.ndim == 0)
        or isinstance(val, pd.Timestamp)
        or (isinstance(val, pd.Categorical) and len(val) == 1)
        or (isinstance(val, pd.Timedelta))
        or (isinstance(val, pd.Timestamp))
        or (isinstance(val, dt.datetime))
        or (isinstance(val, dt.timedelta))
    )


def is_list_like(obj):
    """
    This function checks if the given `obj`
    is a list-like (list, tuple, Series...)
    type or not.

    Parameters
    ----------
    obj : object of any type which needs to be validated.

    Returns
    -------
    Boolean: True or False depending on whether the
    input `obj` is like-like or not.
    """

    return isinstance(obj, (Sequence, np.ndarray)) and not isinstance(
        obj, (str, bytes)
    )


# These methods are aliased directly into this namespace, but can be modified
# later if we determine that there is a need.

union_categoricals = pd_types.union_categoricals
infer_dtype = pd_types.infer_dtype
pandas_dtype = pd_types.pandas_dtype
is_bool_dtype = pd_types.is_bool_dtype
is_complex_dtype = pd_types.is_complex_dtype
# TODO: Evaluate which of the datetime types need special handling for cudf.
is_datetime64_any_dtype = pd_types.is_datetime64_any_dtype
is_datetime64_dtype = pd_types.is_datetime64_dtype
is_datetime64_ns_dtype = pd_types.is_datetime64_ns_dtype
is_datetime64tz_dtype = pd_types.is_datetime64tz_dtype
is_extension_type = pd_types.is_extension_type
is_extension_array_dtype = pd_types.is_extension_array_dtype
is_float_dtype = pd_types.is_float_dtype
is_int64_dtype = pd_types.is_int64_dtype
is_object_dtype = pd_types.is_object_dtype
is_period_dtype = pd_types.is_period_dtype
is_signed_integer_dtype = pd_types.is_signed_integer_dtype
is_timedelta64_dtype = pd_types.is_timedelta64_dtype
is_timedelta64_ns_dtype = pd_types.is_timedelta64_ns_dtype
is_unsigned_integer_dtype = pd_types.is_unsigned_integer_dtype
is_sparse = pd_types.is_sparse
is_dict_like = pd_types.is_dict_like
is_file_like = pd_types.is_file_like
is_named_tuple = pd_types.is_named_tuple
is_iterator = pd_types.is_iterator
is_bool = pd_types.is_bool
is_categorical = pd_types.is_categorical
is_complex = pd_types.is_complex
is_float = pd_types.is_float
is_hashable = pd_types.is_hashable
is_interval = pd_types.is_interval
is_number = pd_types.is_number
is_re = pd_types.is_re
is_re_compilable = pd_types.is_re_compilable
is_dtype_equal = pd_types.is_dtype_equal
