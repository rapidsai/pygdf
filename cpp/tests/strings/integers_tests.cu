/*
 * Copyright (c) 2019-2021, NVIDIA CORPORATION.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include <cudf/strings/convert/convert_integers.hpp>
#include <cudf/strings/strings_column_view.hpp>

#include <tests/strings/utilities.h>
#include <cudf_test/base_fixture.hpp>
#include <cudf_test/column_utilities.hpp>
#include <cudf_test/column_wrapper.hpp>
#include <cudf_test/type_lists.hpp>

#include <string>
#include <vector>

using FCW_B   = cudf::test::fixed_width_column_wrapper<bool>;
using FCW_I32 = cudf::test::fixed_width_column_wrapper<int32_t>;
using FCW_I64 = cudf::test::fixed_width_column_wrapper<int64_t>;
using STR_CW  = cudf::test::strings_column_wrapper;
using STR_CV  = cudf::strings_column_view;

struct StringsConvertTest : public cudf::test::BaseFixture {
};

TEST_F(StringsConvertTest, IsInteger)
{
  // Empty input
  auto strings = STR_CW{};
  auto results = cudf::strings::is_integer(STR_CV(strings), cudf::data_type{cudf::type_id::INT32});
  EXPECT_EQ(cudf::type_id::BOOL8, results->view().type().id());
  EXPECT_EQ(0, results->view().size());

  strings =
    STR_CW({"+175", "-34", "9.8", "17+2", "+-14", "1234567890", "67de", "", "1e10", "-", "++", ""});
  results       = cudf::strings::is_integer(STR_CV(strings), cudf::data_type{cudf::type_id::INT32});
  auto expected = FCW_B({1, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0});
  CUDF_TEST_EXPECT_COLUMNS_EQUAL(*results, expected);

  strings  = STR_CW({"0", "+0", "-0", "1234567890", "-27341132", "+012", "023", "-045"});
  results  = cudf::strings::is_integer(STR_CV(strings), cudf::data_type{cudf::type_id::INT32});
  expected = FCW_B({1, 1, 1, 1, 1, 1, 1, 1});
  CUDF_TEST_EXPECT_COLUMNS_EQUAL(*results, expected);
}

TEST_F(StringsConvertTest, IsIntegerBoundCheck)
{
  auto strings =
    STR_CW({"-200", "-129", "-128", "-120", "0", "120", "127", "130", "150", "255", "300", "500"});
  auto results  = cudf::strings::is_integer(STR_CV(strings), cudf::data_type{cudf::type_id::INT8});
  auto expected = FCW_B({0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0});
  CUDF_TEST_EXPECT_COLUMNS_EQUAL(*results, expected);

  results  = cudf::strings::is_integer(STR_CV(strings), cudf::data_type{cudf::type_id::UINT8});
  expected = FCW_B({0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0});
  CUDF_TEST_EXPECT_COLUMNS_EQUAL(*results, expected);

  strings =
    STR_CW({"-40000", "-32769", "-32768", "-32767", "-32766", "32765", "32766", "32767", "32768"});
  results  = cudf::strings::is_integer(STR_CV(strings), cudf::data_type{cudf::type_id::INT16});
  expected = FCW_B({0, 0, 1, 1, 1, 1, 1, 1, 0});
  CUDF_TEST_EXPECT_COLUMNS_EQUAL(*results, expected);

  results  = cudf::strings::is_integer(STR_CV(strings), cudf::data_type{cudf::type_id::UINT16});
  expected = FCW_B({0, 0, 0, 0, 0, 1, 1, 1, 1});
  CUDF_TEST_EXPECT_COLUMNS_EQUAL(*results, expected);

  results  = cudf::strings::is_integer(STR_CV(strings), cudf::data_type{cudf::type_id::INT32});
  expected = FCW_B({1, 1, 1, 1, 1, 1, 1, 1, 1});
  CUDF_TEST_EXPECT_COLUMNS_EQUAL(*results, expected);

  strings  = STR_CW({"-2147483649",   // std::numeric_limits<int32_t>::min() - 1
                    "-2147483648",   // std::numeric_limits<int32_t>::min()
                    "-2147483647",   // std::numeric_limits<int32_t>::min() + 1
                    "2147483646",    // std::numeric_limits<int32_t>::max() - 1
                    "2147483647",    // std::numeric_limits<int32_t>::max()
                    "2147483648",    // std::numeric_limits<int32_t>::max() + 1
                    "4294967294",    // std::numeric_limits<uint32_t>::max() - 1
                    "4294967295",    // std::numeric_limits<uint32_t>::max()
                    "4294967296"});  // std::numeric_limits<uint32_t>::max() + 1
  results  = cudf::strings::is_integer(STR_CV(strings), cudf::data_type{cudf::type_id::INT32});
  expected = FCW_B({0, 1, 1, 1, 1, 0, 0, 0, 0});
  CUDF_TEST_EXPECT_COLUMNS_EQUAL(*results, expected);

  results  = cudf::strings::is_integer(STR_CV(strings), cudf::data_type{cudf::type_id::UINT32});
  expected = FCW_B({0, 0, 0, 1, 1, 1, 1, 1, 0});
  CUDF_TEST_EXPECT_COLUMNS_EQUAL(*results, expected);

  strings  = STR_CW({"-9223372036854775809",    // std::numeric_limits<int64_t>::min() - 1
                    "-9223372036854775808",    // std::numeric_limits<int64_t>::min()
                    "-9223372036854775807",    // std::numeric_limits<int64_t>::min() + 1
                    "9223372036854775806",     // std::numeric_limits<int64_t>::max() - 1
                    "9223372036854775807",     // std::numeric_limits<int64_t>::max()
                    "9223372036854775808",     // std::numeric_limits<int64_t>::max() + 1
                    "18446744073709551614",    // std::numeric_limits<uint64_t>::max() - 1
                    "18446744073709551615",    // std::numeric_limits<uint64_t>::max()
                    "18446744073709551616"});  // std::numeric_limits<uint64_t>::max() + 1
  results  = cudf::strings::is_integer(STR_CV(strings), cudf::data_type{cudf::type_id::INT64});
  expected = FCW_B({0, 1, 1, 1, 1, 0, 0, 0, 0});
  CUDF_TEST_EXPECT_COLUMNS_EQUAL(*results, expected);

  results  = cudf::strings::is_integer(STR_CV(strings), cudf::data_type{cudf::type_id::UINT64});
  expected = FCW_B({0, 0, 0, 1, 1, 1, 1, 1, 0});
  CUDF_TEST_EXPECT_COLUMNS_EQUAL(*results, expected);
}

TEST_F(StringsConvertTest, ToInteger)
{
  std::vector<const char*> h_strings{
    "eee", "1234", nullptr, "", "-9832", "93.24", "765é", "-1.78e+5", "2147483647", "-2147483648"};
  STR_CW strings(
    h_strings.begin(),
    h_strings.end(),
    thrust::make_transform_iterator(h_strings.begin(), [](auto str) { return str != nullptr; }));
  std::vector<int32_t> h_expected{0, 1234, 0, 0, -9832, 93, 765, -1, 2147483647, -2147483648};

  auto strings_view = STR_CV(strings);
  auto results = cudf::strings::to_integers(strings_view, cudf::data_type{cudf::type_id::INT32});

  FCW_I32 expected(
    h_expected.begin(),
    h_expected.end(),
    thrust::make_transform_iterator(h_strings.begin(), [](auto str) { return str != nullptr; }));
  CUDF_TEST_EXPECT_COLUMNS_EQUAL(*results, expected);
}

TEST_F(StringsConvertTest, FromInteger)
{
  int32_t minint = std::numeric_limits<int32_t>::min();
  int32_t maxint = std::numeric_limits<int32_t>::max();
  std::vector<int32_t> h_integers{100, 987654321, 0, 0, -12761, 0, 5, -4, maxint, minint};
  std::vector<const char*> h_expected{
    "100", "987654321", nullptr, "0", "-12761", "0", "5", "-4", "2147483647", "-2147483648"};

  FCW_I32 integers(
    h_integers.begin(),
    h_integers.end(),
    thrust::make_transform_iterator(h_expected.begin(), [](auto str) { return str != nullptr; }));

  auto results = cudf::strings::from_integers(integers);

  STR_CW expected(
    h_expected.begin(),
    h_expected.end(),
    thrust::make_transform_iterator(h_expected.begin(), [](auto str) { return str != nullptr; }));

  CUDF_TEST_EXPECT_COLUMNS_EQUAL(*results, expected);
}

TEST_F(StringsConvertTest, ZeroSizeStringsColumn)
{
  cudf::column_view zero_size_column(cudf::data_type{cudf::type_id::INT32}, 0, nullptr, nullptr, 0);
  auto results = cudf::strings::from_integers(zero_size_column);
  cudf::test::expect_strings_empty(results->view());
}

TEST_F(StringsConvertTest, ZeroSizeIntegersColumn)
{
  cudf::column_view zero_size_column(
    cudf::data_type{cudf::type_id::STRING}, 0, nullptr, nullptr, 0);
  auto results =
    cudf::strings::to_integers(zero_size_column, cudf::data_type{cudf::type_id::INT32});
  EXPECT_EQ(0, results->size());
}

TEST_F(StringsConvertTest, EmptyStringsColumn)
{
  STR_CW strings({"", "", ""});
  auto results = cudf::strings::to_integers(STR_CV(strings), cudf::data_type{cudf::type_id::INT64});
  FCW_I64 expected({0, 0, 0});
  CUDF_TEST_EXPECT_COLUMNS_EQUAL(results->view(), expected);
}

template <typename T>
class StringsIntegerConvertTest : public StringsConvertTest {
};

TYPED_TEST_CASE(StringsIntegerConvertTest, cudf::test::IntegralTypesNotBool);

TYPED_TEST(StringsIntegerConvertTest, FromToInteger)
{
  thrust::device_vector<TypeParam> d_integers(255);
  thrust::sequence(
    thrust::device, d_integers.begin(), d_integers.end(), -(TypeParam)(d_integers.size() / 2));
  d_integers.push_back(std::numeric_limits<TypeParam>::min());
  d_integers.push_back(std::numeric_limits<TypeParam>::max());
  auto integers      = cudf::make_numeric_column(cudf::data_type{cudf::type_to_id<TypeParam>()},
                                            (cudf::size_type)d_integers.size());
  auto integers_view = integers->mutable_view();
  CUDA_TRY(cudaMemcpy(integers_view.data<TypeParam>(),
                      d_integers.data().get(),
                      d_integers.size() * sizeof(TypeParam),
                      cudaMemcpyDeviceToDevice));
  integers_view.set_null_count(0);

  // convert to strings
  auto results_strings = cudf::strings::from_integers(integers->view());

  thrust::host_vector<TypeParam> h_integers(d_integers);
  std::vector<std::string> h_strings;
  for (auto itr = h_integers.begin(); itr != h_integers.end(); ++itr)
    h_strings.push_back(std::to_string(*itr));

  STR_CW expected(h_strings.begin(), h_strings.end());
  CUDF_TEST_EXPECT_COLUMNS_EQUAL(*results_strings, expected);

  // convert back to integers
  auto strings_view = STR_CV(results_strings->view());
  auto results_integers =
    cudf::strings::to_integers(strings_view, cudf::data_type(cudf::type_to_id<TypeParam>()));
  CUDF_TEST_EXPECT_COLUMNS_EQUAL(*results_integers, integers->view());
}

//
template <typename T>
class StringsFloatConvertTest : public StringsConvertTest {
};

using FloatTypes = cudf::test::Types<float, double>;
TYPED_TEST_CASE(StringsFloatConvertTest, FloatTypes);

TYPED_TEST(StringsFloatConvertTest, FromToIntegerError)
{
  auto dtype  = cudf::data_type{cudf::type_to_id<TypeParam>()};
  auto column = cudf::make_numeric_column(dtype, 100);
  EXPECT_THROW(cudf::strings::from_integers(column->view()), cudf::logic_error);

  STR_CW strings{"this string intentionally left blank"};
  EXPECT_THROW(cudf::strings::to_integers(column->view(), dtype), cudf::logic_error);
}

TEST_F(StringsConvertTest, HexToInteger)
{
  std::vector<const char*> h_strings{
    "1234", nullptr, "98BEEF", "1a5", "CAFE", "2face", "0xAABBCCDD", "112233445566"};
  STR_CW strings(
    h_strings.begin(),
    h_strings.end(),
    thrust::make_transform_iterator(h_strings.begin(), [](auto str) { return str != nullptr; }));

  {
    std::vector<int32_t> h_expected;
    for (auto itr = h_strings.begin(); itr != h_strings.end(); ++itr) {
      if (*itr == nullptr)
        h_expected.push_back(0);
      else
        h_expected.push_back(static_cast<int>(std::stol(std::string(*itr), 0, 16)));
    }

    auto results =
      cudf::strings::hex_to_integers(STR_CV(strings), cudf::data_type{cudf::type_id::INT32});
    FCW_I32 expected(
      h_expected.begin(),
      h_expected.end(),
      thrust::make_transform_iterator(h_strings.begin(), [](auto str) { return str != nullptr; }));
    CUDF_TEST_EXPECT_COLUMNS_EQUAL(*results, expected);
  }
  {
    std::vector<int64_t> h_expected;
    for (auto itr = h_strings.begin(); itr != h_strings.end(); ++itr) {
      if (*itr == nullptr)
        h_expected.push_back(0);
      else
        h_expected.push_back(std::stol(std::string(*itr), 0, 16));
    }

    auto results =
      cudf::strings::hex_to_integers(STR_CV(strings), cudf::data_type{cudf::type_id::INT64});
    FCW_I64 expected(
      h_expected.begin(),
      h_expected.end(),
      thrust::make_transform_iterator(h_strings.begin(), [](auto str) { return str != nullptr; }));
    CUDF_TEST_EXPECT_COLUMNS_EQUAL(*results, expected);
  }
}

TEST_F(StringsConvertTest, IsHex)
{
  std::vector<const char*> h_strings{"",
                                     "1234",
                                     nullptr,
                                     "98BEEF",
                                     "1a5",
                                     "2face",
                                     "0xAABBCCDD",
                                     "112233445566",
                                     "XYZ",
                                     "0",
                                     "0x",
                                     "x"};
  STR_CW strings(
    h_strings.begin(),
    h_strings.end(),
    thrust::make_transform_iterator(h_strings.begin(), [](auto str) { return str != nullptr; }));
  FCW_B expected({0, 1, 0, 1, 1, 1, 1, 1, 0, 1, 0, 0}, {1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1});
  auto results = cudf::strings::is_hex(STR_CV(strings));
  CUDF_TEST_EXPECT_COLUMNS_EQUAL(*results, expected);
}
