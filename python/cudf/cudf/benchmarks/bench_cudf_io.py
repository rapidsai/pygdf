# Copyright (c) 2020, NVIDIA CORPORATION.

import pytest
import cudf
import glob
import io
import os

from get_datasets import create_dataset

from conftest import option

datatype = ['float32', 'float64',
            'int32', 'int64',
            'str', 'datetime64[s]']

null_frequency = [0.1, 0.4, 0.8]


def get_dataset_dir():
    print(" option.dataset_dir : ", option.dataset_dir)
    if option.dataset_dir == "NONE":
        return "cudf/benchmarks/cuio_data/datasets/"
    print(" option.dataset_dir : ", option.dataset_dir)

    return option.dataset_dir


@pytest.mark.parametrize("skiprows", [None, 100000, 200000])
@pytest.mark.parametrize("file_path", glob.glob(get_dataset_dir() + "avro_*"))
def bench_avro(benchmark, file_path, use_buffer, skiprows):
    if use_buffer == "True":
        with open(file_path, "rb") as f:
            file_path = io.BytesIO(f.read())
    benchmark(cudf.read_avro, file_path, skiprows=skiprows)


def get_dtypes(file_path):
    if "_unsigned_int_" in file_path:
        return ["uint8", "uint16", "uint32", "uint64"] * 16
    elif "_int_" in file_path:
        return ["int8", "int16", "int32", "int64"] * 16
    elif "_float_" in file_path:
        return ["float32", "float64"] * 32
    elif "_str_" in file_path:
        return ["str"] * 64
    elif "_datetime64_" in file_path:
        return [
            "timestamp[s]",
            "timestamp[ms]",
            "timestamp[us]",
            "timestamp[ns]",
        ] * 16
    elif "_timedelta64_" in file_path:
        return [
            "timedelta64[s]",
            "timedelta64[ms]",
            "timedelta64[us]",
            "timedelta64[ns]",
        ] * 16
    elif "_bool_" in file_path:
        return ["bool"] * 64
    else:
        raise TypeError("Unsupported dtype file")


@pytest.mark.parametrize("dtype", ["infer", "provide"])
@pytest.mark.parametrize("file_path", glob.glob(get_dataset_dir() + "json_*"))
def bench_json(benchmark, file_path, use_buffer, dtype, run_bench):
    if "bz2" in file_path:
        compression = "bz2"
    elif "gzip" in file_path:
        compression = "gzip"
    elif "infer" in file_path:
        compression = "infer"
    else:
        raise TypeError("Unsupported compression type")

    if dtype == "infer":
        dtype = True
    else:
        dtype = get_dtypes(file_path)

    if use_buffer == "True":
        with open(file_path, "rb") as f:
            file_path = io.BytesIO(f.read())

    benchmark(
        cudf.read_json,
        file_path,
        engine="cudf",
        compression=compression,
        lines=True,
        orient="records",
        dtype=dtype,
    )


@pytest.mark.parametrize("dtype", datatype)
@pytest.mark.parametrize("null_frequency", null_frequency)
def bench_to_csv(benchmark, dtype, null_frequency, run_bench):
    if not run_bench:
        pytest.skip("Pytest variable run_bench not passed as True")
    table, file_path = create_dataset(dtype, file_type="csv",
                                      only_file=False,
                                      null_frequency=null_frequency)

    cudf_df = cudf.DataFrame.from_arrow(table)
    benchmark(cudf_df.to_csv, file_path)


@pytest.mark.parametrize("dtype", datatype)
def bench_from_csv(benchmark, use_buffer, dtype, run_bench):
    if not run_bench:
        pytest.skip("Pytest variable run_bench not passed as True")
    file_path = create_dataset(dtype, file_type="csv",
                               only_file=True,
                               null_frequency=None)

    if use_buffer == "True":
        with open(file_path, "rb") as f:
            file = io.BytesIO(f.read())
    else:
        file = file_path
    benchmark(cudf.read_csv, file)
    os.remove(file_path)


@pytest.mark.parametrize("dtype", datatype)
@pytest.mark.parametrize("null_frequency", null_frequency)
def bench_to_orc(benchmark, dtype, null_frequency, run_bench):
    if not run_bench:
        pytest.skip("Pytest variable run_bench not passed as True")
    table, file_path = create_dataset(dtype, file_type="orc",
                                      only_file=False,
                                      null_frequency=null_frequency)
    
    cudf_df = cudf.DataFrame.from_arrow(table)
    benchmark(cudf_df.to_orc, file_path)


@pytest.mark.parametrize("dtype", datatype)
def bench_read_orc(benchmark, use_buffer, bench_pandas,
                   run_bench, dtype):
    if not run_bench:
        pytest.skip("Pytest variable run_bench not passed as True")
    file_path = create_dataset(dtype, file_type="orc",
                               only_file=True,
                               null_frequency=None)

    if use_buffer == "True":
        with open(file_path, "rb") as f:
            file = io.BytesIO(f.read())
    else:
        file = file_path
    benchmark(cudf.read_orc, file)
    if not bench_pandas:
        os.remove(file_path)


@pytest.mark.parametrize("dtype", datatype)
@pytest.mark.parametrize("null_frequency", null_frequency)
def bench_to_parquet(benchmark, dtype, null_frequency, run_bench):
    if not run_bench:
        pytest.skip("Pytest variable run_bench not passed as True")
    table, file_path = create_dataset(dtype, file_type="parquet",
                                      only_file=False,
                                      null_frequency=null_frequency)
    
    cudf_df = cudf.DataFrame.from_arrow(table)
    benchmark(cudf_df.to_parquet, file_path)


@pytest.mark.parametrize("dtype", datatype)
def bench_read_parquet(benchmark, use_buffer, dtype, run_bench):
    if not run_bench:
        pytest.skip("Pytest variable run_bench not passed as True")
    file_path = create_dataset(dtype, file_type="parquet",
                               only_file=True,
                               null_frequency=None)

    if use_buffer == "True":
        with open(file_path, "rb") as f:
            file = io.BytesIO(f.read())
    else:
        file = file_path
    benchmark(cudf.read_parquet, file)
    os.remove(file_path)
