# Copyright (c) 2021, NVIDIA CORPORATION.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import cudf
from cudf.tests.utils import assert_eq

from libcpp.utility cimport move

from cudf._lib.copying import pack, unpack


def test_equality():
    expect = cudf.DataFrame({'a': [1, 2, 3], 'b': [4, 5, 6]})
    result = cudf.DataFrame._from_table(
        unpack(move(pack(expect)), expect._column_names)
    )

    assert_eq(result, expect)
