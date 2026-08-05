// This is a generated file - do not edit.
//
// Generated from public_api_v4.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class AcceleratorPolicy extends $pb.ProtobufEnum {
  static const AcceleratorPolicy ACCELERATOR_POLICY_UNSPECIFIED =
      AcceleratorPolicy._(
          0, _omitEnumNames ? '' : 'ACCELERATOR_POLICY_UNSPECIFIED');
  static const AcceleratorPolicy ACCELERATOR_POLICY_AUTO =
      AcceleratorPolicy._(1, _omitEnumNames ? '' : 'ACCELERATOR_POLICY_AUTO');
  static const AcceleratorPolicy ACCELERATOR_POLICY_CPU =
      AcceleratorPolicy._(2, _omitEnumNames ? '' : 'ACCELERATOR_POLICY_CPU');
  static const AcceleratorPolicy ACCELERATOR_POLICY_GPU =
      AcceleratorPolicy._(3, _omitEnumNames ? '' : 'ACCELERATOR_POLICY_GPU');
  static const AcceleratorPolicy ACCELERATOR_POLICY_NPU =
      AcceleratorPolicy._(4, _omitEnumNames ? '' : 'ACCELERATOR_POLICY_NPU');

  static const $core.List<AcceleratorPolicy> values = <AcceleratorPolicy>[
    ACCELERATOR_POLICY_UNSPECIFIED,
    ACCELERATOR_POLICY_AUTO,
    ACCELERATOR_POLICY_CPU,
    ACCELERATOR_POLICY_GPU,
    ACCELERATOR_POLICY_NPU,
  ];

  static final $core.List<AcceleratorPolicy?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static AcceleratorPolicy? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const AcceleratorPolicy._(super.value, super.name);
}

class StructuredEnforcementMode extends $pb.ProtobufEnum {
  static const StructuredEnforcementMode
      STRUCTURED_ENFORCEMENT_MODE_UNSPECIFIED = StructuredEnforcementMode._(
          0, _omitEnumNames ? '' : 'STRUCTURED_ENFORCEMENT_MODE_UNSPECIFIED');
  static const StructuredEnforcementMode
      STRUCTURED_ENFORCEMENT_MODE_CONSTRAINED = StructuredEnforcementMode._(
          1, _omitEnumNames ? '' : 'STRUCTURED_ENFORCEMENT_MODE_CONSTRAINED');
  static const StructuredEnforcementMode
      STRUCTURED_ENFORCEMENT_MODE_VALIDATION_ONLY = StructuredEnforcementMode._(
          2,
          _omitEnumNames ? '' : 'STRUCTURED_ENFORCEMENT_MODE_VALIDATION_ONLY');
  static const StructuredEnforcementMode STRUCTURED_ENFORCEMENT_MODE_REPAIR =
      StructuredEnforcementMode._(
          3, _omitEnumNames ? '' : 'STRUCTURED_ENFORCEMENT_MODE_REPAIR');

  static const $core.List<StructuredEnforcementMode> values =
      <StructuredEnforcementMode>[
    STRUCTURED_ENFORCEMENT_MODE_UNSPECIFIED,
    STRUCTURED_ENFORCEMENT_MODE_CONSTRAINED,
    STRUCTURED_ENFORCEMENT_MODE_VALIDATION_ONLY,
    STRUCTURED_ENFORCEMENT_MODE_REPAIR,
  ];

  static final $core.List<StructuredEnforcementMode?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static StructuredEnforcementMode? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const StructuredEnforcementMode._(super.value, super.name);
}

