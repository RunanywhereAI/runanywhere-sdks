import 'package:fixnum/fixnum.dart';
import 'package:runanywhere/foundation/configuration/sdk_constants.dart';
import 'package:runanywhere/generated/sdk_events.pb.dart';

class SdkEventFactory {
  SdkEventFactory._();

  static SDKEvent initializationStarted() => _event(
        category: EventCategory.EVENT_CATEGORY_INITIALIZATION,
        initialization: InitializationEvent(
          stage: InitializationStage.INITIALIZATION_STAGE_STARTED,
          source: 'flutter',
          version: SDKConstants.version,
        ),
        properties: const {'type': 'sdk.initialization.started'},
      );

  static SDKEvent initializationCompleted() => _event(
        category: EventCategory.EVENT_CATEGORY_INITIALIZATION,
        initialization: InitializationEvent(
          stage: InitializationStage.INITIALIZATION_STAGE_COMPLETED,
          source: 'flutter',
          version: SDKConstants.version,
        ),
        properties: const {'type': 'sdk.initialization.completed'},
      );

  static SDKEvent initializationFailed(Object error) => _event(
        category: EventCategory.EVENT_CATEGORY_INITIALIZATION,
        severity: EventSeverity.EVENT_SEVERITY_ERROR,
        initialization: InitializationEvent(
          stage: InitializationStage.INITIALIZATION_STAGE_FAILED,
          source: 'flutter',
          error: error.toString(),
          version: SDKConstants.version,
        ),
        properties: {'type': 'sdk.initialization.failed', 'error': '$error'},
      );

  static SDKEvent modelLoadStarted(String modelId) => _model(
        ModelEventKind.MODEL_EVENT_KIND_LOAD_STARTED,
        modelId: modelId,
        type: 'model.load.started',
      );

  static SDKEvent modelLoadCompleted(String modelId) => _model(
        ModelEventKind.MODEL_EVENT_KIND_LOAD_COMPLETED,
        modelId: modelId,
        type: 'model.load.completed',
      );

  static SDKEvent modelLoadFailed(String modelId, Object error) => _model(
        ModelEventKind.MODEL_EVENT_KIND_LOAD_FAILED,
        modelId: modelId,
        error: '$error',
        type: 'model.load.failed',
        severity: EventSeverity.EVENT_SEVERITY_ERROR,
      );

  static SDKEvent modelUnloadStarted(String modelId) => _model(
        ModelEventKind.MODEL_EVENT_KIND_UNLOAD_STARTED,
        modelId: modelId,
        type: 'model.unload.started',
      );

  static SDKEvent modelUnloadCompleted(String modelId) => _model(
        ModelEventKind.MODEL_EVENT_KIND_UNLOAD_COMPLETED,
        modelId: modelId,
        type: 'model.unload.completed',
      );

  static SDKEvent modelDownloadStarted(String modelId) => _model(
        ModelEventKind.MODEL_EVENT_KIND_DOWNLOAD_STARTED,
        modelId: modelId,
        type: 'model.download.started',
      );

  static SDKEvent modelDownloadCompleted(String modelId) => _model(
        ModelEventKind.MODEL_EVENT_KIND_DOWNLOAD_COMPLETED,
        modelId: modelId,
        type: 'model.download.completed',
      );

  static SDKEvent modelDownloadFailed(String modelId, Object error) => _model(
        ModelEventKind.MODEL_EVENT_KIND_DOWNLOAD_FAILED,
        modelId: modelId,
        error: '$error',
        type: 'model.download.failed',
        severity: EventSeverity.EVENT_SEVERITY_ERROR,
      );

  static SDKEvent ragPipelineCreated() => _rag(
        CapabilityOperationEventKind
            .CAPABILITY_OPERATION_EVENT_KIND_UNSPECIFIED,
        operation: 'pipeline.created',
        type: 'rag.pipeline.created',
      );

  static SDKEvent ragPipelineDestroyed() => _rag(
        CapabilityOperationEventKind
            .CAPABILITY_OPERATION_EVENT_KIND_UNSPECIFIED,
        operation: 'pipeline.destroyed',
        type: 'rag.pipeline.destroyed',
      );

