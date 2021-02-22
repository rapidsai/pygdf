# Copyright (c) 2020-2021, NVIDIA CORPORATION.
from __future__ import annotations

from collections import OrderedDict, namedtuple
from typing import TYPE_CHECKING, Tuple

import cudf
from cudf import _lib as libcudf
from cudf.core.join._join_helpers import (
    _coerce_to_list,
    _coerce_to_tuple,
    _Indexer,
    _match_join_keys,
)

if TYPE_CHECKING:
    from cudf.core.frame import Frame


def merge(
    lhs,
    rhs,
    *,
    on,
    left_on,
    right_on,
    left_index,
    right_index,
    how,
    sort,
    lsuffix,
    rsuffix,
    method,
    indicator,
    suffixes,
):
    if how in {"leftsemi", "leftanti"}:
        merge_cls = MergeSemi
    else:
        merge_cls = Merge
    mergeobj = merge_cls(
        lhs,
        rhs,
        on=on,
        left_on=left_on,
        right_on=right_on,
        left_index=left_index,
        right_index=right_index,
        how=how,
        sort=sort,
        lsuffix=lsuffix,
        rsuffix=rsuffix,
        method=method,
        indicator=indicator,
        suffixes=suffixes,
    )
    return mergeobj.perform_merge()


_JoinKeys = namedtuple("JoinKeys", ["left", "right"])


