// This is a generated file - do not edit.
//
// Generated from vlm_options.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class VLMModelFamily extends $pb.ProtobufEnum {
  static const VLMModelFamily VLM_MODEL_FAMILY_UNSPECIFIED =
      VLMModelFamily._(0, _omitEnumNames ? '' : 'VLM_MODEL_FAMILY_UNSPECIFIED');
  static const VLMModelFamily VLM_MODEL_FAMILY_AUTO =
      VLMModelFamily._(1, _omitEnumNames ? '' : 'VLM_MODEL_FAMILY_AUTO');
  static const VLMModelFamily VLM_MODEL_FAMILY_QWEN2_VL =
      VLMModelFamily._(2, _omitEnumNames ? '' : 'VLM_MODEL_FAMILY_QWEN2_VL');
  static const VLMModelFamily VLM_MODEL_FAMILY_SMOLVLM =
      VLMModelFamily._(3, _omitEnumNames ? '' : 'VLM_MODEL_FAMILY_SMOLVLM');
  static const VLMModelFamily VLM_MODEL_FAMILY_LLAVA =
      VLMModelFamily._(4, _omitEnumNames ? '' : 'VLM_MODEL_FAMILY_LLAVA');
  static const VLMModelFamily VLM_MODEL_FAMILY_CUSTOM =
      VLMModelFamily._(99, _omitEnumNames ? '' : 'VLM_MODEL_FAMILY_CUSTOM');

  static const $core.List<VLMModelFamily> values = <VLMModelFamily>[
    VLM_MODEL_FAMILY_UNSPECIFIED,
    VLM_MODEL_FAMILY_AUTO,
    VLM_MODEL_FAMILY_QWEN2_VL,
    VLM_MODEL_FAMILY_SMOLVLM,
    VLM_MODEL_FAMILY_LLAVA,
    VLM_MODEL_FAMILY_CUSTOM,
  ];

  static final $core.Map<$core.int, VLMModelFamily> _byValue =
      $pb.ProtobufEnum.initByValue(values);
  static VLMModelFamily? valueOf($core.int value) => _byValue[value];

  const VLMModelFamily._(super.value, super.name);
}

class VLMStreamEventKind extends $pb.ProtobufEnum {
  static const VLMStreamEventKind VLM_STREAM_EVENT_KIND_UNSPECIFIED =
      VLMStreamEventKind._(
          0, _omitEnumNames ? '' : 'VLM_STREAM_EVENT_KIND_UNSPECIFIED');
  static const VLMStreamEventKind VLM_STREAM_EVENT_KIND_STARTED =
      VLMStreamEventKind._(
          1, _omitEnumNames ? '' : 'VLM_STREAM_EVENT_KIND_STARTED');

  /// Emitted when the vision encoder finishes and decoding begins -- the
  /// cue for a UI to switch from "analysing image" to "writing". Emitted
  /// where the backend measures the encode boundary
  /// (VLMResult.image_encode_time_ms comes from the same measurement).
  static const VLMStreamEventKind VLM_STREAM_EVENT_KIND_IMAGE_ENCODED =
      VLMStreamEventKind._(
          2, _omitEnumNames ? '' : 'VLM_STREAM_EVENT_KIND_IMAGE_ENCODED');
  static const VLMStreamEventKind VLM_STREAM_EVENT_KIND_TOKEN =
      VLMStreamEventKind._(
          3, _omitEnumNames ? '' : 'VLM_STREAM_EVENT_KIND_TOKEN');
  static const VLMStreamEventKind VLM_STREAM_EVENT_KIND_COMPLETED =
      VLMStreamEventKind._(
          4, _omitEnumNames ? '' : 'VLM_STREAM_EVENT_KIND_COMPLETED');
  static const VLMStreamEventKind VLM_STREAM_EVENT_KIND_ERROR =
      VLMStreamEventKind._(
          5, _omitEnumNames ? '' : 'VLM_STREAM_EVENT_KIND_ERROR');

  static const $core.List<VLMStreamEventKind> values = <VLMStreamEventKind>[
    VLM_STREAM_EVENT_KIND_UNSPECIFIED,
    VLM_STREAM_EVENT_KIND_STARTED,
    VLM_STREAM_EVENT_KIND_IMAGE_ENCODED,
    VLM_STREAM_EVENT_KIND_TOKEN,
    VLM_STREAM_EVENT_KIND_COMPLETED,
    VLM_STREAM_EVENT_KIND_ERROR,
  ];

  static final $core.List<VLMStreamEventKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static VLMStreamEventKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const VLMStreamEventKind._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
