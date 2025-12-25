import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:runanywhere/foundation/configuration/sdk_constants.dart';
import 'package:runanywhere/foundation/device_identity/device_manager.dart';
import 'package:runanywhere/foundation/error_types/sdk_error.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';
// Note: package_info_plus is optional - analytics will work without it
// import 'package:package_info_plus/package_info_plus.dart' show PackageInfo;

/// Service for submitting generation analytics
class AnalyticsService {
  final SDKLogger logger = SDKLogger(category: 'AnalyticsService');
  final SDKInitParams? initParams;

  AnalyticsService({this.initParams});

  /// Submit generation analytics
  Future<void> submitGenerationAnalytics({
    required String generationId,
    required String modelId,
    required PerformanceMetrics performanceMetrics,
    required int inputTokens,
    required int outputTokens,
    required bool success,
    required String executionTarget,
  }) async {
    // Only submit in development mode
    if (initParams?.environment != SDKEnvironment.development) {
      return;
    }

    // Non-blocking background submission
    unawaited(_submitInBackground(
      generationId: generationId,
      modelId: modelId,
      performanceMetrics: performanceMetrics,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      success: success,
      executionTarget: executionTarget,
    ));
  }

  Future<void> _submitInBackground({
    required String generationId,
    required String modelId,
    required PerformanceMetrics performanceMetrics,
    required int inputTokens,
    required int outputTokens,
    required bool success,
    required String executionTarget,
  }) async {
    try {
      final deviceId = await DeviceManager.shared.getDeviceId();

      // Get host app information (optional)
      String? hostAppIdentifier;
      String? hostAppName;
      String? hostAppVersion;

      // Try to get package info if available
      // Note: This requires package_info_plus dependency
      // try {
      //   final packageInfo = await PackageInfo.fromPlatform();
      //   hostAppIdentifier = packageInfo.packageName;
      //   hostAppName = packageInfo.appName;
      //   hostAppVersion = packageInfo.version;
      // } catch (e) {
      //   // Silently continue without package info
      // }

      final request = DevAnalyticsSubmissionRequest(
        generationId: generationId,
        deviceId: deviceId,
        modelId: modelId,
        timeToFirstTokenMs: performanceMetrics.timeToFirstTokenMs,
        tokensPerSecond: performanceMetrics.tokensPerSecond,
        totalGenerationTimeMs: performanceMetrics.inferenceTimeMs,
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        success: success,
        executionTarget: executionTarget,
        buildToken: 'BuildToken.token', // Placeholder
        sdkVersion: SDKConstants.version,
        timestamp: DateTime.now().toIso8601String(),
        hostAppIdentifier: hostAppIdentifier,
        hostAppName: hostAppName,
        hostAppVersion: hostAppVersion,
      );

      if (initParams?.supabaseConfig != null) {
        await _submitViaSupabase(request, initParams!.supabaseConfig!);
      } else {
        await _submitViaBackend(request, initParams!.baseURL);
      }
    } catch (e) {
      // Silent failure - analytics should not break the app
      logger.debug('Analytics submission failed (silent): $e');
    }
  }

  Future<void> _submitViaSupabase(
    DevAnalyticsSubmissionRequest request,
    SupabaseConfig config,
  ) async {
    final url = config.projectURL
        .resolve('/rest/v1/sdk_generation_analytics')
        .toString();

    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'apikey': config.anonKey,
        'Authorization': 'Bearer ${config.anonKey}',
      },
      body: jsonEncode(request.toJson()),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw SDKError.networkError(
        'Analytics submission failed: ${response.statusCode}',
      );
    }

    logger.debug('Analytics submission successful');
  }

  Future<void> _submitViaBackend(
    DevAnalyticsSubmissionRequest request,
    Uri baseURL,
  ) async {
    final url = baseURL.resolve('/api/v1/analytics/generation').toString();

    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw SDKError.networkError('Analytics submission failed');
    }
  }
}

/// Analytics submission request
class DevAnalyticsSubmissionRequest {
  final String generationId;
  final String deviceId;
  final String modelId;
  final int timeToFirstTokenMs;
  final double tokensPerSecond;
  final int totalGenerationTimeMs;
  final int inputTokens;
  final int outputTokens;
  final bool success;
  final String executionTarget;
  final String buildToken;
  final String sdkVersion;
  final String timestamp;
  final String? hostAppIdentifier;
  final String? hostAppName;
  final String? hostAppVersion;

  DevAnalyticsSubmissionRequest({
    required this.generationId,
    required this.deviceId,
    required this.modelId,
    required this.timeToFirstTokenMs,
    required this.tokensPerSecond,
    required this.totalGenerationTimeMs,
    required this.inputTokens,
    required this.outputTokens,
    required this.success,
    required this.executionTarget,
    required this.buildToken,
    required this.sdkVersion,
    required this.timestamp,
    this.hostAppIdentifier,
    this.hostAppName,
    this.hostAppVersion,
  });

  Map<String, dynamic> toJson() => {
        'generation_id': generationId,
        'device_id': deviceId,
        'model_id': modelId,
        'time_to_first_token_ms': timeToFirstTokenMs,
        'tokens_per_second': tokensPerSecond,
        'total_generation_time_ms': totalGenerationTimeMs,
        'input_tokens': inputTokens,
        'output_tokens': outputTokens,
        'success': success,
        'execution_target': executionTarget,
        'build_token': buildToken,
        'sdk_version': sdkVersion,
        'timestamp': timestamp,
        if (hostAppIdentifier != null) 'host_app_identifier': hostAppIdentifier,
        if (hostAppName != null) 'host_app_name': hostAppName,
        if (hostAppVersion != null) 'host_app_version': hostAppVersion,
      };
}

/// Performance metrics
class PerformanceMetrics {
  final int timeToFirstTokenMs;
  final double tokensPerSecond;
  final int inferenceTimeMs;
  final int peakMemoryUsage;

  PerformanceMetrics({
    required this.timeToFirstTokenMs,
    required this.tokensPerSecond,
    required this.inferenceTimeMs,
    required this.peakMemoryUsage,
  });
}
