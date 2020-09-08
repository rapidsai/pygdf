# flake8: noqa
# fmt: off
# -*- coding: utf-8 -*-
# Generated by the protocol buffer compiler.  DO NOT EDIT!
# source: orc_column_statistics.proto
"""Generated protocol buffer code."""
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from google.protobuf import reflection as _reflection
from google.protobuf import symbol_database as _symbol_database
# @@protoc_insertion_point(imports)

_sym_db = _symbol_database.Default()




DESCRIPTOR = _descriptor.FileDescriptor(
  name='orc_column_statistics.proto',
  package='',
  syntax='proto2',
  serialized_options=None,
  create_key=_descriptor._internal_create_key,
  serialized_pb=b'\n\x1borc_column_statistics.proto\"B\n\x11IntegerStatistics\x12\x0f\n\x07minimum\x18\x01 \x01(\x12\x12\x0f\n\x07maximum\x18\x02 \x01(\x12\x12\x0b\n\x03sum\x18\x03 \x01(\x12\"A\n\x10\x44oubleStatistics\x12\x0f\n\x07minimum\x18\x01 \x01(\x01\x12\x0f\n\x07maximum\x18\x02 \x01(\x01\x12\x0b\n\x03sum\x18\x03 \x01(\x01\"A\n\x10StringStatistics\x12\x0f\n\x07minimum\x18\x01 \x01(\t\x12\x0f\n\x07maximum\x18\x02 \x01(\t\x12\x0b\n\x03sum\x18\x03 \x01(\x12\"%\n\x10\x42ucketStatistics\x12\x11\n\x05\x63ount\x18\x01 \x03(\x04\x42\x02\x10\x01\"B\n\x11\x44\x65\x63imalStatistics\x12\x0f\n\x07minimum\x18\x01 \x01(\t\x12\x0f\n\x07maximum\x18\x02 \x01(\t\x12\x0b\n\x03sum\x18\x03 \x01(\t\"2\n\x0e\x44\x61teStatistics\x12\x0f\n\x07minimum\x18\x01 \x01(\x11\x12\x0f\n\x07maximum\x18\x02 \x01(\x11\"_\n\x13TimestampStatistics\x12\x0f\n\x07minimum\x18\x01 \x01(\x12\x12\x0f\n\x07maximum\x18\x02 \x01(\x12\x12\x12\n\nminimumUtc\x18\x03 \x01(\x12\x12\x12\n\nmaximumUtc\x18\x04 \x01(\x12\"\x1f\n\x10\x42inaryStatistics\x12\x0b\n\x03sum\x18\x01 \x01(\x12\"\xa5\x03\n\x10\x43olumnStatistics\x12\x16\n\x0enumberOfValues\x18\x01 \x01(\x04\x12)\n\rintStatistics\x18\x02 \x01(\x0b\x32\x12.IntegerStatistics\x12+\n\x10\x64oubleStatistics\x18\x03 \x01(\x0b\x32\x11.DoubleStatistics\x12+\n\x10stringStatistics\x18\x04 \x01(\x0b\x32\x11.StringStatistics\x12+\n\x10\x62ucketStatistics\x18\x05 \x01(\x0b\x32\x11.BucketStatistics\x12-\n\x11\x64\x65\x63imalStatistics\x18\x06 \x01(\x0b\x32\x12.DecimalStatistics\x12\'\n\x0e\x64\x61teStatistics\x18\x07 \x01(\x0b\x32\x0f.DateStatistics\x12+\n\x10\x62inaryStatistics\x18\x08 \x01(\x0b\x32\x11.BinaryStatistics\x12\x31\n\x13timestampStatistics\x18\t \x01(\x0b\x32\x14.TimestampStatistics\x12\x0f\n\x07hasNull\x18\n \x01(\x08'
)




