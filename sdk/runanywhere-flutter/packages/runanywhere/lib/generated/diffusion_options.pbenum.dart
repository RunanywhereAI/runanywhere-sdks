//
//  Generated code. Do not modify.
//  source: diffusion_options.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// ---------------------------------------------------------------------------
/// Generation mode. Sources pre-IDL (identical across all surfaces):
///   Swift   DiffusionTypes.swift:257    (textToImage / imageToImage / inpainting)
///   Kotlin  DiffusionTypes.kt:188       (TEXT_TO_IMAGE / IMAGE_TO_IMAGE / INPAINTING)
///   RN      DiffusionTypes.ts:73        (TextToImage / ImageToImage / Inpainting)
///   Web     DiffusionTypes.ts:23        (TextToImage / ImageToImage / Inpainting)
///   C ABI   rac_diffusion_types.h:59    (RAC_DIFFUSION_MODE_*)
/// ---------------------------------------------------------------------------
class DiffusionMode extends $pb.ProtobufEnum {
  static const DiffusionMode DIFFUSION_MODE_UNSPECIFIED = DiffusionMode._(0, _omitEnumNames ? '' : 'DIFFUSION_MODE_UNSPECIFIED');
  static const DiffusionMode DIFFUSION_MODE_TEXT_TO_IMAGE = DiffusionMode._(1, _omitEnumNames ? '' : 'DIFFUSION_MODE_TEXT_TO_IMAGE');
  static const DiffusionMode DIFFUSION_MODE_IMAGE_TO_IMAGE = DiffusionMode._(2, _omitEnumNames ? '' : 'DIFFUSION_MODE_IMAGE_TO_IMAGE');
  static const DiffusionMode DIFFUSION_MODE_INPAINTING = DiffusionMode._(3, _omitEnumNames ? '' : 'DIFFUSION_MODE_INPAINTING');

  static const $core.List<DiffusionMode> values = <DiffusionMode> [
    DIFFUSION_MODE_UNSPECIFIED,
    DIFFUSION_MODE_TEXT_TO_IMAGE,
    DIFFUSION_MODE_IMAGE_TO_IMAGE,
    DIFFUSION_MODE_INPAINTING,
  ];

  static final $core.Map<$core.int, DiffusionMode> _byValue = $pb.ProtobufEnum.initByValue(values);
  static DiffusionMode? valueOf($core.int value) => _byValue[value];

  const DiffusionMode._($core.int v, $core.String n) : super(v, n);
}

