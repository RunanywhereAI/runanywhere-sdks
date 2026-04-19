// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import 'package:ffi/ffi.dart';

import '../src/ffi/bindings.dart';
import 'voice_session.dart';

/// Public entry point — mirror of RunAnywhere.swift / RunAnywhere.kt.
///
/// Usage:
/// ```dart
///   final session = RunAnywhere.solution(
///       SolutionConfig.voiceAgent(VoiceAgentConfig()));
///   await for (final e in session.run()) {
///     // ...
///   }
/// ```
class RunAnywhere {
  const RunAnywhere._();

  static VoiceSession solution(SolutionConfig config) =>
      VoiceSession.create(config);

  /// Dynamic plugin load — Android/macOS/Linux only. Returns true on
  /// success. No-op on iOS (static plugin mode) where this returns false.
  static bool loadPlugin(String libPath) {
    try {
      final b = RaCoreBindings.open();
      final cpath = libPath.toNativeUtf8();
      final rc = b.loadPluginRaw(cpath);
      calloc.free(cpath);
      return rc == raOk;
    } catch (_) {
      return false;
    }
  }

  /// Count of currently-registered engine plugins.
  static int get registeredPluginCount {
    try {
      return RaCoreBindings.open().pluginCountRaw();
    } catch (_) {
      return 0;
    }
  }
}

sealed class SolutionConfig {
  const SolutionConfig._();

  factory SolutionConfig.voiceAgent(VoiceAgentConfig config) =
      VoiceAgentSolution;
  factory SolutionConfig.rag(RAGConfig config) = RAGSolution;
  factory SolutionConfig.wakeWord(WakeWordConfig config) = WakeWordSolution;
}

class VoiceAgentSolution extends SolutionConfig {
  final VoiceAgentConfig config;
  const VoiceAgentSolution(this.config) : super._();
}

class RAGSolution extends SolutionConfig {
  final RAGConfig config;
  const RAGSolution(this.config) : super._();
}

class WakeWordSolution extends SolutionConfig {
  final WakeWordConfig config;
  const WakeWordSolution(this.config) : super._();
}

class VoiceAgentConfig {
  final String llm;
  final String stt;
  final String tts;
  final String vad;
  final int    sampleRateHz;
  final int    chunkMs;
  final bool   enableBargeIn;
  final bool   emitPartials;
  final bool   emitThoughts;
  final String systemPrompt;
  final int    maxContextTokens;
  final double temperature;

  const VoiceAgentConfig({
    this.llm             = 'qwen3-4b',
    this.stt             = 'whisper-base',
    this.tts             = 'kokoro',
    this.vad             = 'silero-v5',
    this.sampleRateHz    = 16000,
    this.chunkMs         = 20,
    this.enableBargeIn   = true,
    this.emitPartials    = true,
    this.emitThoughts    = false,
    this.systemPrompt    = '',
    this.maxContextTokens = 4096,
    this.temperature     = 0.7,
  });
}

class RAGConfig {
  final String embedModel;
  final String rerankModel;
  final String llm;
  final String vectorStorePath;
  final int    retrieveK;
  final int    rerankTop;

  const RAGConfig({
    this.embedModel      = 'bge-small-en-v1.5',
    this.rerankModel     = 'bge-reranker-v2-m3',
    this.llm             = 'qwen3-4b',
    this.vectorStorePath = '',
    this.retrieveK       = 24,
    this.rerankTop       = 6,
  });
}

class WakeWordConfig {
  final String model;
  final String keyword;
  final double threshold;
  final int    preRollMs;

  const WakeWordConfig({
    this.model     = 'kws-zipformer-gigaspeech',
    this.keyword   = 'hey mycroft',
    this.threshold = 0.5,
    this.preRollMs = 250,
  });
}