_INTEGERSTATISTICS = _descriptor.Descriptor(
  name='IntegerStatistics',
  full_name='IntegerStatistics',
  filename=None,
  file=DESCRIPTOR,
  containing_type=None,
  create_key=_descriptor._internal_create_key,
  fields=[
    _descriptor.FieldDescriptor(
      name='minimum', full_name='IntegerStatistics.minimum', index=0,
      number=1, type=18, cpp_type=2, label=1,
      has_default_value=False, default_value=0,
      message_type=None, enum_type=None, containing_type=None,
      is_extension=False, extension_scope=None,
      serialized_options=None, file=DESCRIPTOR,  create_key=_descriptor._internal_create_key),
    _descriptor.FieldDescriptor(
      name='maximum', full_name='IntegerStatistics.maximum', index=1,
      number=2, type=18, cpp_type=2, label=1,
      has_default_value=False, default_value=0,
      message_type=None, enum_type=None, containing_type=None,
      is_extension=False, extension_scope=None,
      serialized_options=None, file=DESCRIPTOR,  create_key=_descriptor._internal_create_key),
    _descriptor.FieldDescriptor(
      name='sum', full_name='IntegerStatistics.sum', index=2,
      number=3, type=18, cpp_type=2, label=1,
      has_default_value=False, default_value=0,
      message_type=None, enum_type=None, containing_type=None,
      is_extension=False, extension_scope=None,
      serialized_options=None, file=DESCRIPTOR,  create_key=_descriptor._internal_create_key),
  ],
  extensions=[
  ],
  nested_types=[],
  enum_types=[
  ],
  serialized_options=None,
  is_extendable=False,
  syntax='proto2',
  extension_ranges=[],
  oneofs=[
  ],
  serialized_start=31,
  serialized_end=97,
)


_DOUBLESTATISTICS = _descriptor.Descriptor(
  name='DoubleStatistics',
  full_name='DoubleStatistics',
  filename=None,
  file=DESCRIPTOR,
  containing_type=None,
  create_key=_descriptor._internal_create_key,
  fields=[
    _descriptor.FieldDescriptor(
      name='minimum', full_name='DoubleStatistics.minimum', index=0,
      number=1, type=1, cpp_type=5, label=1,
      has_default_value=False, default_value=float(0),
      message_type=None, enum_type=None, containing_type=None,
      is_extension=False, extension_scope=None,
      serialized_options=None, file=DESCRIPTOR,  create_key=_descriptor._internal_create_key),
    _descriptor.FieldDescriptor(
      name='maximum', full_name='DoubleStatistics.maximum', index=1,
      number=2, type=1, cpp_type=5, label=1,
      has_default_value=False, default_value=float(0),
      message_type=None, enum_type=None, containing_type=None,
      is_extension=False, extension_scope=None,
      serialized_options=None, file=DESCRIPTOR,  create_key=_descriptor._internal_create_key),
    _descriptor.FieldDescriptor(
      name='sum', full_name='DoubleStatistics.sum', index=2,
      number=3, type=1, cpp_type=5, label=1,
      has_default_value=False, default_value=float(0),
      message_type=None, enum_type=None, containing_type=None,
      is_extension=False, extension_scope=None,
      serialized_options=None, file=DESCRIPTOR,  create_key=_descriptor._internal_create_key),
  ],
  extensions=[
  ],
  nested_types=[],
  enum_types=[
  ],
  serialized_options=None,
  is_extendable=False,
  syntax='proto2',
  extension_ranges=[],
  oneofs=[
  ],
  serialized_start=99,
  serialized_end=164,
)


_STRINGSTATISTICS = _descriptor.Descriptor(
  name='StringStatistics',
  full_name='StringStatistics',
  filename=None,
  file=DESCRIPTOR,
  containing_type=None,
  create_key=_descriptor._internal_create_key,
  fields=[
    _descriptor.FieldDescriptor(
      name='minimum', full_name='StringStatistics.minimum', index=0,
      number=1, type=9, cpp_type=9, label=1,
      has_default_value=False, default_value=b"".decode('utf-8'),
      message_type=None, enum_type=None, containing_type=None,
      is_extension=False, extension_scope=None,
      serialized_options=None, file=DESCRIPTOR,  create_key=_descriptor._internal_create_key),
    _descriptor.FieldDescriptor(
      name='maximum', full_name='StringStatistics.maximum', index=1,
      number=2, type=9, cpp_type=9, label=1,
      has_default_value=False, default_value=b"".decode('utf-8'),
      message_type=None, enum_type=None, containing_type=None,
      is_extension=False, extension_scope=None,
      serialized_options=None, file=DESCRIPTOR,  create_key=_descriptor._internal_create_key),
    _descriptor.FieldDescriptor(
      name='sum', full_name='StringStatistics.sum', index=2,
      number=3, type=18, cpp_type=2, label=1,
      has_default_value=False, default_value=0,
      message_type=None, enum_type=None, containing_type=None,
      is_extension=False, extension_scope=None,
      serialized_options=None, file=DESCRIPTOR,  create_key=_descriptor._internal_create_key),
  ],
  extensions=[
  ],
  nested_types=[],
  enum_types=[
  ],
  serialized_options=None,
  is_extendable=False,
  syntax='proto2',
  extension_ranges=[],
  oneofs=[
  ],
  serialized_start=166,
  serialized_end=231,
)