class PublicGenerationEventKind extends $pb.ProtobufEnum {
  static const PublicGenerationEventKind
      PUBLIC_GENERATION_EVENT_KIND_UNSPECIFIED = PublicGenerationEventKind._(
          0, _omitEnumNames ? '' : 'PUBLIC_GENERATION_EVENT_KIND_UNSPECIFIED');
  static const PublicGenerationEventKind PUBLIC_GENERATION_EVENT_KIND_STARTED =
      PublicGenerationEventKind._(
          1, _omitEnumNames ? '' : 'PUBLIC_GENERATION_EVENT_KIND_STARTED');
  static const PublicGenerationEventKind
      PUBLIC_GENERATION_EVENT_KIND_OUTPUT_ITEM_ADDED =
      PublicGenerationEventKind._(
          2,
          _omitEnumNames
              ? ''
              : 'PUBLIC_GENERATION_EVENT_KIND_OUTPUT_ITEM_ADDED');
  static const PublicGenerationEventKind
      PUBLIC_GENERATION_EVENT_KIND_TEXT_DELTA = PublicGenerationEventKind._(
          3, _omitEnumNames ? '' : 'PUBLIC_GENERATION_EVENT_KIND_TEXT_DELTA');
  static const PublicGenerationEventKind
      PUBLIC_GENERATION_EVENT_KIND_REASONING_DELTA =
      PublicGenerationEventKind._(4,
          _omitEnumNames ? '' : 'PUBLIC_GENERATION_EVENT_KIND_REASONING_DELTA');
  static const PublicGenerationEventKind
      PUBLIC_GENERATION_EVENT_KIND_TOOL_CALL_ADDED =
      PublicGenerationEventKind._(5,
          _omitEnumNames ? '' : 'PUBLIC_GENERATION_EVENT_KIND_TOOL_CALL_ADDED');
  static const PublicGenerationEventKind
      PUBLIC_GENERATION_EVENT_KIND_TOOL_ARGUMENTS_DELTA =
      PublicGenerationEventKind._(
          6,
          _omitEnumNames
              ? ''
              : 'PUBLIC_GENERATION_EVENT_KIND_TOOL_ARGUMENTS_DELTA');
  static const PublicGenerationEventKind
      PUBLIC_GENERATION_EVENT_KIND_TOOL_ARGUMENTS_DONE =
      PublicGenerationEventKind._(
          7,
          _omitEnumNames
              ? ''
              : 'PUBLIC_GENERATION_EVENT_KIND_TOOL_ARGUMENTS_DONE');
  static const PublicGenerationEventKind PUBLIC_GENERATION_EVENT_KIND_USAGE =
      PublicGenerationEventKind._(
          8, _omitEnumNames ? '' : 'PUBLIC_GENERATION_EVENT_KIND_USAGE');
  static const PublicGenerationEventKind
      PUBLIC_GENERATION_EVENT_KIND_COMPLETED = PublicGenerationEventKind._(
          9, _omitEnumNames ? '' : 'PUBLIC_GENERATION_EVENT_KIND_COMPLETED');
  static const PublicGenerationEventKind PUBLIC_GENERATION_EVENT_KIND_FAILED =
      PublicGenerationEventKind._(
          10, _omitEnumNames ? '' : 'PUBLIC_GENERATION_EVENT_KIND_FAILED');
  static const PublicGenerationEventKind
      PUBLIC_GENERATION_EVENT_KIND_CANCELLED = PublicGenerationEventKind._(
          11, _omitEnumNames ? '' : 'PUBLIC_GENERATION_EVENT_KIND_CANCELLED');

  static const $core.List<PublicGenerationEventKind> values =
      <PublicGenerationEventKind>[
    PUBLIC_GENERATION_EVENT_KIND_UNSPECIFIED,
    PUBLIC_GENERATION_EVENT_KIND_STARTED,
    PUBLIC_GENERATION_EVENT_KIND_OUTPUT_ITEM_ADDED,
    PUBLIC_GENERATION_EVENT_KIND_TEXT_DELTA,
    PUBLIC_GENERATION_EVENT_KIND_REASONING_DELTA,
    PUBLIC_GENERATION_EVENT_KIND_TOOL_CALL_ADDED,
    PUBLIC_GENERATION_EVENT_KIND_TOOL_ARGUMENTS_DELTA,
    PUBLIC_GENERATION_EVENT_KIND_TOOL_ARGUMENTS_DONE,
    PUBLIC_GENERATION_EVENT_KIND_USAGE,
    PUBLIC_GENERATION_EVENT_KIND_COMPLETED,
    PUBLIC_GENERATION_EVENT_KIND_FAILED,
    PUBLIC_GENERATION_EVENT_KIND_CANCELLED,
  ];

