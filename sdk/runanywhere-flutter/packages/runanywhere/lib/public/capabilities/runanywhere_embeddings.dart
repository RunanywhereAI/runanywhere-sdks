// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_embeddings.dart - Embeddings capability (B10).
//
// STUB: this capability surfaces the public `embed(...)` API on
// `RunAnywhereSDK.instance.embeddings`, but the underlying FFI bridge
// (`DartBridgeEmbeddings`) does not exist yet.
//
// TODO(B10): implement `lib/native/dart_bridge_embeddings.dart` with
// ffi bindings for the three `rac_embeddings_*` C symbols:
//   - rac_embeddings_create(const char* modelId, rac_handle_t* out)
//   - rac_embeddings_embed(handle, text, options*, result*)
//   - rac_embeddings_destroy(handle)
// Plus a finalizer + a handle cache keyed on modelId. See
// `lib/native/dart_bridge_diffusion.dart` for the pattern and
// `lib/public/capabilities/runanywhere_embeddings.dart` (this file)
// for the public-surface shape to preserve.

import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/generated/embeddings_options.pb.dart'
    show EmbeddingsOptions, EmbeddingsResult;
import 'package:runanywhere/internal/sdk_state.dart';

/// Embeddings capability surface.
///
/// Access via `RunAnywhereSDK.instance.embeddings`. Mirrors Swift
/// `RunAnywhere.embed(text:modelId:options:)`.
class RunAnywhereEmbeddings {
  RunAnywhereEmbeddings._();
  static final RunAnywhereEmbeddings _instance = RunAnywhereEmbeddings._();
  static RunAnywhereEmbeddings get shared => _instance;

  /// Generate an embedding vector for a single text.
  ///
  /// Returns an [EmbeddingsResult] containing one vector under `vectors[0]`.
  /// Throws [SDKException.notInitialized] if the SDK is not yet initialized
  /// and [SDKException.notImplemented] until the FFI bridge lands (see
  /// file header TODO).
  ///
  /// - [text]: the input text to embed.
  /// - [modelId]: the embeddings model identifier (registry id or path).
  /// - [options]: optional per-call overrides.
  Future<EmbeddingsResult> embed(
    String text, {
    required String modelId,
    EmbeddingsOptions? options,
  }) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    throw SDKException.notImplemented(
      'embeddings.embed(): TODO(B10) - FFI bridge '
      'DartBridgeEmbeddings not implemented yet. See file header.',
    );
  }
}