_BUCKETSTATISTICS = _descriptor.Descriptor(
  name='BucketStatistics',
  full_name='BucketStatistics',
  filename=None,
  file=DESCRIPTOR,
  containing_type=None,
  create_key=_descriptor._internal_create_key,
  fields=[
    _descriptor.FieldDescriptor(
      name='count', full_name='BucketStatistics.count', index=0,
      number=1, type=4, cpp_type=4, label=3,
      has_default_value=False, default_value=[],
      message_type=None, enum_type=None, containing_type=None,
      is_extension=False, extension_scope=None,
      serialized_options=b'\020\001', file=DESCRIPTOR,  create_key=_descriptor._internal_create_key),
  ],
  extensions=[
  ],
  nested_types=[],
  enum_types=[
  ],
  serialized_options=None,
  is_extendable=False,
  syntax='proto2',
  extension_ranges=[],
  oneofs=[
  ],
  serialized_start=233,
  serialized_end=270,
)


_DECIMALSTATISTICS = _descriptor.Descriptor(
  name='DecimalStatistics',
  full_name='DecimalStatistics',
  filename=None,
  file=DESCRIPTOR,
  containing_type=None,
  create_key=_descriptor._internal_create_key,
  fields=[
    _descriptor.FieldDescriptor(
      name='minimum', full_name='DecimalStatistics.minimum', index=0,
      number=1, type=9, cpp_type=9, label=1,
      has_default_value=False, default_value=b"".decode('utf-8'),
      message_type=None, enum_type=None, containing_type=None,
      is_extension=False, extension_scope=None,
      serialized_options=None, file=DESCRIPTOR,  create_key=_descriptor._internal_create_key),
    _descriptor.FieldDescriptor(
      name='maximum', full_name='DecimalStatistics.maximum', index=1,
      number=2, type=9, cpp_type=9, label=1,
      has_default_value=False, default_value=b"".decode('utf-8'),
      message_type=None, enum_type=None, containing_type=None,
      is_extension=False, extension_scope=None,
      serialized_options=None, file=DESCRIPTOR,  create_key=_descriptor._internal_create_key),
    _descriptor.FieldDescriptor(
      name='sum', full_name='DecimalStatistics.sum', index=2,
      number=3, type=9, cpp_type=9, label=1,
      has_default_value=False, default_value=b"".decode('utf-8'),
      message_type=None, enum_type=None, containing_type=None,
      is_extension=False, extension_scope=None,
      serialized_options=None, file=DESCRIPTOR,  create_key=_descriptor._internal_create_key),
  ],
  extensions=[
  ],
  nested_types=[],
  enum_types=[
  ],
  serialized_options=None,
  is_extendable=False,
  syntax='proto2',
  extension_ranges=[],
  oneofs=[
  ],
  serialized_start=272,
  serialized_end=338,
)


_DATESTATISTICS = _descriptor.Descriptor(
  name='DateStatistics',
  full_name='DateStatistics',
  filename=None,
  file=DESCRIPTOR,
  containing_type=None,
  create_key=_descriptor._internal_create_key,
  fields=[
    _descriptor.FieldDescriptor(
      name='minimum', full_name='DateStatistics.minimum', index=0,
      number=1, type=17, cpp_type=1, label=1,
      has_default_value=False, default_value=0,
      message_type=None, enum_type=None, containing_type=None,
      is_extension=False, extension_scope=None,
      serialized_options=None, file=DESCRIPTOR,  create_key=_descriptor._internal_create_key),
    _descriptor.FieldDescriptor(
      name='maximum', full_name='DateStatistics.maximum', index=1,
      number=2, type=17, cpp_type=1, label=1,
      has_default_value=False, default_value=0,
      message_type=None, enum_type=None, containing_type=None,
      is_extension=False, extension_scope=None,
      serialized_options=None, file=DESCRIPTOR,  create_key=_descriptor._internal_create_key),
  ],
  extensions=[
  ],
  nested_types=[],
  enum_types=[
  ],
  serialized_options=None,
  is_extendable=False,
  syntax='proto2',
  extension_ranges=[],
  oneofs=[
  ],
  serialized_start=340,
  serialized_end=390,
)