  static final $core.List<PublicGenerationEventKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 11);
  static PublicGenerationEventKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const PublicGenerationEventKind._(super.value, super.name);
}

class PublicDownloadEventKind extends $pb.ProtobufEnum {
  static const PublicDownloadEventKind PUBLIC_DOWNLOAD_EVENT_KIND_UNSPECIFIED =
      PublicDownloadEventKind._(
          0, _omitEnumNames ? '' : 'PUBLIC_DOWNLOAD_EVENT_KIND_UNSPECIFIED');
  static const PublicDownloadEventKind PUBLIC_DOWNLOAD_EVENT_KIND_STARTED =
      PublicDownloadEventKind._(
          1, _omitEnumNames ? '' : 'PUBLIC_DOWNLOAD_EVENT_KIND_STARTED');
  static const PublicDownloadEventKind PUBLIC_DOWNLOAD_EVENT_KIND_PROGRESS =
      PublicDownloadEventKind._(
          2, _omitEnumNames ? '' : 'PUBLIC_DOWNLOAD_EVENT_KIND_PROGRESS');
  static const PublicDownloadEventKind PUBLIC_DOWNLOAD_EVENT_KIND_VERIFYING =
      PublicDownloadEventKind._(
          3, _omitEnumNames ? '' : 'PUBLIC_DOWNLOAD_EVENT_KIND_VERIFYING');
  static const PublicDownloadEventKind PUBLIC_DOWNLOAD_EVENT_KIND_EXTRACTING =
      PublicDownloadEventKind._(
          4, _omitEnumNames ? '' : 'PUBLIC_DOWNLOAD_EVENT_KIND_EXTRACTING');
  static const PublicDownloadEventKind PUBLIC_DOWNLOAD_EVENT_KIND_COMPLETED =
      PublicDownloadEventKind._(
          5, _omitEnumNames ? '' : 'PUBLIC_DOWNLOAD_EVENT_KIND_COMPLETED');
  static const PublicDownloadEventKind PUBLIC_DOWNLOAD_EVENT_KIND_FAILED =
      PublicDownloadEventKind._(
          6, _omitEnumNames ? '' : 'PUBLIC_DOWNLOAD_EVENT_KIND_FAILED');
  static const PublicDownloadEventKind PUBLIC_DOWNLOAD_EVENT_KIND_CANCELLED =
      PublicDownloadEventKind._(
          7, _omitEnumNames ? '' : 'PUBLIC_DOWNLOAD_EVENT_KIND_CANCELLED');

  static const $core.List<PublicDownloadEventKind> values =
      <PublicDownloadEventKind>[
    PUBLIC_DOWNLOAD_EVENT_KIND_UNSPECIFIED,
    PUBLIC_DOWNLOAD_EVENT_KIND_STARTED,
    PUBLIC_DOWNLOAD_EVENT_KIND_PROGRESS,
    PUBLIC_DOWNLOAD_EVENT_KIND_VERIFYING,
    PUBLIC_DOWNLOAD_EVENT_KIND_EXTRACTING,
    PUBLIC_DOWNLOAD_EVENT_KIND_COMPLETED,
    PUBLIC_DOWNLOAD_EVENT_KIND_FAILED,
    PUBLIC_DOWNLOAD_EVENT_KIND_CANCELLED,
  ];

  static final $core.List<PublicDownloadEventKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 7);
  static PublicDownloadEventKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const PublicDownloadEventKind._(super.value, super.name);
}

