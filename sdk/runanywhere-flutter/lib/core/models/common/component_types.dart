/// SDK Component Types
/// Similar to Swift SDK's SDKComponent
enum SDKComponent {
  llm,
  stt,
  tts,
  vad,
  voiceAgent,
  wakeWord,
  speakerDiarization,
  vlm,
}

/// Component Initialization Parameters
/// Similar to Swift SDK's ComponentInitParameters
abstract class ComponentInitParameters {
  String get componentType;
}

