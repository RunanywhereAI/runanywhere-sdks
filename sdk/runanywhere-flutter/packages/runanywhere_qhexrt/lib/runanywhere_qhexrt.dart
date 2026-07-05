/// Private Qualcomm Hexagon NPU (QHexRT) backend for the RunAnywhere Flutter SDK.
///
/// Android/Snapdragon only — runs prebuilt QNN context binaries on Hexagon
/// v75+ NPUs (LLM/VLM/STT/TTS). A thin wrapper that registers the C++
/// engine and exposes a pre-flight NPU probe; all inference flows through the
/// core SDK. The probe returns the generated `runanywhere.v1.NpuCapability`
/// proto message.
///
/// ```dart
/// import 'package:runanywhere_qhexrt/runanywhere_qhexrt.dart';
///
/// final npu = QHexRT.probeNpu();
/// if (npu.qhexrtSupported) await QHexRT.register();
/// ```
library;

export 'qhexrt.dart';