///  ---------------------------------------------------------------------------
///  Scheduler / sampler algorithm — *forward-looking union*.
///
///  Pre-IDL sources all expose the same eight cases (DPM++ 2M Karras, DPM++ 2M,
///  DPM++ 2M SDE, DDIM, Euler, Euler Ancestral, PNDM, LMS); see:
///    Swift   DiffusionTypes.swift:184    (.dpmPP2MKarras .. .lms)
///    Kotlin  DiffusionTypes.kt:155       (DPM_PP_2M_KARRAS .. LMS)
///    RN      DiffusionTypes.ts:48        (DPMPP2MKarras .. LMS)
///    Web     DiffusionTypes.ts:3         (numeric DPM_PP_2M_Karras .. LMS, matches C ABI)
///    C ABI   rac_diffusion_types.h:31    (RAC_DIFFUSION_SCHEDULER_*)
///
///  This proto enum extends that with two values that downstream backends are
///  expected to grow into but no SDK exposes yet:
///    - DDPM   — original Ho et al. 2020 sampler
///    - LCM    — Latent Consistency Model sampler (paired with the LCM model
///               variant; today Swift/Kotlin reuse DPM++ 2M Karras for LCM
///               models because no LCM scheduler case exists).
///  And it intentionally omits DPMPP_2M_SDE, which exists in every SDK today
///  but is being collapsed back into DPMPP_2M for the v1 IDL surface (the SDE
///  variant is purely an algorithmic toggle on DPM++ 2M; backends accept
///  either tag).
///
///  Drift reconciliation:
///    - Swift/Kotlin/RN/Web/C-ABI carriers of DPMPP_2M_SDE must round-trip
///      that case to DIFFUSION_SCHEDULER_DPMPP_2M (lossy in name, equivalent
///      in semantics — the SDE flag is a backend implementation detail).
///    - DDPM and LCM are *new* slots; SDKs that don't yet recognize them must
///      fall back to DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS (the recommended
///      default).
///  ---------------------------------------------------------------------------
class DiffusionScheduler extends $pb.ProtobufEnum {
  static const DiffusionScheduler DIFFUSION_SCHEDULER_UNSPECIFIED = DiffusionScheduler._(0, _omitEnumNames ? '' : 'DIFFUSION_SCHEDULER_UNSPECIFIED');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_DPMPP_2M = DiffusionScheduler._(1, _omitEnumNames ? '' : 'DIFFUSION_SCHEDULER_DPMPP_2M');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS = DiffusionScheduler._(2, _omitEnumNames ? '' : 'DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_DDIM = DiffusionScheduler._(3, _omitEnumNames ? '' : 'DIFFUSION_SCHEDULER_DDIM');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_DDPM = DiffusionScheduler._(4, _omitEnumNames ? '' : 'DIFFUSION_SCHEDULER_DDPM');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_EULER = DiffusionScheduler._(5, _omitEnumNames ? '' : 'DIFFUSION_SCHEDULER_EULER');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_EULER_A = DiffusionScheduler._(6, _omitEnumNames ? '' : 'DIFFUSION_SCHEDULER_EULER_A');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_PNDM = DiffusionScheduler._(7, _omitEnumNames ? '' : 'DIFFUSION_SCHEDULER_PNDM');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_LMS = DiffusionScheduler._(8, _omitEnumNames ? '' : 'DIFFUSION_SCHEDULER_LMS');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_LCM = DiffusionScheduler._(9, _omitEnumNames ? '' : 'DIFFUSION_SCHEDULER_LCM');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_DPMPP_2M_SDE = DiffusionScheduler._(10, _omitEnumNames ? '' : 'DIFFUSION_SCHEDULER_DPMPP_2M_SDE');

  static const $core.List<DiffusionScheduler> values = <DiffusionScheduler> [
    DIFFUSION_SCHEDULER_UNSPECIFIED,
    DIFFUSION_SCHEDULER_DPMPP_2M,
    DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS,
    DIFFUSION_SCHEDULER_DDIM,
    DIFFUSION_SCHEDULER_DDPM,
    DIFFUSION_SCHEDULER_EULER,
    DIFFUSION_SCHEDULER_EULER_A,
    DIFFUSION_SCHEDULER_PNDM,
    DIFFUSION_SCHEDULER_LMS,
    DIFFUSION_SCHEDULER_LCM,
    DIFFUSION_SCHEDULER_DPMPP_2M_SDE,
  ];

  static final $core.Map<$core.int, DiffusionScheduler> _byValue = $pb.ProtobufEnum.initByValue(values);
  static DiffusionScheduler? valueOf($core.int value) => _byValue[value];

  const DiffusionScheduler._($core.int v, $core.String n) : super(v, n);
}

/// ---------------------------------------------------------------------------
/// Stable Diffusion model variant. Sources pre-IDL (identical 6 cases):
///   Swift  DiffusionTypes.swift:92     (sd15 / sd21 / sdxl / sdxlTurbo / sdxs / lcm)
///   Kotlin DiffusionTypes.kt:85        (SD15 / SD21 / SDXL / SDXL_TURBO / SDXS / LCM)
///   RN     DiffusionTypes.ts:28        (SD15 / SD21 / SDXL / SDXLTurbo / SDXS / LCM)
///   Web    DiffusionTypes.ts:14        (numeric SD_1_5 / SD_2_1 / SDXL / SDXL_Turbo / SDXS / LCM)
///   C ABI  rac_diffusion_types.h:47    (RAC_DIFFUSION_MODEL_*)
/// ---------------------------------------------------------------------------
class DiffusionModelVariant extends $pb.ProtobufEnum {
  static const DiffusionModelVariant DIFFUSION_MODEL_VARIANT_UNSPECIFIED = DiffusionModelVariant._(0, _omitEnumNames ? '' : 'DIFFUSION_MODEL_VARIANT_UNSPECIFIED');
  static const DiffusionModelVariant DIFFUSION_MODEL_VARIANT_SD_1_5 = DiffusionModelVariant._(1, _omitEnumNames ? '' : 'DIFFUSION_MODEL_VARIANT_SD_1_5');
  static const DiffusionModelVariant DIFFUSION_MODEL_VARIANT_SD_2_1 = DiffusionModelVariant._(2, _omitEnumNames ? '' : 'DIFFUSION_MODEL_VARIANT_SD_2_1');
  static const DiffusionModelVariant DIFFUSION_MODEL_VARIANT_SDXL = DiffusionModelVariant._(3, _omitEnumNames ? '' : 'DIFFUSION_MODEL_VARIANT_SDXL');
  static const DiffusionModelVariant DIFFUSION_MODEL_VARIANT_SDXL_TURBO = DiffusionModelVariant._(4, _omitEnumNames ? '' : 'DIFFUSION_MODEL_VARIANT_SDXL_TURBO');
  static const DiffusionModelVariant DIFFUSION_MODEL_VARIANT_SDXS = DiffusionModelVariant._(5, _omitEnumNames ? '' : 'DIFFUSION_MODEL_VARIANT_SDXS');
  static const DiffusionModelVariant DIFFUSION_MODEL_VARIANT_LCM = DiffusionModelVariant._(6, _omitEnumNames ? '' : 'DIFFUSION_MODEL_VARIANT_LCM');

