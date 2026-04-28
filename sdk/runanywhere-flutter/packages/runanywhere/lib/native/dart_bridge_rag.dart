/// DartBridge+RAG
///
/// RAG pipeline bridge using C++ JSON-based bridge functions.
/// The C++ bridge (flutter_rag_bridge.cpp) handles:
/// - JSON parsing and C struct marshalling
/// - Model path resolution (GGUF directory scanning, vocab.txt discovery)
/// - Thread safety (std::mutex)
/// - Pipeline lifecycle management
///
/// This Dart layer is a thin FFI wrapper that passes JSON strings to/from C++.
library dart_bridge_rag;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/generated/rag.pb.dart';

// =============================================================================
// FFI Function Typedefs for C++ bridge (flutter_rag_bridge.h)
// =============================================================================

// int32_t flutter_rag_create_pipeline_json(const char* config_json)
typedef _CreatePipelineJsonNative = Int32 Function(Pointer<Utf8> configJson);
typedef _CreatePipelineJsonDart = int Function(Pointer<Utf8> configJson);

// int32_t flutter_rag_destroy_pipeline()
typedef _DestroyPipelineNative = Int32 Function();
typedef _DestroyPipelineDart = int Function();

// int32_t flutter_rag_add_document(const char* text, const char* metadata_json)
typedef _AddDocumentNative = Int32 Function(
    Pointer<Utf8> text, Pointer<Utf8> metadataJson);
typedef _AddDocumentDart = int Function(
    Pointer<Utf8> text, Pointer<Utf8> metadataJson);

// int32_t flutter_rag_add_documents_batch_json(const char* documents_json)
typedef _AddDocumentsBatchJsonNative = Int32 Function(
    Pointer<Utf8> documentsJson);
typedef _AddDocumentsBatchJsonDart = int Function(
    Pointer<Utf8> documentsJson);

// const char* flutter_rag_query_json(const char* query_json)
typedef _QueryJsonNative = Pointer<Utf8> Function(Pointer<Utf8> queryJson);
typedef _QueryJsonDart = Pointer<Utf8> Function(Pointer<Utf8> queryJson);

// int32_t flutter_rag_clear_documents()
typedef _ClearDocumentsNative = Int32 Function();
typedef _ClearDocumentsDart = int Function();

// int32_t flutter_rag_get_document_count()
typedef _GetDocumentCountNative = Int32 Function();
typedef _GetDocumentCountDart = int Function();

// const char* flutter_rag_get_statistics_json()
typedef _GetStatisticsJsonNative = Pointer<Utf8> Function();
typedef _GetStatisticsJsonDart = Pointer<Utf8> Function();

// void flutter_rag_free_string(const char* str)
typedef _FreeStringNative = Void Function(Pointer<Utf8> str);
typedef _FreeStringDart = void Function(Pointer<Utf8> str);

// const char* flutter_rag_get_last_error()
typedef _GetLastErrorNative = Pointer<Utf8> Function();
typedef _GetLastErrorDart = Pointer<Utf8> Function();

// RAG backend registration (from RACommons, not the bridge)
typedef _RagRegisterNative = Int32 Function();
typedef _RagRegisterDart = int Function();

// =============================================================================
// DartBridgeRAG — JSON-based FFI bridge to C++ RAG bridge
// =============================================================================

/// RAG pipeline bridge for C++ interop.
///
/// Uses the C++ flutter_rag_bridge which handles JSON parsing, model path
/// resolution, and all C struct marshalling internally.
class DartBridgeRAG {
  static final DartBridgeRAG shared = DartBridgeRAG._();

  DartBridgeRAG._();

  final _logger = SDKLogger('DartBridge.RAG');
  DynamicLibrary? _bridgeLib;
  bool _registered = false;

  bool get isCreated => _isCreated;
  bool _isCreated = false;

