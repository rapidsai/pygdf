# Copyright (c) 2018, NVIDIA CORPORATION.

from itertools import product

import pytest
import numpy as np
import pandas as pd

from cudf.tests import utils
from cudf import Series
from math import floor


@pytest.mark.parametrize('nelem,masked',
                         list(product([2, 10, 100, 1000],
                                      [True, False])))
def test_applymap_round(nelem, masked):
    # Generate data
    np.random.seed(0)
    data = np.random.random(nelem) * 100

    if masked:
        # Make mask
        bitmask = utils.random_bitmask(nelem)
        boolmask = np.asarray(utils.expand_bits_to_bytes(bitmask),
                              dtype=np.bool)[:nelem]
        data[~boolmask] = np.nan

    sr = Series(data)

    if masked:
        # Mask the Series
        sr = sr.set_mask(bitmask)

    # Call applymap
    out = sr.applymap(lambda x: (floor(x) + 1 if x - floor(x) >= 0.5
                                 else floor(x)))

    if masked:
        # Fill masked values
        out = out.fillna(np.nan)

    # Check
    expect = np.round(data)
    got = out.to_array()
    np.testing.assert_array_almost_equal(expect, got)


def test_applymap_change_out_dtype():
    # Test for changing the out_dtype using applymap

    data = list(range(10))

    sr = Series(data)

    out = sr.applymap(lambda x: float(x), out_dtype=float)

    # Check
    expect = np.array(data, dtype=float)
    got = out.to_array()
    np.testing.assert_array_equal(expect, got)


def test_datetime_applymap():
    data = np.arange(10).astype('datetime64[ms]')
    cudf_series = Series(data)
    pd_series = pd.Series(data)

    def to_timestamp(date2):
        return (date2 + np.timedelta64(1,'D'))

    got = cudf_series.applymap(np.dtype('timedelta64[D]').type(1))
    expect = pd_series.apply(to_timestamp)
    assert got == expect