  static const $core.List<DiffusionModelVariant> values = <DiffusionModelVariant> [
    DIFFUSION_MODEL_VARIANT_UNSPECIFIED,
    DIFFUSION_MODEL_VARIANT_SD_1_5,
    DIFFUSION_MODEL_VARIANT_SD_2_1,
    DIFFUSION_MODEL_VARIANT_SDXL,
    DIFFUSION_MODEL_VARIANT_SDXL_TURBO,
    DIFFUSION_MODEL_VARIANT_SDXS,
    DIFFUSION_MODEL_VARIANT_LCM,
  ];

  static final $core.Map<$core.int, DiffusionModelVariant> _byValue = $pb.ProtobufEnum.initByValue(values);
  static DiffusionModelVariant? valueOf($core.int value) => _byValue[value];

  const DiffusionModelVariant._($core.int v, $core.String n) : super(v, n);
}

/// ---------------------------------------------------------------------------
/// Tokenizer source kind. Apple's compiled CoreML SD models do not bundle
/// vocab.json / merges.txt, so the tokenizer must be downloaded from a
/// HuggingFace repo (or a developer-supplied URL).
/// Sources pre-IDL:
///   Swift  DiffusionTypes.swift:18     (.sd15 / .sd2 / .sdxl / .custom(baseURL:))
///   Kotlin DiffusionTypes.kt:31        (Sd15 / Sd2 / Sdxl / Custom(customBaseUrl))
///   RN     DiffusionTypes.ts:17        ({kind:'sd15'|'sd2'|'sdxl'|'custom'} discriminated union)
///   Web    — n/a (the llamacpp Web package doesn't expose tokenizer source)
///   C ABI  rac_diffusion_types.h:79    (RAC_DIFFUSION_TOKENIZER_SD_1_5 / SD_2_X / SDXL / CUSTOM)
/// ---------------------------------------------------------------------------
class DiffusionTokenizerSourceKind extends $pb.ProtobufEnum {
  static const DiffusionTokenizerSourceKind DIFFUSION_TOKENIZER_SOURCE_KIND_UNSPECIFIED = DiffusionTokenizerSourceKind._(0, _omitEnumNames ? '' : 'DIFFUSION_TOKENIZER_SOURCE_KIND_UNSPECIFIED');
  static const DiffusionTokenizerSourceKind DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD15 = DiffusionTokenizerSourceKind._(1, _omitEnumNames ? '' : 'DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD15');
  static const DiffusionTokenizerSourceKind DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD2 = DiffusionTokenizerSourceKind._(2, _omitEnumNames ? '' : 'DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD2');
  static const DiffusionTokenizerSourceKind DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SDXL = DiffusionTokenizerSourceKind._(3, _omitEnumNames ? '' : 'DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SDXL');
  static const DiffusionTokenizerSourceKind DIFFUSION_TOKENIZER_SOURCE_KIND_CUSTOM = DiffusionTokenizerSourceKind._(4, _omitEnumNames ? '' : 'DIFFUSION_TOKENIZER_SOURCE_KIND_CUSTOM');

  static const $core.List<DiffusionTokenizerSourceKind> values = <DiffusionTokenizerSourceKind> [
    DIFFUSION_TOKENIZER_SOURCE_KIND_UNSPECIFIED,
    DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD15,
    DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD2,
    DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SDXL,
    DIFFUSION_TOKENIZER_SOURCE_KIND_CUSTOM,
  ];

  static final $core.Map<$core.int, DiffusionTokenizerSourceKind> _byValue = $pb.ProtobufEnum.initByValue(values);
  static DiffusionTokenizerSourceKind? valueOf($core.int value) => _byValue[value];

  const DiffusionTokenizerSourceKind._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