  /// Load the library containing the bridge functions.
  ///
  /// On iOS: bridge is statically linked via podspec, accessible from executable.
  /// On Android: bridge is a separate .so loaded dynamically.
  DynamicLibrary _loadBridgeLib() {
    if (_bridgeLib != null) return _bridgeLib!;

    if (Platform.isIOS) {
      // Statically linked — symbols accessible from the executable
      _bridgeLib = DynamicLibrary.executable();
    } else if (Platform.isAndroid) {
      // Try loading the separate bridge .so first
      try {
        _bridgeLib = DynamicLibrary.open('libflutter_rag_bridge.so');
      } catch (_) {
        // Fallback: bridge symbols might be in rac_commons (future unified build)
        _bridgeLib = PlatformLoader.loadCommons();
      }
    } else {
      // macOS/Linux/Windows: try process, then executable, then commons
      try {
        final lib = DynamicLibrary.process();
        lib.lookup('flutter_rag_create_pipeline_json');
        _bridgeLib = lib;
      } catch (_) {
        try {
          final lib = DynamicLibrary.executable();
          lib.lookup('flutter_rag_create_pipeline_json');
          _bridgeLib = lib;
        } catch (_) {
          _bridgeLib = PlatformLoader.loadCommons();
        }
      }
    }

    return _bridgeLib!;
  }

  /// Register the RAG module (call once before using RAG).
  void register() {
    if (_registered) return;

    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<_RagRegisterNative, _RagRegisterDart>(
        'rac_backend_rag_register');

    final result = fn();
    if (result != RAC_SUCCESS && result != -401) {
      _logger.error('Failed to register RAG module: $result');
      return;
    }

    _registered = true;
    _logger.debug('RAG module registered');
  }

  /// Create a RAG pipeline with the given configuration.
  ///
  /// The C++ bridge handles JSON parsing, model path resolution, and
  /// auto-registers the RAG module if needed.
  void createPipeline(RAGConfiguration config) {
    final lib = _loadBridgeLib();
    final fn = lib.lookupFunction<_CreatePipelineJsonNative,
        _CreatePipelineJsonDart>('flutter_rag_create_pipeline_json');

    final jsonStr = config.writeToJson();
    _logger.debug('createPipeline config: $jsonStr');
    final cStr = jsonStr.toNativeUtf8();

    try {
      final result = fn(cStr);
      if (result != 0) {
        final detail = _getLastError();
        final msg = detail != null
            ? 'RAG pipeline creation failed (code $result): $detail'
            : 'RAG pipeline creation failed (code $result)';
        _logger.error(msg);
        throw Exception(msg);
      }

      _isCreated = true;
      _registered = true; // C++ bridge auto-registers
      _logger.debug('RAG pipeline created');
    } finally {
      calloc.free(cStr);
    }
  }

  /// Fetch last error detail from the C++ bridge (if any).
  String? _getLastError() {
    try {
      final lib = _loadBridgeLib();
      final fn = lib.lookupFunction<_GetLastErrorNative, _GetLastErrorDart>(
          'flutter_rag_get_last_error');
      final freeFn = lib.lookupFunction<_FreeStringNative, _FreeStringDart>(
          'flutter_rag_free_string');

      final ptr = fn();
      if (ptr == nullptr) return null;

      final detail = ptr.toDartString();
      freeFn(ptr);
      return detail;
    } catch (_) {
      return null;
    }
  }

  /// Destroy the RAG pipeline.
  void destroyPipeline() {
    if (!_isCreated) return;

    final lib = _loadBridgeLib();
    final fn = lib.lookupFunction<_DestroyPipelineNative, _DestroyPipelineDart>(
        'flutter_rag_destroy_pipeline');

    fn();
    _isCreated = false;
    _logger.debug('RAG pipeline destroyed');
  }