_TIMESTAMPSTATISTICS = _descriptor.Descriptor(
  name='TimestampStatistics',
  full_name='TimestampStatistics',
  filename=None,
  file=DESCRIPTOR,
  containing_type=None,
  create_key=_descriptor._internal_create_key,
  fields=[
    _descriptor.FieldDescriptor(
      name='minimum', full_name='TimestampStatistics.minimum', index=0,
      number=1, type=18, cpp_type=2, label=1,
      has_default_value=False, default_value=0,
      message_type=None, enum_type=None, containing_type=None,
      is_extension=False, extension_scope=None,
      serialized_options=None, file=DESCRIPTOR,  create_key=_descriptor._internal_create_key),
    _descriptor.FieldDescriptor(
      name='maximum', full_name='TimestampStatistics.maximum', index=1,
      number=2, type=18, cpp_type=2, label=1,
      has_default_value=False, default_value=0,
      message_type=None, enum_type=None, containing_type=None,
      is_extension=False, extension_scope=None,
      serialized_options=None, file=DESCRIPTOR,  create_key=_descriptor._internal_create_key),
    _descriptor.FieldDescriptor(
      name='minimumUtc', full_name='TimestampStatistics.minimumUtc', index=2,
      number=3, type=18, cpp_type=2, label=1,
      has_default_value=False, default_value=0,
      message_type=None, enum_type=None, containing_type=None,
      is_extension=False, extension_scope=None,
      serialized_options=None, file=DESCRIPTOR,  create_key=_descriptor._internal_create_key),
    _descriptor.FieldDescriptor(
      name='maximumUtc', full_name='TimestampStatistics.maximumUtc', index=3,
      number=4, type=18, cpp_type=2, label=1,
      has_default_value=False, default_value=0,
      message_type=None, enum_type=None, containing_type=None,
      is_extension=False, extension_scope=None,
      serialized_options=None, file=DESCRIPTOR,  create_key=_descriptor._internal_create_key),
  ],
  extensions=[
  ],
  nested_types=[],
  enum_types=[
  ],
  serialized_options=None,
  is_extendable=False,
  syntax='proto2',
  extension_ranges=[],
  oneofs=[
  ],
  serialized_start=392,
  serialized_end=487,
)


_BINARYSTATISTICS = _descriptor.Descriptor(
  name='BinaryStatistics',
  full_name='BinaryStatistics',
  filename=None,
  file=DESCRIPTOR,
  containing_type=None,
  create_key=_descriptor._internal_create_key,
  fields=[
    _descriptor.FieldDescriptor(
      name='sum', full_name='BinaryStatistics.sum', index=0,
      number=1, type=18, cpp_type=2, label=1,
      has_default_value=False, default_value=0,
      message_type=None, enum_type=None, containing_type=None,
      is_extension=False, extension_scope=None,
      serialized_options=None, file=DESCRIPTOR,  create_key=_descriptor._internal_create_key),
  ],
  extensions=[
  ],
  nested_types=[],
  enum_types=[
  ],
  serialized_options=None,
  is_extendable=False,
  syntax='proto2',
  extension_ranges=[],
  oneofs=[
  ],
  serialized_start=489,
  serialized_end=520,
)


