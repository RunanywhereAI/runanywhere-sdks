/// LLM Thinking — Dart FFI facade over the rac_llm_thinking C ABI.
///
/// v3-readiness Phase A9 / GAP 08 #6. Cross-SDK parity with Swift's
/// `CppBridge+LLMThinking.swift` and Kotlin's `CppBridgeLlmThinking`.
/// Lets Flutter apps parse `<think>...</think>` blocks with byte-for-byte
/// the same semantics as the other SDKs.
///
/// C ABI source: `sdk/runanywhere-commons/include/rac/features/llm/rac_llm_thinking.h`.
library llm_thinking;

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart' show StringUtf8Pointer, Utf8, calloc;

import 'package:runanywhere/native/platform_loader.dart';

// =============================================================================
// FFI signatures
// =============================================================================

/// `rac_result_t rac_llm_extract_thinking(
///      const char* text,
///      const char** out_response,
///      size_t* out_response_len,
///      const char** out_thinking,
///      size_t* out_thinking_len);`
typedef _ExtractThinkingNative = ffi.Int32 Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Pointer<Utf8>>,
  ffi.Pointer<ffi.Size>,
  ffi.Pointer<ffi.Pointer<Utf8>>,
  ffi.Pointer<ffi.Size>,
);
typedef _ExtractThinkingDart = int Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Pointer<Utf8>>,
  ffi.Pointer<ffi.Size>,
  ffi.Pointer<ffi.Pointer<Utf8>>,
  ffi.Pointer<ffi.Size>,
);

/// `rac_result_t rac_llm_strip_thinking(
///      const char* text,
///      const char** out_stripped,
///      size_t* out_stripped_len);`
typedef _StripThinkingNative = ffi.Int32 Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Pointer<Utf8>>,
  ffi.Pointer<ffi.Size>,
);
typedef _StripThinkingDart = int Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Pointer<Utf8>>,
  ffi.Pointer<ffi.Size>,
);

/// `rac_result_t rac_llm_split_thinking_tokens(
///      int32_t total_completion_tokens,
///      const char* response_text,
///      const char* thinking_text,
///      int32_t* out_thinking_tokens,
///      int32_t* out_response_tokens);`
typedef _SplitTokensNative = ffi.Int32 Function(
  ffi.Int32,
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Int32>,
  ffi.Pointer<ffi.Int32>,
);
typedef _SplitTokensDart = int Function(
  int,
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Int32>,
  ffi.Pointer<ffi.Int32>,
);

// =============================================================================
// Lazy binding cache — resolved once per process
// =============================================================================

class _LlmThinkingBindings {
  _LlmThinkingBindings(ffi.DynamicLibrary lib)
      : rac_llm_extract_thinking = lib.lookupFunction<
            _ExtractThinkingNative, _ExtractThinkingDart>(
            'rac_llm_extract_thinking'),
        rac_llm_strip_thinking = lib.lookupFunction<
            _StripThinkingNative, _StripThinkingDart>('rac_llm_strip_thinking'),
        rac_llm_split_thinking_tokens = lib.lookupFunction<
            _SplitTokensNative, _SplitTokensDart>('rac_llm_split_thinking_tokens');

  // ignore: non_constant_identifier_names
  final _ExtractThinkingDart rac_llm_extract_thinking;
  // ignore: non_constant_identifier_names
  final _StripThinkingDart rac_llm_strip_thinking;
  // ignore: non_constant_identifier_names
  final _SplitTokensDart rac_llm_split_thinking_tokens;
}

_LlmThinkingBindings? _cached;
_LlmThinkingBindings _bindings() =>
    _cached ??= _LlmThinkingBindings(PlatformLoader.loadCommons());

// =============================================================================
// Public data types
// =============================================================================

/// Result of [LlmThinking.extract]: the visible response text plus the
/// optional hidden thinking chunk.
class LlmThinkingExtraction {
  const LlmThinkingExtraction({required this.response, this.thinking});
  final String response;
  final String? thinking;
}

/// Token-split result from [LlmThinking.splitTokens].
class LlmThinkingTokenSplit {
  const LlmThinkingTokenSplit({
    required this.thinkingTokens,
    required this.responseTokens,
  });
  final int thinkingTokens;
  final int responseTokens;
}

// =============================================================================
// Public facade
// =============================================================================

/// Pure utility around the `rac_llm_thinking` C ABI. Mirrors Swift's
/// `ThinkingContentParser` and Kotlin's `CppBridgeLlmThinking` exactly
/// so cross-SDK streaming UIs render thinking vs answer content the
/// same way everywhere.
///
/// Thread-safety: the C ABI uses a thread_local arena; Dart always
/// invokes FFI on the isolate thread. Each call copies the returned
/// strings into Dart heap memory before returning, so values are safe
/// to retain across subsequent calls.
class LlmThinking {
  const LlmThinking._();