  static SDKEvent ragIngestionStarted(int documentLength) => _rag(
        CapabilityOperationEventKind
            .CAPABILITY_OPERATION_EVENT_KIND_RAG_INGESTION_STARTED,
        operation: 'ingest',
        inputCount: documentLength,
        type: 'rag.ingestion.started',
      );

  static SDKEvent ragIngestionCompleted({
    required int chunkCount,
    required double durationMs,
  }) =>
      _rag(
        CapabilityOperationEventKind
            .CAPABILITY_OPERATION_EVENT_KIND_RAG_INGESTION_COMPLETED,
        operation: 'ingest',
        outputCount: chunkCount,
        resultJson: '{"durationMs":$durationMs}',
        type: 'rag.ingestion.completed',
      );

  static SDKEvent ragQueryStarted(int questionLength) => _rag(
        CapabilityOperationEventKind
            .CAPABILITY_OPERATION_EVENT_KIND_RAG_QUERY_STARTED,
        operation: 'query',
        inputCount: questionLength,
        type: 'rag.query.started',
      );

  static SDKEvent ragQueryCompleted({
    required int answerLength,
    required int chunksRetrieved,
    required double retrievalTimeMs,
    required double generationTimeMs,
    required double totalTimeMs,
  }) =>
      _rag(
        CapabilityOperationEventKind
            .CAPABILITY_OPERATION_EVENT_KIND_RAG_QUERY_COMPLETED,
        operation: 'query',
        inputCount: chunksRetrieved,
        outputCount: answerLength,
        resultJson:
            '{"retrievalTimeMs":$retrievalTimeMs,"generationTimeMs":$generationTimeMs,"totalTimeMs":$totalTimeMs}',
        type: 'rag.query.completed',
      );

  static SDKEvent ragFailed(Object error) => _rag(
        CapabilityOperationEventKind.CAPABILITY_OPERATION_EVENT_KIND_RAG_FAILED,
        operation: 'rag',
        error: '$error',
        type: 'rag.error',
        severity: EventSeverity.EVENT_SEVERITY_ERROR,
      );

  static SDKEvent _model(
    ModelEventKind kind, {
    required String modelId,
    required String type,
    Object? error,
    EventSeverity severity = EventSeverity.EVENT_SEVERITY_INFO,
  }) =>
      _event(
        category: EventCategory.EVENT_CATEGORY_MODEL,
        component: SDKComponent.SDK_COMPONENT_UNSPECIFIED,
        severity: severity,
        model: ModelEvent(
          kind: kind,
          modelId: modelId,
          error: error?.toString(),
        ),
        properties: {
          'type': type,
          'modelId': modelId,
          if (error != null) 'error': '$error',
        },
      );

  static SDKEvent _rag(
    CapabilityOperationEventKind kind, {
    required String operation,
    required String type,
    int? inputCount,
    int? outputCount,
    String? resultJson,
    Object? error,
    EventSeverity severity = EventSeverity.EVENT_SEVERITY_INFO,
  }) =>
      _event(
        category: EventCategory.EVENT_CATEGORY_RAG,
        component: SDKComponent.SDK_COMPONENT_RAG,
        severity: severity,
        capability: CapabilityOperationEvent(
          kind: kind,
          component: SDKComponent.SDK_COMPONENT_RAG,
          operation: operation,
          inputCount: inputCount == null ? null : Int64(inputCount),
          outputCount: outputCount == null ? null : Int64(outputCount),
          resultJson: resultJson,
          error: error?.toString(),
        ),
        properties: {
          'type': type,
          'operation': operation,
          if (error != null) 'error': '$error',
        },
      );

  static SDKEvent _event({
    required EventCategory category,
    EventSeverity severity = EventSeverity.EVENT_SEVERITY_INFO,
    SDKComponent component = SDKComponent.SDK_COMPONENT_UNSPECIFIED,
    InitializationEvent? initialization,
    ModelEvent? model,
    CapabilityOperationEvent? capability,
    Map<String, String> properties = const {},
  }) {
    return SDKEvent(
      id: 'flutter-${DateTime.now().microsecondsSinceEpoch}',
      timestampMs: Int64(DateTime.now().millisecondsSinceEpoch),
      severity: severity,
      destination: EventDestination.EVENT_DESTINATION_ALL,
      category: category,
      component: component,
      initialization: initialization,
      model: model,
      capability: capability,
      properties: properties,
    );
  }
}
