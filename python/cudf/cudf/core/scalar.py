# Copyright (c) 2020, NVIDIA CORPORATION.
import numpy as np

from cudf import _lib as libcudf
from cudf.core.column.column import ColumnBase
from cudf.core.index import Index
from cudf.core.series import Series
from cudf.utils.dtypes import (
    get_allowed_combinations_for_operator,
    to_cudf_compatible_scalar,
)


class Scalar(libcudf.scalar.Scalar):
    def __init__(self, value, dtype=None):
        """
        A GPU-backed scalar object with NumPy scalar like properties
        May be used in binary operations against other scalars, cuDF
        Series, DataFrame, and Index objects.

        Examples
        --------
        >>> import cudf
        >>> cudf.Scalar(42, dtype='int64')
        Scalar(42, dtype=int64)
        >>> cudf.Scalar(42, dtype='int32') + cudf.Scalar(42, dtype='float64')
        Scalar(84.0, dtype=float64)
        >>> cudf.Scalar(42, dtype='int64') + np.int8(21)
        Scalar(63, dtype=int64)
        >>> x = cudf.Scalar(42, dtype='datetime64[s]')
        >>> y = cudf.Scalar(21, dtype='timedelta64[ns])
        >>> x - y
        Scalar(1970-01-01T00:00:41.999999979, dtype=datetime64[ns])
        >>> cudf.Series([1,2,3]) + cudf.Scalar(1)
        0    2
        1    3
        2    4
        dtype: int64
        >>> df = cudf.DataFrame({'a':[1,2,3], 'b':[4.5, 5.5, 6.5]})
        >>> slr = cudf.Scalar(10, dtype='uint8')
        >>> df - slr
        a    b
        0 -9 -5.5
        1 -8 -4.5
        2 -7 -3.5

        Parameters
        ----------
        value : Python Scalar, NumPy Scalar, or cuDF Scalar
            The scalar value to be converted to a GPU backed scalar object
        dtype : np.dtype or string specifier
            The data type
        """
        super().__init__(value, dtype=dtype)

    def __index__(self):
        if self.dtype.kind not in {"u", "i"}:
            raise TypeError("Only Integer typed scalars may be used in slices")
        return int(self)

    def __int__(self):
        return int(self.value)

    def __float__(self):
        return float(self.value)

    def __bool__(self):
        return bool(self.value)

    # Scalar Binary Operations
    def __add__(self, other):
        return self._scalar_binop(other, "__add__")

    def __radd__(self, other):
        return self._scalar_binop(other, "__radd__")

    def __sub__(self, other):
        return self._scalar_binop(other, "__sub__")

    def __rsub__(self, other):
        return self._scalar_binop(other, "__rsub__")

    def __mul__(self, other):
        return self._scalar_binop(other, "__mul__")

    def __rmul__(self, other):
        return self._scalar_binop(other, "__rmul__")

    def __truediv__(self, other):
        return self._scalar_binop(other, "__truediv__")

    def __floordiv__(self, other):
        return self._scalar_binop(other, "__floordiv__")

    def __rtruediv__(self, other):
        return self._scalar_binop(other, "__rtruediv__")

    def __mod__(self, other):
        return self._scalar_binop(other, "__mod__")

    def __divmod__(self, other):
        return self._scalar_binop(other, "__divmod__")

    def __and__(self, other):
        return self._scalar_binop(other, "__and__")

    def __xor__(self, other):
        return self._scalar_binop(other, "__or__")

    def __pow__(self, other):
        return self._scalar_binop(other, "__pow__")

    def __gt__(self, other):
        return self._scalar_binop(other, "__gt__")

    def __lt__(self, other):
        return self._scalar_binop(other, "__lt__")

    def __ge__(self, other):
        return self._scalar_binop(other, "__ge__")

    def __le__(self, other):
        return self._scalar_binop(other, "__le__")

    def __eq__(self, other):
        return self._scalar_binop(other, "__eq__")

    def __ne__(self, other):
        return self._scalar_binop(other, "__ne__")

    def __round__(self, n):
        return self._scalar_binop(n, "__round__")

    # Scalar Unary Operations
    def __abs__(self):
        return self._scalar_unaop("__abs__")

    def __ceil__(self):
        return self._scalar_unaop("__ceil__")

    def __floor__(self):
        return self._scalar_unaop("__floor__")

    def __invert__(self):
        return self._scalar_unaop("__invert__")

    def __neg__(self):
        return self._scalar_unaop("__neg__")

    def __repr__(self):
        # str() fixes a numpy bug with NaT
        # https://github.com/numpy/numpy/issues/17552
        return f"Scalar({str(self.value)}, dtype={self.dtype})"

    def _binop_result_dtype_or_error(self, other, op):
        if op in {"__eq__", "__ne__", "__lt__", "__gt__", "__le__", "__ge__"}:
            return np.bool

        out_dtype = get_allowed_combinations_for_operator(
            self.dtype, other.dtype, op
        )

        # datetime handling
        if out_dtype in "Mm":
            if self.dtype.char in "Mm" and other.dtype.char not in "Mm":
                return self.dtype
            if other.dtype.char in "Mm" and self.dtype.char not in "Mm":
                return other.dtype
            else:
                if (
                    op == "__sub__"
                    and self.dtype.char == other.dtype.char == "M"
                ):
                    res, _ = np.datetime_data(max(self.dtype, other.dtype))
                    return np.dtype("m8" + f"[{res}]")
                return np.result_type(self.dtype, other.dtype)

        return np.dtype(out_dtype)

    def _scalar_binop(self, other, op):
        if isinstance(other, (ColumnBase, Series, Index, np.ndarray)):
            # dispatch to column implementation
            return NotImplemented
        other = to_cudf_compatible_scalar(other)
        out_dtype = self._binop_result_dtype_or_error(other, op)
        valid = self.is_valid() and (
            isinstance(other, np.generic) or other.is_valid()
        )
        if not valid:
            return Scalar(None, dtype=out_dtype)
        else:
            result = self._dispatch_scalar_binop(other, op)
            return Scalar(result, dtype=out_dtype)

    def _dispatch_scalar_binop(self, other, op):
        if isinstance(other, Scalar):
            other = other.value
        return getattr(self.value, op)(other)

    def _unaop_result_type_or_error(self, op):
        if op == "__neg__" and self.dtype == "bool":
            raise TypeError(
                "Boolean scalars in cuDF, do not support"
                "negation, use logical not"
            )

        if op in {"__ceil__", "__floor__"}:
            if self.dtype.char in "bBhHf":
                return np.dtype("float32")
            else:
                return np.dtype("float64")
        return self.dtype

    def _scalar_unaop(self, op):
        out_dtype = self._unaop_result_type_or_error(op)
        if not self.is_valid():
            result = None
        else:
            result = self._dispatch_scalar_unaop(op)
            return Scalar(result, dtype=out_dtype)

    def _dispatch_scalar_unaop(self, op):
        if op == "__floor__":
            return np.floor(self.value)
        if op == "__ceil__":
            return np.ceil(self.value)
        return getattr(self.value, op)()


class cudf_NA_type(object):
    def __init__(self):
        pass

    def __repr__(self):
        return "<NA>"

    def __bool__(self):
        raise TypeError("boolean value of cudf.NA is ambiguous")


NA = cudf_NA_type()
