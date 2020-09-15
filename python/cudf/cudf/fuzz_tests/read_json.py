import sys

import pandas as pd

import cudf
from cudf.testing.json import JSONReader
from cudf.testing.main import pythonfuzz
from cudf.tests.utils import assert_eq


@pythonfuzz(data_handle=JSONReader)
def json_reader_test(file_name):
    pdf = pd.read_json(file_name)
    gdf = cudf.read_json(file_name)

    assert_eq(gdf, pdf)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage is python file_name.py function_name")

    function_name_to_run = sys.argv[1]
    try:
        globals()[function_name_to_run]()
    except KeyError:
        print(
            f"Provided function name({function_name_to_run}) does not exist."
        )