_COLUMNSTATISTICS = _descriptor.Descriptor(
  name='ColumnStatistics',
  full_name='ColumnStatistics',
  filename=None,
  file=DESCRIPTOR,
  containing_type=None,
  create_key=_descriptor._internal_create_key,
  fields=[
    _descriptor.FieldDescriptor(
      name='numberOfValues', full_name='ColumnStatistics.numberOfValues', index=0,
      number=1, type=4, cpp_type=4, label=1,
      has_default_value=False, default_value=0,
      message_type=None, enum_type=None, containing_type=None,
      is_extension=False, extension_scope=None,
      serialized_options=None, file=DESCRIPTOR,  create_key=_descriptor._internal_create_key),
    _descriptor.FieldDescriptor(
      name='intStatistics', full_name='ColumnStatistics.intStatistics', index=1,
      number=2, type=11, cpp_type=10, label=1,
      has_default_value=False, default_value=None,
      message_type=None, enum_type=None, containing_type=None,
      is_extension=False, extension_scope=None,
      serialized_options=None, file=DESCRIPTOR,  create_key=_descriptor._internal_create_key),
    _descriptor.FieldDescriptor(
      name='doubleStatistics', full_name='ColumnStatistics.doubleStatistics', index=2,
      number=3, type=11, cpp_type=10, label=1,
      has_default_value=False, default_value=None,
      message_type=None, enum_type=None, containing_type=None,
      is_extension=False, extension_scope=None,
      serialized_options=None, file=DESCRIPTOR,  create_key=_descriptor._internal_create_key),
    _descriptor.FieldDescriptor(
      name='stringStatistics', full_name='ColumnStatistics.stringStatistics', index=3,
      number=4, type=11, cpp_type=10, label=1,
      has_default_value=False, default_value=None,
      message_type=None, enum_type=None, containing_type=None,
      is_extension=False, extension_scope=None,
      serialized_options=None, file=DESCRIPTOR,  create_key=_descriptor._internal_create_key),
    _descriptor.FieldDescriptor(
      name='bucketStatistics', full_name='ColumnStatistics.bucketStatistics', index=4,
      number=5, type=11, cpp_type=10, label=1,
      has_default_value=False, default_value=None,
      message_type=None, enum_type=None, containing_type=None,
      is_extension=False, extension_scope=None,
      serialized_options=None, file=DESCRIPTOR,  create_key=_descriptor._internal_create_key),
    _descriptor.FieldDescriptor(
      name='decimalStatistics', full_name='ColumnStatistics.decimalStatistics', index=5,
      number=6, type=11, cpp_type=10, label=1,
      has_default_value=False, default_value=None,
      message_type=None, enum_type=None, containing_type=None,
      is_extension=False, extension_scope=None,
      serialized_options=None, file=DESCRIPTOR,  create_key=_descriptor._internal_create_key),
    _descriptor.FieldDescriptor(
      name='dateStatistics', full_name='ColumnStatistics.dateStatistics', index=6,
      number=7, type=11, cpp_type=10, label=1,
      has_default_value=False, default_value=None,
      message_type=None, enum_type=None, containing_type=None,
      is_extension=False, extension_scope=None,
      serialized_options=None, file=DESCRIPTOR,  create_key=_descriptor._internal_create_key),
    _descriptor.FieldDescriptor(
      name='binaryStatistics', full_name='ColumnStatistics.binaryStatistics', index=7,
      number=8, type=11, cpp_type=10, label=1,
      has_default_value=False, default_value=None,
      message_type=None, enum_type=None, containing_type=None,
      is_extension=False, extension_scope=None,
      serialized_options=None, file=DESCRIPTOR,  create_key=_descriptor._internal_create_key),
    _descriptor.FieldDescriptor(
      name='timestampStatistics', full_name='ColumnStatistics.timestampStatistics', index=8,
      number=9, type=11, cpp_type=10, label=1,
      has_default_value=False, default_value=None,
      message_type=None, enum_type=None, containing_type=None,
      is_extension=False, extension_scope=None,
      serialized_options=None, file=DESCRIPTOR,  create_key=_descriptor._internal_create_key),
    _descriptor.FieldDescriptor(
      name='hasNull', full_name='ColumnStatistics.hasNull', index=9,
      number=10, type=8, cpp_type=7, label=1,
      has_default_value=False, default_value=False,
      message_type=None, enum_type=None, containing_type=None,
      is_extension=False, extension_scope=None,
      serialized_options=None, file=DESCRIPTOR,  create_key=_descriptor._internal_create_key),
  ],
  extensions=[
  ],
  nested_types=[],
  enum_types=[
  ],
  serialized_options=None,
  is_extendable=False,
  syntax='proto2',
  extension_ranges=[],
  oneofs=[
  ],
  serialized_start=523,
  serialized_end=944,
)

_COLUMNSTATISTICS.fields_by_name['intStatistics'].message_type = _INTEGERSTATISTICS
_COLUMNSTATISTICS.fields_by_name['doubleStatistics'].message_type = _DOUBLESTATISTICS
_COLUMNSTATISTICS.fields_by_name['stringStatistics'].message_type = _STRINGSTATISTICS
_COLUMNSTATISTICS.fields_by_name['bucketStatistics'].message_type = _BUCKETSTATISTICS
_COLUMNSTATISTICS.fields_by_name['decimalStatistics'].message_type = _DECIMALSTATISTICS
_COLUMNSTATISTICS.fields_by_name['dateStatistics'].message_type = _DATESTATISTICS
_COLUMNSTATISTICS.fields_by_name['binaryStatistics'].message_type = _BINARYSTATISTICS
_COLUMNSTATISTICS.fields_by_name['timestampStatistics'].message_type = _TIMESTAMPSTATISTICS
DESCRIPTOR.message_types_by_name['IntegerStatistics'] = _INTEGERSTATISTICS
DESCRIPTOR.message_types_by_name['DoubleStatistics'] = _DOUBLESTATISTICS
DESCRIPTOR.message_types_by_name['StringStatistics'] = _STRINGSTATISTICS
DESCRIPTOR.message_types_by_name['BucketStatistics'] = _BUCKETSTATISTICS
DESCRIPTOR.message_types_by_name['DecimalStatistics'] = _DECIMALSTATISTICS
DESCRIPTOR.message_types_by_name['DateStatistics'] = _DATESTATISTICS
DESCRIPTOR.message_types_by_name['TimestampStatistics'] = _TIMESTAMPSTATISTICS
DESCRIPTOR.message_types_by_name['BinaryStatistics'] = _BINARYSTATISTICS
DESCRIPTOR.message_types_by_name['ColumnStatistics'] = _COLUMNSTATISTICS
_sym_db.RegisterFileDescriptor(DESCRIPTOR)