class PublicTranscriptionEventKind extends $pb.ProtobufEnum {
  static const PublicTranscriptionEventKind
      PUBLIC_TRANSCRIPTION_EVENT_KIND_UNSPECIFIED =
      PublicTranscriptionEventKind._(0,
          _omitEnumNames ? '' : 'PUBLIC_TRANSCRIPTION_EVENT_KIND_UNSPECIFIED');
  static const PublicTranscriptionEventKind
      PUBLIC_TRANSCRIPTION_EVENT_KIND_STARTED = PublicTranscriptionEventKind._(
          1, _omitEnumNames ? '' : 'PUBLIC_TRANSCRIPTION_EVENT_KIND_STARTED');
  static const PublicTranscriptionEventKind
      PUBLIC_TRANSCRIPTION_EVENT_KIND_SPEECH_STARTED =
      PublicTranscriptionEventKind._(
          2,
          _omitEnumNames
              ? ''
              : 'PUBLIC_TRANSCRIPTION_EVENT_KIND_SPEECH_STARTED');
  static const PublicTranscriptionEventKind
      PUBLIC_TRANSCRIPTION_EVENT_KIND_PARTIAL = PublicTranscriptionEventKind._(
          3, _omitEnumNames ? '' : 'PUBLIC_TRANSCRIPTION_EVENT_KIND_PARTIAL');
  static const PublicTranscriptionEventKind
      PUBLIC_TRANSCRIPTION_EVENT_KIND_TRANSCRIPT_FINAL =
      PublicTranscriptionEventKind._(
          4,
          _omitEnumNames
              ? ''
              : 'PUBLIC_TRANSCRIPTION_EVENT_KIND_TRANSCRIPT_FINAL');
  static const PublicTranscriptionEventKind
      PUBLIC_TRANSCRIPTION_EVENT_KIND_SPEECH_ENDED =
      PublicTranscriptionEventKind._(5,
          _omitEnumNames ? '' : 'PUBLIC_TRANSCRIPTION_EVENT_KIND_SPEECH_ENDED');
  static const PublicTranscriptionEventKind
      PUBLIC_TRANSCRIPTION_EVENT_KIND_USAGE = PublicTranscriptionEventKind._(
          6, _omitEnumNames ? '' : 'PUBLIC_TRANSCRIPTION_EVENT_KIND_USAGE');
  static const PublicTranscriptionEventKind
      PUBLIC_TRANSCRIPTION_EVENT_KIND_COMPLETED =
      PublicTranscriptionEventKind._(
          7, _omitEnumNames ? '' : 'PUBLIC_TRANSCRIPTION_EVENT_KIND_COMPLETED');
  static const PublicTranscriptionEventKind
      PUBLIC_TRANSCRIPTION_EVENT_KIND_FAILED = PublicTranscriptionEventKind._(
          8, _omitEnumNames ? '' : 'PUBLIC_TRANSCRIPTION_EVENT_KIND_FAILED');
  static const PublicTranscriptionEventKind
      PUBLIC_TRANSCRIPTION_EVENT_KIND_CANCELLED =
      PublicTranscriptionEventKind._(
          9, _omitEnumNames ? '' : 'PUBLIC_TRANSCRIPTION_EVENT_KIND_CANCELLED');

  static const $core.List<PublicTranscriptionEventKind> values =
      <PublicTranscriptionEventKind>[
    PUBLIC_TRANSCRIPTION_EVENT_KIND_UNSPECIFIED,
    PUBLIC_TRANSCRIPTION_EVENT_KIND_STARTED,
    PUBLIC_TRANSCRIPTION_EVENT_KIND_SPEECH_STARTED,
    PUBLIC_TRANSCRIPTION_EVENT_KIND_PARTIAL,
    PUBLIC_TRANSCRIPTION_EVENT_KIND_TRANSCRIPT_FINAL,
    PUBLIC_TRANSCRIPTION_EVENT_KIND_SPEECH_ENDED,
    PUBLIC_TRANSCRIPTION_EVENT_KIND_USAGE,
    PUBLIC_TRANSCRIPTION_EVENT_KIND_COMPLETED,
    PUBLIC_TRANSCRIPTION_EVENT_KIND_FAILED,
    PUBLIC_TRANSCRIPTION_EVENT_KIND_CANCELLED,
  ];

  static final $core.List<PublicTranscriptionEventKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 9);
  static PublicTranscriptionEventKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const PublicTranscriptionEventKind._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
