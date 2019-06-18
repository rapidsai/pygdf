/*
 * Copyright 2019 BlazingDB, Inc.
 *     Copyright 2019 Christian Cordova Estrada <christianc@blazingdb.com>
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

#ifndef GIS_HPP
#define GIS_HPP

#include "cudf.h"

namespace cudf {

/** 
 * @brief Determine whether or not coordinates (query points) are completely inside a static polygon
 * 
 * Note: The polygon must not have holes or intersect with itself, but it is not
 * required to be convex.
 * 
 * The polygon is defined by a set of coordinates (latitudes and longitudes),
 * where the first and last coordinates must have the same value (closed).
 * 
 * This function supports clockwise and counter-clockwise polygons.
 * 
 * If a query point is colinear with two contiguous polygon coordinates
 * then this query point isn't inside.
 * 
 * polygon_latitudes and polygon_longitudes must have equal size.
 * 
 * point_latitudes and point_longitudes must have equal size.
 * 
 * All input params must have equal datatypes (for numeric operations).
 *
 * @param[in] polygon_latitudes: column with latitudes of a polygon
 * @param[in] polygon_longitudes: column with longitudes of a polygon
 * @param[in] query_point_latitudes: column with latitudes of query points
 * @param[in] query_point_longitudes: column with longitudes of query points
 *
 * @returns gdf_column of type GDF_BOOL8 indicating whether the i-th query point is inside (true) or not (false)
 */
gdf_column point_in_polygon( gdf_column const & polygon_latitudes,
                             gdf_column const & polygon_longitudes,
                             gdf_column const & query_point_latitudes,
                             gdf_column const & query_point_longitudes );

/**
 * @brief Compute the perimeter of polygons on the Earth surface using Haversine formula.
 * 
 * Note: The polygons must not have holes
 * 
 * The polygons are defined by sets of coordinates (latitudes and longitudes),
 * where the first and last coordinates of each polygon must have the same value (closed).
 * 
 * polygon_latitudes and polygon_longitudes must have equal size to 'num_polygons'.
 *
 * All latitudes and longitudes must have equal datatypes (for numeric operations).
 * 
 * @param[in] polygons_latitudes[]: set of columns with latitudes of polygons
 * @param[in] polygons_longitudes[]: set of columns with longitudes of polygons
 * @param[in] num_polygons: Number of polygons
 *
 * @returns gdf_column of perimeters with size 'num_polygons'
 */
gdf_column perimeter( gdf_column* polygons_latitudes[],
					  gdf_column* polygons_longitudes[],
					  gdf_size_type const & num_polygons );

}  // namespace cudf

#endif  // GIS_H
