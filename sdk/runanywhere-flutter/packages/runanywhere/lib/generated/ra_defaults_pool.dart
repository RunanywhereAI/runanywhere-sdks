// SPDX-License-Identifier: Apache-2.0
//
// GENERATED FILE — DO NOT EDIT.
// Regenerate with: idl/codegen/generate_defaults_pool.py
//
// Values come from `(runanywhere.v1.rac_default)` annotations in
// idl/sdk_defaults.proto. That file is the single declaration of every default
// here; the C header and the other three SDK languages are generated from
// the same annotations, so editing this copy only desynchronizes one SDK.

/// Central default pool. Read these instead of retyping a literal.
library;

abstract final class RADefaultsNetwork {
  static const int requestTimeoutMs = 60000;
  static const int resourceTimeoutMs = 600000;
  static const int streamingTimeoutMs = 86400000;
  static const int adapterTimeoutMs = 30000;
  static const int connectTimeoutMs = 30000;
  static const int streamChunkBytes = 262144;
  static const int maxRetries = 3;
  static const int retryBackoffBaseMs = 100;
}

abstract final class RADefaultsAudioCapture {
  static const int micSampleRateHz = 16000;
  static const int micChannels = 1;
  static const int micChannelCapacity = 128;
  static const int micTapBufferFrames = 4096;
  static const int ttsSampleRateHz = 22050;
}

abstract final class RADefaultsVoiceAgent {
  static const int maxTokens = 96;
  static const double temperature = 0.0;
  static const String defaultVadModelId = "silero-vad";
  static const double speechRmsThreshold = 0.015;
  static const double speechFloorMultiplier = 2.0;
}

abstract final class RADefaultsHybrid {
  static const double sttConfidenceThreshold = 0.5;
}

abstract final class RADefaultsWorker {
  static const int handshakeTimeoutMs = 10000;
  static const int backendInitTimeoutMs = 120000;
}

abstract final class RADefaultsFFI {
  static const int pathBufferBytes = 1024;
}

abstract final class RADefaultsEnvironment {
  static const String productionBaseUrl = "https://api.runanywhere.ai";
  static const String developmentBaseUrl = "https://dev-api.runanywhere.ai";
  static const String developmentPlaceholderUrl = "https://dev.runanywhere.local";
}

abstract final class RADefaultsStructuredOutput {
  static const int maxTokens = 512;
  static const double temperature = 0.0;
}

abstract final class RADefaultsStorage {
  static const int contextLength = 2048;
}