  /// Add a document to the pipeline.
  void addDocument(String text, {String? metadataJson}) {
    _ensurePipeline();

    final lib = _loadBridgeLib();
    final fn =
        lib.lookupFunction<_AddDocumentNative, _AddDocumentDart>(
            'flutter_rag_add_document');

    final cText = text.toNativeUtf8();
    final cMeta = metadataJson != null ? metadataJson.toNativeUtf8() : nullptr;

    try {
      final result = fn(cText, cMeta);
      if (result != 0) {
        throw Exception('Failed to add document: error $result');
      }
    } finally {
      calloc.free(cText);
      if (cMeta != nullptr) calloc.free(cMeta);
    }
  }

  /// Add multiple documents in batch.
  ///
  /// [documents] is a list of maps with 'text' and optional 'metadataJson' keys.
  void addDocumentsBatch(List<Map<String, String>> documents) {
    _ensurePipeline();

    final lib = _loadBridgeLib();
    final fn = lib.lookupFunction<_AddDocumentsBatchJsonNative,
        _AddDocumentsBatchJsonDart>('flutter_rag_add_documents_batch_json');

    final jsonStr = jsonEncode(documents);
    final cStr = jsonStr.toNativeUtf8();

    try {
      final result = fn(cStr);
      if (result != 0) {
        throw Exception('Failed to add documents batch: error $result');
      }
    } finally {
      calloc.free(cStr);
    }
  }

  /// Clear all documents from the pipeline.
  void clearDocuments() {
    _ensurePipeline();

    final lib = _loadBridgeLib();
    final fn = lib.lookupFunction<_ClearDocumentsNative, _ClearDocumentsDart>(
        'flutter_rag_clear_documents');

    fn();
  }

  /// Get the number of indexed document chunks.
  int get documentCount {
    if (!_isCreated) return 0;

    final lib = _loadBridgeLib();
    final fn = lib
        .lookupFunction<_GetDocumentCountNative, _GetDocumentCountDart>(
            'flutter_rag_get_document_count');

    return fn();
  }

  /// Query the RAG pipeline.
  RAGResult query(RAGQueryOptions options) {
    _ensurePipeline();

    final lib = _loadBridgeLib();
    final queryFn =
        lib.lookupFunction<_QueryJsonNative, _QueryJsonDart>(
            'flutter_rag_query_json');
    final freeFn =
        lib.lookupFunction<_FreeStringNative, _FreeStringDart>(
            'flutter_rag_free_string');

    final jsonStr = options.writeToJson();
    final cStr = jsonStr.toNativeUtf8();

    try {
      final resultPtr = queryFn(cStr);
      final resultJson = resultPtr.toDartString();
      freeFn(resultPtr);

      return RAGResult.fromJson(resultJson);
    } finally {
      calloc.free(cStr);
    }
  }

  /// Get pipeline statistics.
  RAGStatistics getStatistics() {
    _ensurePipeline();

    final lib = _loadBridgeLib();
    final fn = lib.lookupFunction<_GetStatisticsJsonNative,
        _GetStatisticsJsonDart>('flutter_rag_get_statistics_json');
    final freeFn =
        lib.lookupFunction<_FreeStringNative, _FreeStringDart>(
            'flutter_rag_free_string');

    final resultPtr = fn();
    final resultJson = resultPtr.toDartString();
    freeFn(resultPtr);

    return RAGStatistics.fromJson(resultJson);
  }

  void _ensurePipeline() {
    if (!_isCreated) {
      throw StateError('RAG pipeline not created. Call createPipeline() first.');
    }
  }

  /// Create pipeline on a background isolate.
  Future<void> createPipelineAsync(RAGConfiguration config) async {
    final jsonStr = config.writeToJson();
    _logger.debug('createPipelineAsync config: $jsonStr');

    final result = await Isolate.run(() => _isolateCreatePipeline(jsonStr));
    if (result != 0) {
      final detail = _getLastError();
      final msg = detail != null
          ? 'RAG pipeline creation failed (code $result): $detail'
          : 'RAG pipeline creation failed (code $result)';
      _logger.error(msg);
      throw Exception(msg);
    }

    _isCreated = true;
    _registered = true;
    _logger.debug('RAG pipeline created (async)');
  }

