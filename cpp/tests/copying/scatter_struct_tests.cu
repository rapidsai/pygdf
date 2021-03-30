/*
 * Copyright (c) 2020-2021, NVIDIA CORPORATION.
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

#include <cudf_test/base_fixture.hpp>
#include <cudf_test/column_utilities.hpp>
#include <cudf_test/column_wrapper.hpp>
#include <cudf_test/type_lists.hpp>

#include <cudf/column/column_factories.hpp>
#include <cudf/copying.hpp>
#include <cudf/detail/iterator.cuh>
#include <cudf/lists/lists_column_view.hpp>
#include <cudf/structs/structs_column_view.hpp>
#include <cudf/table/table_view.hpp>
#include <cudf/types.hpp>
#include <cudf/utilities/error.hpp>

#include <nvfunctional>

#include <memory>

// using column_vector = std::vector<std::unique_ptr<cudf::column>>;
// using cudf::size_type;
using namespace cudf::test;

struct StructScatterTest : public cudf::test::BaseFixture {
};

template <typename T>
struct TypedStructScatterTest : public cudf::test::BaseFixture {
};

using TestTypes = cudf::test::Concat<cudf::test::IntegralTypes,
                                     cudf::test::FloatingPointTypes,
                                     cudf::test::DurationTypes,
                                     cudf::test::TimestampTypes>;

TYPED_TEST_CASE(TypedStructScatterTest, int);

// Test case when all input columns are empty
TYPED_TEST(TypedStructScatterTest, EmptyInputTest)
{
  auto child_col_src     = fixed_width_column_wrapper<TypeParam, int32_t>{};
  auto const structs_src = structs_column_wrapper{{child_col_src}, std::vector<bool>{}}.release();
  auto const source      = cudf::table_view{std::vector<cudf::column_view>{structs_src->view()}};

  auto child_col_tgt     = fixed_width_column_wrapper<TypeParam, int32_t>{};
  auto const structs_tgt = structs_column_wrapper{{child_col_tgt}, std::vector<bool>{}}.release();
  auto const target      = cudf::table_view{std::vector<cudf::column_view>{structs_tgt->view()}};

  auto const scatter_map = fixed_width_column_wrapper<int32_t>{}.release();
  auto const result      = cudf::scatter(source, scatter_map->view(), target);

  CUDF_TEST_EXPECT_COLUMNS_EQUAL(structs_src->view(), result->get_column(0));
  CUDF_TEST_EXPECT_COLUMNS_EQUAL(structs_tgt->view(), result->get_column(0));
}

// Test case when only the scatter map is empty
TYPED_TEST(TypedStructScatterTest, EmptyScatterMapTest)
{
  auto constexpr null = std::numeric_limits<TypeParam>::max();  // Null child element
  auto constexpr XXX  = std::numeric_limits<TypeParam>::max();  // Null struct element

  auto child_col_src = fixed_width_column_wrapper<TypeParam, int32_t>{
    {0, 1, 2, 3, null, XXX},
    cudf::detail::make_counting_transform_iterator(0, [](auto i) { return i != 4; })};
  auto const structs_src = structs_column_wrapper{
    {child_col_src}, cudf::detail::make_counting_transform_iterator(0, [](auto i) {
      return i != 5;
    })}.release();
  auto const source = cudf::table_view{std::vector<cudf::column_view>{structs_src->view()}};

  auto child_col_tgt = fixed_width_column_wrapper<TypeParam, int32_t>{
    {50, null, 70, XXX, 90, 100},
    cudf::detail::make_counting_transform_iterator(0, [](auto i) { return i != 1; })};
  auto const structs_tgt = structs_column_wrapper{
    {child_col_tgt}, cudf::detail::make_counting_transform_iterator(0, [](auto i) {
      return i != 3;
    })}.release();
  auto const target = cudf::table_view{std::vector<cudf::column_view>{structs_tgt->view()}};

  auto const scatter_map = fixed_width_column_wrapper<int32_t>{}.release();
  auto const result      = cudf::scatter(source, scatter_map->view(), target);
  CUDF_TEST_EXPECT_COLUMNS_EQUAL(structs_tgt->view(), result->get_column(0));
}

TYPED_TEST(TypedStructScatterTest, ScatterAsCopyTest)
{
  auto constexpr null = std::numeric_limits<TypeParam>::max();  // Null child element
  auto constexpr XXX  = std::numeric_limits<TypeParam>::max();  // Null struct element

  auto child_col_src = fixed_width_column_wrapper<TypeParam, int32_t>{
    {0, 1, 2, 3, null, XXX},
    cudf::detail::make_counting_transform_iterator(0, [](auto i) { return i != 4; })};
  auto const structs_src = structs_column_wrapper{
    {child_col_src}, cudf::detail::make_counting_transform_iterator(0, [](auto i) {
      return i != 5;
    })}.release();
  auto const source = cudf::table_view{std::vector<cudf::column_view>{structs_src->view()}};

  auto child_col_tgt = fixed_width_column_wrapper<TypeParam, int32_t>{
    {50, null, 70, XXX, 90, 100},
    cudf::detail::make_counting_transform_iterator(0, [](auto i) { return i != 1; })};
  auto const structs_tgt = structs_column_wrapper{
    {child_col_tgt}, cudf::detail::make_counting_transform_iterator(0, [](auto i) {
      return i != 3;
    })}.release();
  auto target = cudf::table_view{std::vector<cudf::column_view>{structs_tgt->view()}};

  // Scatter as copy: the target should be the same as source
  auto const scatter_map = fixed_width_column_wrapper<int32_t>{0, 1, 2, 3, 4, 5}.release();
  auto const result      = cudf::scatter(source, scatter_map->view(), target);

  CUDF_TEST_EXPECT_COLUMNS_EQUAL(structs_src->view(), result->get_column(0));
}

TYPED_TEST(TypedStructScatterTest, ScatterAsLeftShiftTest)
{
  auto constexpr null = std::numeric_limits<TypeParam>::max();  // Null child element
  auto constexpr XXX  = std::numeric_limits<TypeParam>::max();  // Null struct element

  auto child_col_src = fixed_width_column_wrapper<TypeParam, int32_t>{
    {0, 1, 2, 3, null, XXX},
    cudf::detail::make_counting_transform_iterator(0, [](auto i) { return i != 4; })};
  auto const structs_src = structs_column_wrapper{
    {child_col_src}, cudf::detail::make_counting_transform_iterator(0, [](auto i) {
      return i != 5;
    })}.release();
  auto const source = cudf::table_view{std::vector<cudf::column_view>{structs_src->view()}};

  auto child_col_tgt = fixed_width_column_wrapper<TypeParam, int32_t>{
    {50, null, 70, XXX, 90, 100},
    cudf::detail::make_counting_transform_iterator(0, [](auto i) { return i != 1; })};
  auto const structs_tgt = structs_column_wrapper{
    {child_col_tgt}, cudf::detail::make_counting_transform_iterator(0, [](auto i) {
      return i != 3;
    })}.release();
  auto const target = cudf::table_view{std::vector<cudf::column_view>{structs_tgt->view()}};

  auto child_col_expected = fixed_width_column_wrapper<TypeParam, int32_t>{
    {2, 3, null, XXX, 0, 1},
    cudf::detail::make_counting_transform_iterator(0, [](auto i) { return i != 2; })};
  auto structs_expected = structs_column_wrapper{
    {child_col_expected}, cudf::detail::make_counting_transform_iterator(0, [](auto i) {
      return i != 3;
    })}.release();

  auto const scatter_map = fixed_width_column_wrapper<int32_t>{-2, -1, 0, 1, 2, 3}.release();
  auto const result      = cudf::scatter(source, scatter_map->view(), target);
  CUDF_TEST_EXPECT_COLUMNS_EQUAL(structs_expected->view(), result->get_column(0));
}

TYPED_TEST(TypedStructScatterTest, SimpleScatterTests)
{
  auto constexpr null = std::numeric_limits<TypeParam>::max();  // Null child element
  auto constexpr XXX  = std::numeric_limits<TypeParam>::max();  // Null struct element

  auto child_col_src = fixed_width_column_wrapper<TypeParam, int32_t>{
    {0, 1, 2, 3, null, XXX},
    cudf::detail::make_counting_transform_iterator(0, [](auto i) { return i != 4; })};
  auto const structs_src = structs_column_wrapper{
    {child_col_src}, cudf::detail::make_counting_transform_iterator(0, [](auto i) {
      return i != 5;
    })}.release();
  auto const source = cudf::table_view{std::vector<cudf::column_view>{structs_src->view()}};

  auto child_col_tgt = fixed_width_column_wrapper<TypeParam, int32_t>{
    {50, null, 70, XXX, 90, 100},
    cudf::detail::make_counting_transform_iterator(0, [](auto i) { return i != 1; })};
  auto const structs_tgt = structs_column_wrapper{
    {child_col_tgt}, cudf::detail::make_counting_transform_iterator(0, [](auto i) {
      return i != 3;
    })}.release();
  auto target = cudf::table_view{std::vector<cudf::column_view>{structs_tgt->view()}};

  auto child_col_expected1 = fixed_width_column_wrapper<TypeParam, int32_t>{
    {1, null, 70, XXX, 0, 2},
    cudf::detail::make_counting_transform_iterator(0, [](auto i) { return i != 1; })};
  auto const structs_expected1 = structs_column_wrapper{
    {child_col_expected1}, cudf::detail::make_counting_transform_iterator(0, [](auto i) {
      return i != 3;
    })}.release();
  auto const scatter_map1 = fixed_width_column_wrapper<int32_t>{-2, 0, 5}.release();
  auto const result1      = cudf::scatter(source, scatter_map1->view(), target);
  CUDF_TEST_EXPECT_COLUMNS_EQUAL(structs_expected1->view(), result1->get_column(0));

  auto child_col_expected2 = fixed_width_column_wrapper<TypeParam, int32_t>{
    {1, null, 70, 3, 0, 2},
    cudf::detail::make_counting_transform_iterator(0, [](auto i) { return i != 1; })};
  auto const structs_expected2 = structs_column_wrapper{
    {child_col_expected2}, cudf::detail::make_counting_transform_iterator(0, [](auto i) {
      return true;
    })}.release();
  auto const scatter_map2 = fixed_width_column_wrapper<int32_t>{-2, 0, 5, 3}.release();
  auto const result2      = cudf::scatter(source, scatter_map2->view(), target);
  CUDF_TEST_EXPECT_COLUMNS_EQUAL(structs_expected2->view(), result2->get_column(0));
}

TYPED_TEST(TypedStructScatterTest, ComplexDataTest)
{
  // Testing scatter() on struct<string, numeric, bool>.

  // 1. String "names" column.
  auto const names_src =
    std::vector<std::string>{"Newton", "Washington", "Cherry", "Kiwi", "Lemon", "Tomato"};
  auto const names_validity_src = std::vector<bool>{1, 1, 1, 1, 1, 1};
  auto names_column_src =
    strings_column_wrapper{names_src.begin(), names_src.end(), names_validity_src.begin()};

  // 2. Numeric "ages" column.
  auto const ages_src          = std::vector<int32_t>{5, 10, 15, 20, 25, 30};
  auto const ages_validity_src = std::vector<bool>{1, 1, 1, 1, 0, 1};
  auto ages_column_src         = fixed_width_column_wrapper<TypeParam, int32_t>{
    ages_src.begin(), ages_src.end(), ages_validity_src.begin()};

  // 3. Boolean "is_human" column.
  auto const is_human_src          = {true, true, false, false, false, false};
  auto const is_human_validity_src = std::vector<bool>{1, 1, 1, 0, 1, 1};
  auto is_human_col_src            = fixed_width_column_wrapper<bool>{
    is_human_src.begin(), is_human_src.end(), is_human_validity_src.begin()};

  // Assemble struct column.
  auto const struct_validity_src = std::vector<bool>{1, 1, 1, 1, 1, 0};
  auto structs_src = structs_column_wrapper{{names_column_src, ages_column_src, is_human_col_src},
                                            struct_validity_src.begin()}
                       .release();

  // 1. String "names" column.
  auto const names_tgt = std::vector<std::string>{
    "String 0", "String 1", "String 2", "String 3", "String 4", "String 5"};
  auto const names_validity_tgt = std::vector<bool>{0, 1, 1, 1, 1, 1};
  auto names_column_tgt =
    strings_column_wrapper{names_tgt.begin(), names_tgt.end(), names_validity_tgt.begin()};

  // 2. Numeric "ages" column.
  auto const ages_tgt          = std::vector<int32_t>{50, 60, 70, 80, 90, 100};
  auto const ages_validity_tgt = std::vector<bool>{1, 0, 1, 1, 1, 1};
  auto ages_column_tgt         = fixed_width_column_wrapper<TypeParam, int32_t>{
    ages_tgt.begin(), ages_tgt.end(), ages_validity_tgt.begin()};

  // 3. Boolean "is_human" column.
  auto const is_human_tgt          = {true, true, true, true, true, true};
  auto const is_human_validity_tgt = std::vector<bool>{1, 1, 1, 1, 1, 1};
  auto is_human_col_tgt            = fixed_width_column_wrapper<bool>{
    is_human_tgt.begin(), is_human_tgt.end(), is_human_validity_tgt.begin()};

  // Assemble struct column.
  auto const struct_validity_tgt = std::vector<bool>{1, 1, 0, 1, 1, 1};
  auto structs_tgt = structs_column_wrapper{{names_column_tgt, ages_column_tgt, is_human_col_tgt},
                                            struct_validity_tgt.begin()}
                       .release();

  // 1. String "names" column.
  auto const names_expected =
    std::vector<std::string>{"String 0", "Lemon", "Kiwi", "Cherry", "Washington", "Newton"};
  auto const names_validity_expected = std::vector<bool>{0, 1, 1, 1, 1, 1};
  auto names_column_expected         = strings_column_wrapper{
    names_expected.begin(), names_expected.end(), names_validity_expected.begin()};

  // 2. Numeric "ages" column.
  auto const ages_expected          = std::vector<int32_t>{50, 25, 20, 15, 10, 5};
  auto const ages_validity_expected = std::vector<bool>{1, 0, 1, 1, 1, 1};
  auto ages_column_expected         = fixed_width_column_wrapper<TypeParam, int32_t>{
    ages_expected.begin(), ages_expected.end(), ages_validity_expected.begin()};

  // 3. Boolean "is_human" column.
  auto const is_human_expected          = {true, false, false, false, true, true};
  auto const is_human_validity_expected = std::vector<bool>{1, 1, 0, 1, 1, 1};
  auto is_human_col_expected            = fixed_width_column_wrapper<bool>{
    is_human_expected.begin(), is_human_expected.end(), is_human_validity_expected.begin()};

  // Assemble struct column.
  auto const struct_validity_expected = std::vector<bool>{1, 1, 1, 1, 1, 1};
  auto structs_expected =
    structs_column_wrapper{{names_column_expected, ages_column_expected, is_human_col_expected},
                           struct_validity_expected.begin()}
      .release();

  auto const scatter_map = fixed_width_column_wrapper<int32_t>{-1, 4, 3, 2, 1}.release();
  auto const source      = cudf::table_view{std::vector<cudf::column_view>{structs_src->view()}};
  auto const target      = cudf::table_view{std::vector<cudf::column_view>{structs_tgt->view()}};
  auto const result      = cudf::scatter(source, scatter_map->view(), target);
  CUDF_TEST_EXPECT_COLUMNS_EQUAL(structs_expected->view(), result->get_column(0), true);
}

#if 0
TYPED_TEST(TypedStructScatterTest, TestSimpleStructGather)
{
  // Testing gather() on struct<string, numeric, bool>.

  // 1. String "names" column.
  auto const names =
    std::vector<std::string>{"Vimes", "Carrot", "Angua", "Cheery", "Detritus", "Slant"};
  auto const names_validity = std::vector<bool>{1, 1, 1, 1, 1, 1};
  auto names_column = strings_column_wrapper{names.begin(), names.end(), names_validity.begin()};

  // 2. Numeric "ages" column.
  auto const ages          = std::vector<int32_t>{5, 10, 15, 20, 25, 30};
  auto const ages_validity = std::vector<bool>{1, 1, 1, 1, 0, 1};
  auto ages_column =
    fixed_width_column_wrapper<TypeParam, int32_t>{ages.begin(), ages.end(), ages_validity.begin()};

  // 3. Boolean "is_human" column.
  auto const is_human          = {true, true, false, false, false, false};
  auto const is_human_validity = std::vector<bool>{1, 1, 1, 0, 1, 1};
  auto is_human_col =
    fixed_width_column_wrapper<bool>{is_human.begin(), is_human.end(), is_human_validity.begin()};

  // Assemble struct column.
  auto const struct_validity = std::vector<bool>{1, 1, 1, 1, 1, 0};
  auto struct_column =
    structs_column_wrapper{{names_column, ages_column, is_human_col}, struct_validity.begin()}
      .release();

  // Gather to new struct column.
  auto const scatter_map = std::vector<int>{-1, 4, 3, 2, 1};
  auto const gather_map_col =
    fixed_width_column_wrapper<int32_t>(scatter_map.begin(), scatter_map.end()).release();

  auto const gathered_table =
    cudf::gather(cudf::table_view{std::vector<cudf::column_view>{struct_column->view()}},
                 gather_map_col->view());

  auto const gathered_struct_col      = gathered_table->get_column(0);
  auto const gathered_struct_col_view = cudf::structs_column_view{gathered_struct_col};

  // Verify that the gathered struct's fields are as expected.

  auto expected_names_column =
    get_expected_column<std::string>(names, names_validity, struct_validity, scatter_map);
  expect_columns_equivalent(*expected_names_column, gathered_struct_col.child(0));

  auto expected_ages_column =
    get_expected_column<TypeParam, int32_t>(ages, ages_validity, struct_validity, scatter_map);
  expect_columns_equivalent(*expected_ages_column, gathered_struct_col.child(1));

  auto expected_bool_column =
    get_expected_column<bool>(std::vector<bool>(is_human.begin(), is_human.end()),
                              is_human_validity,
                              struct_validity,
                              scatter_map);
  expect_columns_equivalent(*expected_bool_column, gathered_struct_col.child(2));

  std::vector<std::unique_ptr<cudf::column>> expected_columns;
  expected_columns.push_back(std::move(expected_names_column));
  expected_columns.push_back(std::move(expected_ages_column));
  expected_columns.push_back(std::move(expected_bool_column));
  auto const expected_struct_column =
    structs_column_wrapper{std::move(expected_columns), std::vector<bool>{0, 1, 1, 1, 1}}.release();

  expect_columns_equivalent(*expected_struct_column, gathered_struct_col);
}

TYPED_TEST(TypedStructScatterTest, TestGatherStructOfLists)
{
  using namespace cudf::test;

  // Testing gather() on struct<list<numeric>>

  auto lists_column_exemplar = []() {
    return lists_column_wrapper<TypeParam, int32_t>{
      {{5}, {10, 15}, {20, 25, 30}, {35, 40, 45, 50}, {55, 60, 65}, {70, 75}, {80}, {}, {}},
      cudf::detail::make_counting_transform_iterator(0, [](auto i) { return !(i % 3); })};
  };

  auto lists_column = std::make_unique<cudf::column>(cudf::column(lists_column_exemplar(), 0));

  // Assemble struct column.
  std::vector<std::unique_ptr<cudf::column>> column_vector;
  column_vector.push_back(std::move(lists_column));
  auto const struct_column = structs_column_wrapper{std::move(column_vector)}.release();

  // Gather to new struct column.
  auto const scatter_map = std::vector<int>{-1, 4, 3, 2, 1, 7, 3};
  auto const gather_map_col =
    fixed_width_column_wrapper<int32_t>(scatter_map.begin(), scatter_map.end()).release();

  auto const gathered_table =
    cudf::gather(cudf::table_view{std::vector<cudf::column_view>{struct_column->view()}},
                 gather_map_col->view());

  auto const gathered_struct_col      = gathered_table->get_column(0);
  auto const gathered_struct_col_view = cudf::structs_column_view{gathered_struct_col};

  // Verify that the gathered struct column's list member presents as if
  // it had itself been gathered individually.

  auto const list_column_before_gathering = lists_column_exemplar().release();

  auto const expected_gathered_list_column =
    cudf::gather(
      cudf::table_view{std::vector<cudf::column_view>{list_column_before_gathering->view()}},
      gather_map_col->view())
      ->get_column(0);

  expect_columns_equivalent(expected_gathered_list_column.view(), gathered_struct_col.child(0));
}

TYPED_TEST(TypedStructScatterTest, TestGatherStructOfListsOfLists)
{
  using namespace cudf::test;

  // Testing gather() on struct<list<list<numeric>>>

  auto const lists_column_exemplar = []() {
    return lists_column_wrapper<TypeParam, int32_t>{
      {{{5, 5}},
       {{10, 15}},
       {{20, 25}, {30}},
       {{35, 40}, {45, 50}},
       {{55}, {60, 65}},
       {{70, 75}},
       {{80, 80}},
       {},
       {}},
      cudf::detail::make_counting_transform_iterator(0, [](auto i) { return !(i % 3); })};
  };

  auto lists_column = std::make_unique<cudf::column>(cudf::column(lists_column_exemplar(), 0));

  // Assemble struct column.
  std::vector<std::unique_ptr<cudf::column>> column_vector;
  column_vector.push_back(std::move(lists_column));
  auto const struct_column = structs_column_wrapper{std::move(column_vector)}.release();

  // Gather to new struct column.
  auto const scatter_map = std::vector<int>{-1, 4, 3, 2, 1, 7, 3};
  auto const gather_map_col =
    fixed_width_column_wrapper<int32_t>(scatter_map.begin(), scatter_map.end()).release();

  auto const gathered_table =
    cudf::gather(cudf::table_view{std::vector<cudf::column_view>{struct_column->view()}},
                 gather_map_col->view());

  auto const gathered_struct_col      = gathered_table->get_column(0);
  auto const gathered_struct_col_view = cudf::structs_column_view{gathered_struct_col};

  // Verify that the gathered struct column's list member presents as if
  // it had itself been gathered individually.

  auto const list_column_before_gathering = lists_column_exemplar().release();

  auto const expected_gathered_list_column =
    cudf::gather(
      cudf::table_view{std::vector<cudf::column_view>{list_column_before_gathering->view()}},
      gather_map_col->view())
      ->get_column(0);

  expect_columns_equivalent(expected_gathered_list_column.view(), gathered_struct_col.child(0));
}

TYPED_TEST(TypedStructScatterTest, TestGatherStructOfStructs)
{
  using namespace cudf::test;

  // Testing gather() on struct<struct<numeric>>

  auto const numeric_column_exemplar = []() {
    return fixed_width_column_wrapper<TypeParam, int32_t>{
      {5, 10, 15, 20, 25, 30, 35, 45, 50, 55, 60, 65, 70, 75},
      cudf::detail::make_counting_transform_iterator(0, [](auto i) { return !(i % 3); })};
  };

  auto numeric_column = numeric_column_exemplar();
  auto structs_column = structs_column_wrapper{{numeric_column}};

  auto const struct_of_structs_column = structs_column_wrapper{{structs_column}}.release();

  // Gather to new struct column.
  auto const scatter_map = std::vector<int>{-1, 4, 3, 2, 1, 7, 3};
  auto const gather_map_col =
    fixed_width_column_wrapper<int32_t>(scatter_map.begin(), scatter_map.end()).release();

  auto const gathered_table =
    cudf::gather(cudf::table_view{std::vector<cudf::column_view>{struct_of_structs_column->view()}},
                 gather_map_col->view());

  auto const gathered_struct_col      = gathered_table->get_column(0);
  auto const gathered_struct_col_view = cudf::structs_column_view{gathered_struct_col};

  // Verify that the underlying numeric column presents as if
  // it had itself been gathered individually.

  auto const numeric_column_before_gathering = numeric_column_exemplar().release();
  auto const expected_gathered_column =
    cudf::gather(
      cudf::table_view{std::vector<cudf::column_view>{numeric_column_before_gathering->view()}},
      gather_map_col->view())
      ->get_column(0);

  expect_columns_equivalent(expected_gathered_column, gathered_struct_col.child(0).child(0).view());
}

TYPED_TEST(TypedStructScatterTest, TestGatherStructOfListOfStructs)
{
  using namespace cudf::test;

  // Testing gather() on struct<struct<numeric>>

  auto const numeric_column_exemplar = []() {
    return fixed_width_column_wrapper<TypeParam, int32_t>{
      {5, 10, 15, 20, 25, 30, 35, 45, 50, 55, 60, 65, 70, 75}};
  };

  auto numeric_column         = numeric_column_exemplar();
  auto structs_column         = structs_column_wrapper{{numeric_column}}.release();
  auto list_of_structs_column = cudf::make_lists_column(
    7,
    fixed_width_column_wrapper<int32_t>{0, 2, 4, 6, 8, 10, 12, 14}.release(),
    std::move(structs_column),
    cudf::UNKNOWN_NULL_COUNT,
    {});

  std::vector<std::unique_ptr<cudf::column>> column_vector;
  column_vector.push_back(std::move(list_of_structs_column));
  auto const struct_of_list_of_structs = structs_column_wrapper{std::move(column_vector)}.release();

  // Gather to new struct column.
  auto const scatter_map = std::vector<int>{-1, 4, 3, 2, 1};
  auto const gather_map_col =
    fixed_width_column_wrapper<int32_t>(scatter_map.begin(), scatter_map.end()).release();

  auto const gathered_table = cudf::gather(
    cudf::table_view{std::vector<cudf::column_view>{struct_of_list_of_structs->view()}},
    gather_map_col->view());

  auto const gathered_struct_col      = gathered_table->get_column(0);
  auto const gathered_struct_col_view = cudf::structs_column_view{gathered_struct_col};

  // Construct expected gather result.

  auto expected_numeric_col =
    fixed_width_column_wrapper<TypeParam, int32_t>{{70, 75, 50, 55, 35, 45, 25, 30, 15, 20}};
  auto expected_struct_col = structs_column_wrapper{{expected_numeric_col}}.release();
  auto expected_list_of_structs_column =
    cudf::make_lists_column(5,
                            fixed_width_column_wrapper<int32_t>{0, 2, 4, 6, 8, 10}.release(),
                            std::move(expected_struct_col),
                            cudf::UNKNOWN_NULL_COUNT,
                            {});
  std::vector<std::unique_ptr<cudf::column>> expected_vector_of_columns;
  expected_vector_of_columns.push_back(std::move(expected_list_of_structs_column));
  auto const expected_struct_of_list_of_struct =
    structs_column_wrapper{std::move(expected_vector_of_columns)}.release();

  expect_columns_equivalent(expected_struct_of_list_of_struct->view(), gathered_struct_col.view());
}

TYPED_TEST(TypedStructScatterTest, TestGatherStructOfStructsWithValidity)
{
  using namespace cudf::test;

  // Testing gather() on struct<struct<numeric>>

  // Factory to construct numeric column with configurable null-mask.
  auto const numeric_column_exemplar = [](nvstd::function<bool(size_type)> pred) {
    return fixed_width_column_wrapper<TypeParam, int32_t>{
      {5, 10, 15, 20, 25, 30, 35, 45, 50, 55, 60, 65, 70, 75},
      cudf::detail::make_counting_transform_iterator(0, [=](auto i) { return pred(i); })};
  };

  // Validity predicates.
  auto const every_3rd_element_null = [](size_type i) { return !(i % 3); };
  auto const twelfth_element_null   = [](size_type i) { return i != 11; };

  // Construct struct-of-struct-of-numerics.
  auto numeric_column = numeric_column_exemplar(every_3rd_element_null);
  auto structs_column = structs_column_wrapper{
    {numeric_column}, cudf::detail::make_counting_transform_iterator(0, twelfth_element_null)};
  auto struct_of_structs_column = structs_column_wrapper{{structs_column}}.release();

  // Gather to new struct column.
  auto const scatter_map = std::vector<int>{-1, 4, 3, 2, 1, 7, 3};
  auto const gather_map_col =
    fixed_width_column_wrapper<int32_t>(scatter_map.begin(), scatter_map.end()).release();

  auto const gathered_table =
    cudf::gather(cudf::table_view{std::vector<cudf::column_view>{struct_of_structs_column->view()}},
                 gather_map_col->view());

  auto const gathered_struct_col      = gathered_table->get_column(0);
  auto const gathered_struct_col_view = cudf::structs_column_view{gathered_struct_col};

  // Verify that the underlying numeric column presents as if
  // it had itself been gathered individually.

  auto const final_predicate = [=](size_type i) {
    return every_3rd_element_null(i) && twelfth_element_null(i);
  };
  auto const numeric_column_before_gathering = numeric_column_exemplar(final_predicate).release();
  auto const expected_gathered_column =
    cudf::gather(
      cudf::table_view{std::vector<cudf::column_view>{numeric_column_before_gathering->view()}},
      gather_map_col->view())
      ->get_column(0);

  expect_columns_equivalent(expected_gathered_column, gathered_struct_col.child(0).child(0).view());
}
#endif
