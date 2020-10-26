import numpy as np
import pandas as pd

import cudf
from cudf.core.column import as_column
from cudf.utils.dtypes import (
    can_convert_to_column,
    is_numerical_dtype,
    is_datetime_dtype,
    is_timedelta_dtype,
    is_categorical_dtype,
    is_string_dtype,
    is_list_dtype,
    is_struct_dtype,
)

import cudf._lib as libcudf


def to_numeric(arg, errors="raise", downcast=None):
    """
    Convert argument into numerical types.

    Parameters
    ----------
    arg : column-convertible
        The object to convert to numeric types
    errors : {'raise', 'ignore', 'coerce'}, defaults 'raise'
        Policy to handle errors during parsing.
        - 'raise' will notify user all errors encountered.
        - 'ignore' will skip error and returns input.
        - 'coerce' will leave invalid values as nulls.
    downcast : {'integer', 'signed', 'unsigned', 'float'}, defaults None
        If set, will try to down-convert the datatype of the
        parsed results to smallest possible type. For each `downcast`
        type, this method will determine the smallest possible
        dtype from the following sets:
        - {'integer', 'signed'}: all integer types larger or equal to `np.int8`
        - {'unsigned'}: all unsigned types larger or equal to `np.uint8`
        - {'float'}: all floating types larger or equal to `np.float32`

    Returns
    -------
    Depending on the input, if series is passed in, series is returned,
    otherwise ndarray

    Notes
    -------
    An important difference from pandas is that this function does not accept
    mixed numeric, non-numeric type sequences. For example `[1, 'a']`.
    A `TypeError` will be raised when such input is received, regardless of
    `errors` parameter.

    Examples
    --------
    """

    if errors not in {"raise", "ignore", "coerce"}:
        raise ValueError("invalid error value specified")

    if downcast not in {None, "integer", "signed", "unsigned", "float"}:
        raise ValueError("invalid downcasting method provided")

    if not can_convert_to_column(arg) or (
        hasattr(arg, "ndim") and arg.ndim > 1
    ):
        raise ValueError("arg must be column convertible")

    col = as_column(arg)
    dtype = col.dtype

    if is_datetime_dtype(dtype) or is_timedelta_dtype(dtype):
        col = col.as_numerical_column(np.dtype("int64"))
    elif is_categorical_dtype(dtype):
        cat_dtype = col.dtype.type
        if is_numerical_dtype(cat_dtype):
            col = col.as_numerical_column(cat_dtype)
        else:
            try:
                col = _convert_str_col(col._get_decategorized_column(), errors)
            except ValueError as e:
                if errors == "ignore":
                    return arg
                else:
                    raise e
    elif is_string_dtype(dtype):
        try:
            col = _convert_str_col(col, errors)
        except ValueError as e:
            if errors == "ignore":
                return arg
            else:
                raise e
    elif is_list_dtype(dtype) or is_struct_dtype(dtype):
        raise ValueError("Input does not support nested datatypes")
    elif is_numerical_dtype(dtype):
        pass
    else:
        raise ValueError("Unrecognized datatype")

    if downcast:
        downcast_type_map = {
            "integer": list(np.typecodes["Integer"]),
            "signed": list(np.typecodes["Integer"]),
            "unsigned": list(np.typecodes["UnsignedInteger"]),
        }
        float_types = list(np.typecodes["Float"])
        idx = float_types.index(np.dtype(np.float32).char)
        downcast_type_map["float"] = float_types[idx:]

        type_set = downcast_type_map[downcast]
        for t in type_set:
            downcast_dtype = np.dtype(t)
            if (
                downcast_dtype.itemsize <= col.dtype.itemsize
                and col.can_cast_safely(downcast_dtype)
            ):
                col = libcudf.unary.cast(col, downcast_dtype)
                break

    if isinstance(arg, (cudf.Series, pd.Series)):
        return cudf.Series(col)
    else:
        return col.to_array(fillna="pandas")


def _convert_str_col(col, errors):
    if not is_string_dtype(col):
        raise TypeError("col must be string dtype.")

    is_integer = col.str().isinteger()
    if is_integer.all():
        return col.as_numerical_column(dtype=np.dtype("i8"))

    # Account for `infinite` strings
    col = col.str().lower()
    col = col.str().replace("\\+?(inf|infinity)$", "Inf", regex=True)
    col = col.str().replace("-(inf|infinity)$", "-Inf", regex=True)

    is_float = col.str().isfloat()
    if is_float.all():
        return col.as_numerical_column(dtype=np.dtype("d"))
    if is_integer.sum() + is_float.sum() == len(col):
        return col.as_numerical_column(dtype=np.dtype("d"))
    else:
        if errors == "coerce":
            col = libcudf.string_casting.stod(col)
            non_numerics = is_integer.binary_operator(
                "or", is_float
            ).unary_operator("not")
            col[non_numerics] = None
            return col
        else:
            raise ValueError("Unable to convert some strings to numerics.")
