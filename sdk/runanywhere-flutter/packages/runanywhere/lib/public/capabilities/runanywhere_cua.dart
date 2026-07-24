// SPDX-License-Identifier: Apache-2.0
//
// Computer-Use-Agent (CUA) capability — a stateless, model-agnostic scaffold
// that turns a VLM into a drivable agent via a model *profile* (data describing
// prompt / output format / coordinate convention). Mirrors the Swift
// `CuaAction` value type + `RunAnywhere.CUA` facade (RunAnywhere+CUA.swift).
// Pair it with `RunAnywhere.vlm` for inference; the app owns screenshot
// capture, executing the action, and the agent loop.

import 'package:runanywhere/native/dart_bridge_cua.dart';

/// The action a CUA model wants to perform. Integer values mirror
/// `rac_cua_action_type_t` in commons (`rac_cua.h`).
enum CuaActionKind {
  unknown(0),
  leftClick(1),
  rightClick(2),
  doubleClick(3),
  tripleClick(4),
  mouseMove(5),
  leftClickDrag(6),
  type(7),
  key(8),
  scroll(9),
  hscroll(10),
  visitUrl(11),
  historyBack(12),
  webSearch(13),
  readPageAnswer(14),
  pauseMemorize(15),
  askUser(16),
  wait(17),
  terminate(18);

  const CuaActionKind(this.value);

  /// Wire value matching the C `rac_cua_action_type_t` enum.
  final int value;

  /// Map a C enum value onto a [CuaActionKind], defaulting to [unknown].
  static CuaActionKind fromValue(int value) {
    for (final kind in CuaActionKind.values) {
      if (kind.value == value) return kind;
    }
    return CuaActionKind.unknown;
  }
}

/// A computer-use-agent action parsed from a model's output, with coordinates
/// already scaled to the caller's viewport. Model-agnostic (see
/// [RunAnywhereCUA]). Mirrors the Swift `CuaAction` struct.
class CuaAction {
  const CuaAction({
    required this.kind,
    required this.coordinate,
    required this.text,
    required this.reasoning,
    required this.scrollPixels,
    required this.waitSeconds,
    required this.isValid,
  });

  /// The action the model wants to perform.
  final CuaActionKind kind;

  /// Viewport-scaled pixel coordinate (for click / move / drag), else null.
  final ({int x, int y})? coordinate;

  /// Primary string argument, interpreted by [kind]: type→text, visitUrl→url,
  /// webSearch→query, terminate→answer, askUser/readPageAnswer→question,
  /// pauseMemorize→fact, key→space-joined keys.
  final String text;

  /// Chain-of-thought the model emitted before the tool call, if any.
  final String reasoning;

  /// Scroll amount for scroll/hscroll (+up / -down).
  final int scrollPixels;

  /// Seconds to wait for [CuaActionKind.wait].
  final double waitSeconds;

  /// Whether a valid tool call was found.
  final bool isValid;
}

/// Computer-use-agent scaffold. Turns a VLM into a drivable agent using a model
/// *profile* (data describing prompt / output format / coordinate convention).
/// Fara1.5 ships built in; adding another CUA model is a new profile in
/// commons, not new API. Stateless — pair it with
/// `RunAnywhere.vlm.processImage` / `processImageStream` for inference; the app
/// owns screenshot capture, executing the action, and the agent loop.
///
/// Access via `RunAnywhere.cua`. Mirrors Swift `RunAnywhere.CUA`.
class RunAnywhereCUA {
  RunAnywhereCUA._();

  static final RunAnywhereCUA _instance = RunAnywhereCUA._();

  static RunAnywhereCUA get shared => _instance;

  /// Built-in profile for Microsoft Fara1.5 / Qwen3.5-VL `computer_use`
  /// (a fixed 1000x1000 coordinate space). Matches `RAC_CUA_PROFILE_FARA`.
  static const String faraProfile = 'fara';

  /// The system prompt (identity + `computer_use` tool schema) for a profile,
  /// rendered at a declared coordinate space (pass the profile's native space,
  /// e.g. 1000x1000 for Fara). Returns null for an unknown profile. Mirrors
  /// Swift `CUA.systemPrompt(profile:display:)`.
  String? systemPrompt({
    String profile = faraProfile,
    int displayWidth = 1000,
    int displayHeight = 1000,
  }) {
    return DartBridgeCua.shared.systemPrompt(
      profile,
      displayWidth,
      displayHeight,
    );
  }

  /// Parse a model's raw output into a [CuaAction], rescaling coordinates from
  /// the profile's model space to [viewportWidth] x [viewportHeight]. Returns
  /// null for an unknown profile; [CuaAction.isValid] is false when no tool
  /// call was found. Mirrors Swift `CUA.parseAction(_:profile:viewport:)`.
  CuaAction? parseAction(
    String modelOutput, {
    String profile = faraProfile,
    required int viewportWidth,
    required int viewportHeight,
  }) {
    return DartBridgeCua.shared.parseAction(
      profile,
      modelOutput,
      viewportWidth,
      viewportHeight,
    );
  }
}
