import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/capabilities/analytics/analytics_service.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';

void main() {
  group('AnalyticsService Tests', () {
    test('AnalyticsService initialization', () {
      final service = AnalyticsService(initParams: null);
      expect(service, isNotNull);
    });

    test('PerformanceMetrics creation', () {
      final metrics = PerformanceMetrics(
        timeToFirstTokenMs: 100,
        tokensPerSecond: 50.0,
        inferenceTimeMs: 2000,
        peakMemoryUsage: 500 * 1024 * 1024,
      );

      expect(metrics.timeToFirstTokenMs, equals(100));
      expect(metrics.tokensPerSecond, equals(50.0));
      expect(metrics.inferenceTimeMs, equals(2000));
      expect(metrics.peakMemoryUsage, equals(500 * 1024 * 1024));
    });

    test('DevAnalyticsSubmissionRequest creation', () {
      final request = DevAnalyticsSubmissionRequest(
        generationId: 'test-id',
        deviceId: 'device-id',
        modelId: 'model-id',
        timeToFirstTokenMs: 100,
        tokensPerSecond: 50.0,
        totalGenerationTimeMs: 2000,
        inputTokens: 10,
        outputTokens: 20,
        success: true,
        executionTarget: 'on_device',
        buildToken: 'token',
        sdkVersion: '0.15.8',
        timestamp: DateTime.now().toIso8601String(),
      );

      expect(request.generationId, equals('test-id'));
      expect(request.success, isTrue);
      expect(request.toJson(), isA<Map<String, dynamic>>());
    });
  });
}

