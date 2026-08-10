/// Private Qualcomm Hexagon NPU (QHexRT) backend for the RunAnywhere Flutter SDK.
///
/// Android/Snapdragon only — runs prebuilt QNN context binaries on Hexagon
/// V75/V79/V81 NPUs (LLM/VLM/STT/TTS). A thin wrapper that registers the C++
/// engine and exposes its capability probe; model registration and all
/// inference flow through the core SDK. The probe returns the generated
/// `runanywhere.v1.NpuCapability` proto message.
///
/// ```dart
/// import 'package:runanywhere/runanywhere.dart';
/// import 'package:runanywhere_qhexrt/runanywhere_qhexrt.dart';
///
/// final npu = QHexRT.probeNpu();
/// if (npu.supported) {
///   await QHexRT.register();
///   await RunAnywhere.models.register(
///     ModelRegistration.url(
///       id: 'my-qhexrt-model',
///       name: 'My QHexRT Model',
///       url: 'https://huggingface.co/organization/dedicated-qhexrt-model/resolve/main/model.json',
///       framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
///     ),
///   );
/// }
/// ```
library;

export 'qhexrt.dart';