IntegerStatistics = _reflection.GeneratedProtocolMessageType('IntegerStatistics', (_message.Message,), {
  'DESCRIPTOR' : _INTEGERSTATISTICS,
  '__module__' : 'orc_column_statistics_pb2'
  # @@protoc_insertion_point(class_scope:IntegerStatistics)
  })
_sym_db.RegisterMessage(IntegerStatistics)

DoubleStatistics = _reflection.GeneratedProtocolMessageType('DoubleStatistics', (_message.Message,), {
  'DESCRIPTOR' : _DOUBLESTATISTICS,
  '__module__' : 'orc_column_statistics_pb2'
  # @@protoc_insertion_point(class_scope:DoubleStatistics)
  })
_sym_db.RegisterMessage(DoubleStatistics)

StringStatistics = _reflection.GeneratedProtocolMessageType('StringStatistics', (_message.Message,), {
  'DESCRIPTOR' : _STRINGSTATISTICS,
  '__module__' : 'orc_column_statistics_pb2'
  # @@protoc_insertion_point(class_scope:StringStatistics)
  })
_sym_db.RegisterMessage(StringStatistics)

BucketStatistics = _reflection.GeneratedProtocolMessageType('BucketStatistics', (_message.Message,), {
  'DESCRIPTOR' : _BUCKETSTATISTICS,
  '__module__' : 'orc_column_statistics_pb2'
  # @@protoc_insertion_point(class_scope:BucketStatistics)
  })
_sym_db.RegisterMessage(BucketStatistics)

DecimalStatistics = _reflection.GeneratedProtocolMessageType('DecimalStatistics', (_message.Message,), {
  'DESCRIPTOR' : _DECIMALSTATISTICS,
  '__module__' : 'orc_column_statistics_pb2'
  # @@protoc_insertion_point(class_scope:DecimalStatistics)
  })
_sym_db.RegisterMessage(DecimalStatistics)

DateStatistics = _reflection.GeneratedProtocolMessageType('DateStatistics', (_message.Message,), {
  'DESCRIPTOR' : _DATESTATISTICS,
  '__module__' : 'orc_column_statistics_pb2'
  # @@protoc_insertion_point(class_scope:DateStatistics)
  })
_sym_db.RegisterMessage(DateStatistics)

TimestampStatistics = _reflection.GeneratedProtocolMessageType('TimestampStatistics', (_message.Message,), {
  'DESCRIPTOR' : _TIMESTAMPSTATISTICS,
  '__module__' : 'orc_column_statistics_pb2'
  # @@protoc_insertion_point(class_scope:TimestampStatistics)
  })
_sym_db.RegisterMessage(TimestampStatistics)

BinaryStatistics = _reflection.GeneratedProtocolMessageType('BinaryStatistics', (_message.Message,), {
  'DESCRIPTOR' : _BINARYSTATISTICS,
  '__module__' : 'orc_column_statistics_pb2'
  # @@protoc_insertion_point(class_scope:BinaryStatistics)
  })
_sym_db.RegisterMessage(BinaryStatistics)

ColumnStatistics = _reflection.GeneratedProtocolMessageType('ColumnStatistics', (_message.Message,), {
  'DESCRIPTOR' : _COLUMNSTATISTICS,
  '__module__' : 'orc_column_statistics_pb2'
  # @@protoc_insertion_point(class_scope:ColumnStatistics)
  })
_sym_db.RegisterMessage(ColumnStatistics)


_BUCKETSTATISTICS.fields_by_name['count']._options = None
# @@protoc_insertion_point(module_scope)
# fmt: on
