# Copyright (c) 2020, NVIDIA CORPORATION.

from libcpp.vector cimport vector
from libcpp.string cimport string

cimport cudf._lib.cpp.io.types as cudf_io_types


cdef extern from "cudf/io/orc_metadata.hpp" \
        namespace "cudf::io" nogil:

    cdef cppclass raw_orc_statistics:
        raw_orc_statistics() except +
        vector[string] column_names
        vector[string] column_stats
        vector[vector[string]] stripe_stats

    cdef raw_orc_statistics read_raw_orc_statistics(
        cudf_io_types.source_info src_info
    ) except +