  /// Extract the FIRST `<think>...</think>` block. Response contains
  /// everything outside the block (before + after joined by `\n`);
  /// thinking contains the inside-block content, or null when no
  /// block was found.
  ///
  /// Throws [StateError] on a null-pointer error from the C ABI
  /// (shouldn't happen with a non-null String input).
  static LlmThinkingExtraction extract(String text) {
    final textPtr = text.toNativeUtf8();
    final outRespPtr = calloc<ffi.Pointer<Utf8>>();
    final outRespLen = calloc<ffi.Size>();
    final outThinkPtr = calloc<ffi.Pointer<Utf8>>();
    final outThinkLen = calloc<ffi.Size>();
    try {
      final rc = _bindings().rac_llm_extract_thinking(
        textPtr, outRespPtr, outRespLen, outThinkPtr, outThinkLen,
      );
      if (rc != 0) {
        throw StateError('rac_llm_extract_thinking failed: code=$rc');
      }
      // Response is never NULL on success per the C ABI contract; copy
      // both strings into Dart-owned memory before the next FFI call
      // could invalidate the thread_local arena.
      final response = _copyUtf8(outRespPtr.value, outRespLen.value);
      final thinking = outThinkPtr.value.address == 0
          ? null
          : _copyUtf8(outThinkPtr.value, outThinkLen.value);
      return LlmThinkingExtraction(response: response, thinking: thinking);
    } finally {
      calloc.free(textPtr);
      calloc.free(outRespPtr);
      calloc.free(outRespLen);
      calloc.free(outThinkPtr);
      calloc.free(outThinkLen);
    }
  }

  /// Remove ALL `<think>...</think>` blocks (plus trailing unclosed
  /// `<think>`) from `text`. Returns the trimmed remainder.
  ///
  /// Throws [StateError] on a null-pointer error.
  static String strip(String text) {
    final textPtr = text.toNativeUtf8();
    final outPtr = calloc<ffi.Pointer<Utf8>>();
    final outLen = calloc<ffi.Size>();
    try {
      final rc = _bindings().rac_llm_strip_thinking(textPtr, outPtr, outLen);
      if (rc != 0 || outPtr.value.address == 0) {
        throw StateError('rac_llm_strip_thinking failed: code=$rc');
      }
      return _copyUtf8(outPtr.value, outLen.value);
    } finally {
      calloc.free(textPtr);
      calloc.free(outPtr);
      calloc.free(outLen);
    }
  }

  /// Apportion a total token count between thinking + response segments
  /// proportionally by character length.
  ///
  /// If `thinking` is null or empty: returns `(0, total)`.
  /// Else: proportional split with `thinking + response == total`.
  static LlmThinkingTokenSplit splitTokens({
    required int totalCompletionTokens,
    String? response,
    String? thinking,
  }) {
    final respPtr =
        (response == null || response.isEmpty) ? ffi.nullptr : response.toNativeUtf8();
    final thinkPtr =
        (thinking == null || thinking.isEmpty) ? ffi.nullptr : thinking.toNativeUtf8();
    final outThinking = calloc<ffi.Int32>();
    final outResponse = calloc<ffi.Int32>();
    try {
      final rc = _bindings().rac_llm_split_thinking_tokens(
        totalCompletionTokens,
        respPtr,
        thinkPtr,
        outThinking,
        outResponse,
      );
      if (rc != 0) {
        throw StateError('rac_llm_split_thinking_tokens failed: code=$rc');
      }
      return LlmThinkingTokenSplit(
        thinkingTokens: outThinking.value,
        responseTokens: outResponse.value,
      );
    } finally {
      if (respPtr != ffi.nullptr) calloc.free(respPtr);
      if (thinkPtr != ffi.nullptr) calloc.free(thinkPtr);
      calloc.free(outThinking);
      calloc.free(outResponse);
    }
  }

  /// Copy a thread_local-owned (ptr, len) UTF-8 string into a fresh
  /// Dart String.
  static String _copyUtf8(ffi.Pointer<Utf8> ptr, int len) {
    if (ptr.address == 0 || len == 0) return '';
    // The C buffer may not be NUL-terminated at `len` bytes even if
    // the implementation happens to NUL-terminate today. Use the
    // length-bounded cast.
    final bytes = ptr.cast<ffi.Uint8>().asTypedList(len);
    return String.fromCharCodes(bytes);
  }
}
