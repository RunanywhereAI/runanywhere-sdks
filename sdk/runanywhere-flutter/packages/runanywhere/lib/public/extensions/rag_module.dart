/// RAG backend module for RunAnywhere Flutter SDK.
///
/// This module registers the RAG (Retrieval-Augmented Generation) backend
/// with the RunAnywhere plugin system via the module lifecycle.
///
/// ## Architecture
///
/// The C++ RAG pipeline (compiled into RACommons) handles all business logic:
/// - RAG pipeline creation and management
/// - Document embedding and vector indexing
/// - Query retrieval and LLM answer generation
///
/// This Dart module just:
/// 1. Calls `rac_backend_rag_register()` to register the backend
/// 2. The core SDK handles RAG operations via `DartBridgeRAG`
///
/// ## Quick Start
///
/// ```dart
/// import 'package:runanywhere/public/extensions/rag_module.dart';
///
/// // Register the module (matches Swift: RAGModule.register())
/// await RAGModule.register();
///
/// // Use DartBridgeRAG for pipeline operations
/// DartBridgeRAG.shared.createPipeline(config: myConfig);
/// ```
library;

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/dart_bridge_rag.dart';

/// RAG module for Retrieval-Augmented Generation.
///
/// Registers the C++ RAG backend with the RunAnywhere service registry.
/// RAG uses ONNX for embeddings and delegates LLM generation to the
/// already-registered LlamaCpp backend.
///
/// Matches the Swift RAGModule pattern from the iOS SDK.
class RAGModule {
  RAGModule._();

  // ============================================================================
  // Registration State
  // ============================================================================

  static bool _isRegistered = false;
  static final _logger = SDKLogger('RAGModule');

  // ============================================================================
  // Registration (matches LlamaCpp.register() pattern)
  // ============================================================================

  /// Register the RAG backend with the C++ service registry.
  ///
  /// Calls `rac_backend_rag_register()` to register the RAG service provider.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  static Future<void> register() async {
    if (_isRegistered) {
      _logger.debug('RAGModule already registered');
      return;
    }

    _logger.info('Registering RAG backend with C++ registry...');

    try {
      DartBridgeRAG.shared.register();

      _isRegistered = true;
      _logger.info('RAG backend registered successfully');
    } catch (e) {
      _logger.error('RAG backend not available: $e');
      rethrow;
    }
  }

  /// Unregister the RAG backend from the C++ service registry.
  static void unregister() {
    if (!_isRegistered) {
      return;
    }

    DartBridgeRAG.shared.unregister();
    _isRegistered = false;
    _logger.info('RAG backend unregistered');
  }

  /// Whether the RAG backend is currently registered.
  static bool get isRegistered => _isRegistered;
}
