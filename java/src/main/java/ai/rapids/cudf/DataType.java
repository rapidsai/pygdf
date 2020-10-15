/*
 * Copyright (c) 2020, NVIDIA CORPORATION.
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
package ai.rapids.cudf;

public class DataType {

  final DType typeId;
  int scale = 0;

  public DataType(DType id) { typeId = id; }

  public DataType(DType id, int decimalScale) {
    typeId = id;
    scale = decimalScale;
  }

  public boolean isTimestamp() { return typeId.isTimestamp();}

  public boolean hasTimeResolution() { return typeId.hasTimeResolution(); }

  public boolean isBackedByInt() { return typeId.isBackedByInt(); }

  public boolean isBackedByLong() { return typeId.isBackedByLong(); }

  public boolean isBackedByShort() { return typeId.isBackedByShort(); }

  public boolean isBackedByByte() { return typeId.isBackedByByte(); }

  public boolean isNestedType() { return typeId.isNestedType(); }

  public int getNativeId() { return typeId.getNativeId(); }

}
