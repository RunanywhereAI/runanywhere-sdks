// SPDX-License-Identifier: Apache-2.0
//
// dart_bridge_llm_streaming.dart — FFI-only helpers that wrap proto
// LLM stream-event subscription. Public capability code calls
// [DartBridgeLLMStreaming.protoStream] / [.protoAvailable] and stays
// free of `dart:ffi` imports (canonical §15 type-discipline).

import 'dart:ffi' as ffi;

import 'package:runanywhere/adapters/llm_stream_adapter.dart';
import 'package:runanywhere/core/native/rac_native.dart' show RacNative;
import 'package:runanywhere/generated/llm_service.pb.dart' show LLMStreamEvent;
import 'package:runanywhere/native/dart_bridge_llm.dart';

/// FFI helpers for proto-based LLM streaming. Owned by `lib/native/`
/// so the public capability layer can stay `dart:ffi`-free.
class DartBridgeLLMStreaming {
  DartBridgeLLMStreaming._();

  static bool? _protoCache;

  /// Cached check for whether the loaded native library exposes
  /// proto streaming. Strategy: register a null function pointer
  /// with `rac_llm_set_stream_proto_callback` — `RAC_SUCCESS` means
  /// the symbol is wired up. Result is cached process-wide.
  static bool protoAvailable() {
    if (_protoCache != null) return _protoCache!;

    final handle = DartBridgeLLM.shared.getHandle();
    try {
      final rc = RacNative.bindings.rac_llm_set_stream_proto_callback(
        handle,
        ffi.nullptr,
        ffi.nullptr,
      );
      if (rc == 0) {
        RacNative.bindings.rac_llm_unset_stream_proto_callback(handle);
        _protoCache = true;
      } else {
        _protoCache = false;
      }
    } catch (_) {
      _protoCache = false;
    }
    return _protoCache!;
  }

  /// Open a proto-event stream for the loaded LLM model. The caller
  /// is responsible for invoking the underlying generation driver
  /// (e.g. via [DartBridgeLLM.generateStream]) so the C++ backend
  /// produces tokens; this method only sets up the proto-event
  /// subscription.
  static Stream<LLMStreamEvent> protoStream() {
    final handle = DartBridgeLLM.shared.getHandle();
    return LLMStreamAdapter(handle).stream();
  }
}