  Future<void> addDocumentAsync(String text, {String? metadataJson}) async {
    _ensurePipeline();
    _logger.debug('addDocumentAsync: ${text.length} chars');

    final result = await Isolate.run(
      () => _isolateAddDocument(text, metadataJson),
    );
    if (result != 0) {
      throw Exception('Failed to add document: error $result');
    }
  }

  Future<void> addDocumentsBatchAsync(
    List<Map<String, String>> documents,
  ) async {
    _ensurePipeline();

    final jsonStr = jsonEncode(documents);
    final result = await Isolate.run(
      () => _isolateAddDocumentsBatch(jsonStr),
    );
    if (result != 0) {
      throw Exception('Failed to add documents batch: error $result');
    }
  }

  Future<RAGResult> queryAsync(RAGQueryOptions options) async {
    _ensurePipeline();

    final jsonStr = options.writeToJson();
    final resultJson = await Isolate.run(
      () => _isolateQuery(jsonStr),
    );

    return RAGResult.fromJson(resultJson);
  }
}

DynamicLibrary _openBridgeLib() {
  if (Platform.isIOS) {
    return DynamicLibrary.executable();
  } else if (Platform.isAndroid) {
    try {
      return DynamicLibrary.open('libflutter_rag_bridge.so');
    } catch (_) {
      return DynamicLibrary.open('librac_commons.so');
    }
  } else {
    return DynamicLibrary.process();
  }
}

DynamicLibrary _openCommonsLib() {
  if (Platform.isIOS) {
    return DynamicLibrary.executable();
  } else if (Platform.isAndroid) {
    return DynamicLibrary.open('librac_commons.so');
  } else {
    return DynamicLibrary.process();
  }
}

int _isolateCreatePipeline(String configJson) {
  final commons = _openCommonsLib();
  final registerFn =
      commons.lookupFunction<_RagRegisterNative, _RagRegisterDart>(
          'rac_backend_rag_register');
  registerFn(); 

  final lib = _openBridgeLib();
  final fn = lib.lookupFunction<_CreatePipelineJsonNative,
      _CreatePipelineJsonDart>('flutter_rag_create_pipeline_json');

  final cStr = configJson.toNativeUtf8();
  try {
    return fn(cStr);
  } finally {
    calloc.free(cStr);
  }
}

int _isolateAddDocument(String text, String? metadataJson) {
  final lib = _openBridgeLib();
  final fn = lib.lookupFunction<_AddDocumentNative, _AddDocumentDart>(
      'flutter_rag_add_document');

  final cText = text.toNativeUtf8();
  final cMeta = metadataJson != null ? metadataJson.toNativeUtf8() : nullptr;

  try {
    return fn(cText, cMeta);
  } finally {
    calloc.free(cText);
    if (cMeta != nullptr) calloc.free(cMeta);
  }
}

int _isolateAddDocumentsBatch(String documentsJson) {
  final lib = _openBridgeLib();
  final fn = lib.lookupFunction<_AddDocumentsBatchJsonNative,
      _AddDocumentsBatchJsonDart>('flutter_rag_add_documents_batch_json');

  final cStr = documentsJson.toNativeUtf8();
  try {
    return fn(cStr);
  } finally {
    calloc.free(cStr);
  }
}

String _isolateQuery(String queryJson) {
  final lib = _openBridgeLib();
  final queryFn = lib.lookupFunction<_QueryJsonNative, _QueryJsonDart>(
      'flutter_rag_query_json');
  final freeFn = lib.lookupFunction<_FreeStringNative, _FreeStringDart>(
      'flutter_rag_free_string');

  final cStr = queryJson.toNativeUtf8();
  try {
    final resultPtr = queryFn(cStr);
    final resultJson = resultPtr.toDartString();
    freeFn(resultPtr);
    return resultJson;
  } finally {
    calloc.free(cStr);
  }
}
