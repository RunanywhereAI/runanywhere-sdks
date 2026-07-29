// This is a generated file - do not edit.
//
// Generated from segmentation.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// Packed 8-bit pixel layouts accepted at the SDK boundary. Rows are tightly
/// packed; callers must not include per-row padding.
class SegmentationPixelFormat extends $pb.ProtobufEnum {
  static const SegmentationPixelFormat SEGMENTATION_PIXEL_FORMAT_UNSPECIFIED =
      SegmentationPixelFormat._(
          0, _omitEnumNames ? '' : 'SEGMENTATION_PIXEL_FORMAT_UNSPECIFIED');
  static const SegmentationPixelFormat SEGMENTATION_PIXEL_FORMAT_RGB8 =
      SegmentationPixelFormat._(
          1, _omitEnumNames ? '' : 'SEGMENTATION_PIXEL_FORMAT_RGB8');
  static const SegmentationPixelFormat SEGMENTATION_PIXEL_FORMAT_RGBA8 =
      SegmentationPixelFormat._(
          2, _omitEnumNames ? '' : 'SEGMENTATION_PIXEL_FORMAT_RGBA8');
  static const SegmentationPixelFormat SEGMENTATION_PIXEL_FORMAT_BGRA8 =
      SegmentationPixelFormat._(
          3, _omitEnumNames ? '' : 'SEGMENTATION_PIXEL_FORMAT_BGRA8');

  static const $core.List<SegmentationPixelFormat> values =
      <SegmentationPixelFormat>[
    SEGMENTATION_PIXEL_FORMAT_UNSPECIFIED,
    SEGMENTATION_PIXEL_FORMAT_RGB8,
    SEGMENTATION_PIXEL_FORMAT_RGBA8,
    SEGMENTATION_PIXEL_FORMAT_BGRA8,
  ];

  static final $core.List<SegmentationPixelFormat?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static SegmentationPixelFormat? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const SegmentationPixelFormat._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