class Merge(object):
    # A namedtuple of indexers representing the left and right keys
    _keys: _JoinKeys

    # The joiner function must have the following signature:
    #
    #     def joiner(lhs, rhs, left_on, right_on, how=how):
    #          ...
    #
    # Where:
    #
    # - `lhs` and `rhs` represent the left and right Frames to join
    # - `left_on` and `right_on` represent the *numerical* indices
    #   of the key columns  of lhs and rhs. This allows specifying
    #   index levels as keys in an unambiguous way.
    # - `how` is a string specifying the kind of join to perform
    #   (useful if the joiner function can perform more than one join).
    _joiner = libcudf.join.join

    def __init__(
        self,
        lhs,
        rhs,
        *,
        on,
        left_on,
        right_on,
        left_index,
        right_index,
        how,
        sort,
        lsuffix,
        rsuffix,
        method,
        indicator,
        suffixes,
    ):
        """
        Manage the merging of two Frames.

        Parameters
        ----------
        lhs : Series or DataFrame
            The left operand of the merge
        rhs : Series or DataFrame
            The right operand of the merge
        on : string or list like
            A set of key columns in the left and right operands
            elements must be common to both frames
        left_on : string or list like
            A set of key columns in the left operand. Must be
            specified with right_on or right_index concurrently
        right_on : string or list like
            A set of key columns in the right operand. Must be
            specified with left_on or left_index concurrently
        left_index : bool
            Boolean flag indicating the left index column or columns
            are to be used as join keys in order.
        right_index : bool
            Boolean flag indicating the right index column or coumns
            are to be used as join keys in order.
        how : string
            The type of join. Possible values are
            'inner', 'outer', 'left', 'leftsemi' and 'leftanti'
        sort : bool
            Boolean flag indicating if the output Frame is to be
            sorted on the output's join keys, in left to right order.
        lsuffix : string
            The suffix to be appended to left hand column names that
            are found to exist in the right frame, but are not specified
            as join keys themselves.
        rsuffix : string
            The suffix to be appended to right hand column names that
            are found to exist in the left frame, but are not specified
            as join keys themselves.
        suffixes : list like
            Left and right suffixes specified together, unpacked into lsuffix
            and rsuffix.
        """
        self._validate_merge_params(
            lhs,
            rhs,
            on=on,
            left_on=left_on,
            right_on=right_on,
            left_index=left_index,
            right_index=right_index,
            how=how,
            lsuffix=lsuffix,
            rsuffix=rsuffix,
            suffixes=suffixes,
        )

        self.lhs = lhs
        self.rhs = rhs
        self.on = on
        self.left_on = left_on
        self.right_on = right_on
        self.left_index = left_index
        self.right_index = right_index
        self.how = how
        self.sort = sort
        self.lsuffix = lsuffix
        self.rsuffix = rsuffix
        self.suffixes = suffixes

        self._out_class = cudf.DataFrame

        if isinstance(self.lhs, cudf.MultiIndex) or isinstance(
            self.rhs, cudf.MultiIndex
        ):
            self._out_class = cudf.MultiIndex
        elif isinstance(self.lhs, cudf.Index):
            self._out_class = self.lhs.__class__

        self._compute_join_keys()

    def perform_merge(self) -> Frame:
        lhs, rhs = self._match_key_dtypes(self.lhs, self.rhs)

        left_key_indices = [
            key.get_numeric_index(lhs) for key in self._keys.left
        ]
        right_key_indices = [
            key.get_numeric_index(rhs) for key in self._keys.right
        ]

        left_rows, right_rows = self._joiner(
            lhs,
            rhs,
            left_on=left_key_indices,
            right_on=right_key_indices,
            how=self.how,
        )
        lhs, rhs = self._restore_categorical_keys(lhs, rhs)

        left_result = lhs._gather(left_rows, nullify=True)
        right_result = rhs._gather(right_rows, nullify=True)

        result = self._merge_results(left_result, right_result)

        if self.sort:
            result = self._sort_result(result)
        return result

    def _compute_join_keys(self):
        # Computes self._keys
        if (
            self.left_index
            or self.right_index
            or self.left_on
            or self.right_on
        ):
            left_keys = []
            right_keys = []
            if self.left_index:
                left_keys.extend(
                    [
                        _Indexer(name=on, index=True)
                        for on in self.lhs.index.names
                    ]
                )
            if self.left_on:
                # TODO: require left_on or left_index to be specified
                left_keys.extend(
                    [
                        _Indexer(name=on, column=True)
                        for on in _coerce_to_tuple(self.left_on)
                    ]
                )
            if self.right_index:
                right_keys.extend(
                    [
                        _Indexer(name=on, index=True)
                        for on in self.rhs.index.names
                    ]
                )
            if self.right_on:
                # TODO: require right_on or right_index to be specified
                right_keys.extend(
                    [
                        _Indexer(name=on, column=True)
                        for on in _coerce_to_tuple(self.right_on)
                    ]
                )
        else:
            # Use `on` if provided. Otherwise,
            # implicitly use identically named columns as the key columns:
            on_names = (
                _coerce_to_tuple(self.on)
                if self.on is not None
                else set(self.lhs._data) & set(self.rhs._data)
            )
            left_keys = [_Indexer(name=on, column=True) for on in on_names]
            right_keys = [_Indexer(name=on, column=True) for on in on_names]

        if len(left_keys) != len(right_keys):
            raise ValueError(
                "Merge operands must have same number of join key columns"
            )

        self._keys = _JoinKeys(left=left_keys, right=right_keys)

    def _merge_results(self, left_result: Frame, right_result: Frame) -> Frame:
        # Merge the Frames `left_result` and `right_result` into a single
        # `Frame`, suffixing column names if necessary.

        # For outer joins, the key columns from left_result and
        # right_result are combined if they have the same name.
        # We will drop those keys from right_result later, so
        # combine them now with keys from left_result.
        if self.how == "outer":
            for lkey, rkey in zip(*self._keys):
                if lkey.name == rkey.name:
                    # fill nulls in lhs from values in the rhs
                    lkey.set(
                        left_result,
                        lkey.get(left_result).fillna(rkey.get(right_result)),
                    )

        # `left_names` and `right_names` are mappings of column names
        # of `lhs` and `rhs` to the corresponding column names in the result
        left_names = OrderedDict(zip(left_result._data, left_result._data))
        right_names = OrderedDict(zip(right_result._data, right_result._data))

        common_names = set(left_names) & set(right_names)

        if self.on:
            key_columns_with_same_name = self.on
        else:
            key_columns_with_same_name = []
            for lkey, rkey in zip(*self._keys):
                if (lkey.index, rkey.index) == (False, False):
                    if lkey.name == rkey.name:
                        key_columns_with_same_name.append(lkey.name)

        # For any columns with the same name:
        # - if they are key columns, keep only the left column
        # - if they are not key columns, use suffixes
        for name in common_names:
            if name not in key_columns_with_same_name:
                left_names[name] = f"{name}{self.lsuffix}"
                right_names[name] = f"{name}{self.rsuffix}"
            else:
                del right_names[name]

        # Assemble the data columns of the result:
        data = cudf.core.column_accessor.ColumnAccessor()

        for lcol in left_names:
            data[left_names[lcol]] = left_result._data[lcol]
        for rcol in right_names:
            data[right_names[rcol]] = right_result._data[rcol]

        # Index of the result:
        if self.left_index and self.right_index:
            if self.how == "right":
                index = right_result._index
            else:
                index = left_result._index
        elif self.left_index:
            # left_index and right_on
            index = right_result._index
        elif self.right_index:
            # right_index and left_on
            index = left_result._index
        else:
            index = None

        # Construct result from data and index:
        result = self._out_class._from_data(data=data, index=index)

        return result

    def _sort_result(self, result: Frame) -> Frame:
        # Pandas sorts on the key columns in the
        # same order as given in 'on'. If the indices are used as
        # keys, the index will be sorted. If one index is specified,
        # the key columns on the other side will be used to sort.
        if self.on:
            if isinstance(result, cudf.Index):
                sort_order = result._get_sorted_inds()
            else:
                sort_order = result._get_sorted_inds(_coerce_to_list(self.on))
            return result._gather(sort_order, keep_index=False)
        by = []
        if self.left_index and self.right_index:
            if result._index is not None:
                by.extend(result._index._data.columns)
        if self.left_on:
            by.extend(
                [result._data[col] for col in _coerce_to_list(self.left_on)]
            )
        if self.right_on:
            by.extend(
                [result._data[col] for col in _coerce_to_list(self.right_on)]
            )
        if by:
            to_sort = cudf.DataFrame._from_columns(by)
            sort_order = to_sort.argsort()
            result = result._gather(sort_order)
        return result

    @staticmethod
    def _validate_merge_params(
        lhs,
        rhs,
        on,
        left_on,
        right_on,
        left_index,
        right_index,
        how,
        lsuffix,
        rsuffix,
        suffixes,
    ):
        """
        Error for various invalid combinations of merge input parameters
        """
        # must actually support the requested merge type
        if how not in {"left", "inner", "outer", "leftanti", "leftsemi"}:
            raise NotImplementedError(f"{how} merge not supported yet")

        # Passing 'on' with 'left_on' or 'right_on' is ambiguous
        if on and (left_on or right_on):
            raise ValueError(
                'Can only pass argument "on" OR "left_on" '
                'and "right_on", not a combination of both.'
            )

        # Can't merge on unnamed Series
        if (isinstance(lhs, cudf.Series) and not lhs.name) or (
            isinstance(rhs, cudf.Series) and not rhs.name
        ):
            raise ValueError("Can not merge on unnamed Series")

        # If nothing specified, must have common cols to use implicitly
        same_named_columns = set(lhs._data) & set(rhs._data)
        if (
            not (left_index or right_index)
            and not (left_on or right_on)
            and len(same_named_columns) == 0
        ):
            raise ValueError("No common columns to perform merge on")

        if suffixes:
            lsuffix, rsuffix = suffixes
        for name in same_named_columns:
            if name == left_on == right_on:
                continue
            elif left_on and right_on:
                if (name in left_on and name in right_on) and (
                    left_on.index(name) == right_on.index(name)
                ):
                    continue
            else:
                if not (lsuffix or rsuffix):
                    raise ValueError(
                        "there are overlapping columns but "
                        "lsuffix and rsuffix are not defined"
                    )

    def _match_key_dtypes(self, lhs: Frame, rhs: Frame) -> Tuple[Frame, Frame]:
        # Match the dtypes of the key columns from lhs and rhs
        out_lhs = lhs.copy(deep=False)
        out_rhs = rhs.copy(deep=False)
        for left_key, right_key in zip(*self._keys):
            lcol, rcol = left_key.get(lhs), right_key.get(rhs)
            dtype = _match_join_keys(lcol, rcol, how=self.how)
            if dtype:
                left_key.set(out_lhs, lcol.astype(dtype))
                right_key.set(out_rhs, rcol.astype(dtype))
        return out_lhs, out_rhs

    def _restore_categorical_keys(
        self, lhs: Frame, rhs: Frame
    ) -> Tuple[Frame, Frame]:
        # For inner joins, any categorical keys in `self.lhs` and `self.rhs`
        # were casted to their category type to produce `lhs` and `rhs`.
        # Here, we cast them back.
        out_lhs = lhs.copy(deep=False)
        out_rhs = rhs.copy(deep=False)
        if self.how == "inner":
            for left_key, right_key in zip(*self._keys):
                if isinstance(
                    left_key.get(self.lhs).dtype, cudf.CategoricalDtype
                ) and isinstance(
                    right_key.get(self.rhs).dtype, cudf.CategoricalDtype
                ):
                    left_key.set(
                        out_lhs, left_key.get(out_lhs).astype("category")
                    )
                    right_key.set(
                        out_rhs, right_key.get(out_rhs).astype("category")
                    )
        return out_lhs, out_rhs


class MergeSemi(Merge):
    _joiner = libcudf.join.semi_join

    def _merge_results(self, lhs: Frame, rhs: Frame) -> Frame:
        return super()._merge_results(lhs, cudf.core.frame.Frame())
