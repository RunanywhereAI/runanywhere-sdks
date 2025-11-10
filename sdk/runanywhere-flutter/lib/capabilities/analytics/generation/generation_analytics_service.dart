import '../../../public/models/generation_result.dart';
import '../../../public/models/performance_metrics.dart';

/// Generation Analytics Service
/// Similar to Swift SDK's GenerationAnalyticsService
class GenerationAnalyticsService {
  final List<GenerationAnalyticsRecord> _records = [];

  /// Record a generation
  Future<void> recordGeneration({
    required String generationId,
    required String modelId,
    required GenerationResult result,
    required PerformanceMetrics metrics,
  }) async {
    final record = GenerationAnalyticsRecord(
      generationId: generationId,
      modelId: modelId,
      result: result,
      metrics: metrics,
      timestamp: DateTime.now(),
    );

    _records.add(record);
  }

  /// Get all records
  List<GenerationAnalyticsRecord> getAllRecords() {
    return List.unmodifiable(_records);
  }

  /// Get records for a model
  List<GenerationAnalyticsRecord> getRecordsForModel(String modelId) {
    return _records.where((r) => r.modelId == modelId).toList();
  }

  /// Clear all records
  void clearRecords() {
    _records.clear();
  }
}

/// Generation Analytics Record
class GenerationAnalyticsRecord {
  final String generationId;
  final String modelId;
  final GenerationResult result;
  final PerformanceMetrics metrics;
  final DateTime timestamp;

  GenerationAnalyticsRecord({
    required this.generationId,
    required this.modelId,
    required this.result,
    required this.metrics,
    required this.timestamp,
  });
}

