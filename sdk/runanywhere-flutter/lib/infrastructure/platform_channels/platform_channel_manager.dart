import 'package:flutter/services.dart';

/// Platform channel manager for native code integration
class PlatformChannelManager {
  static const MethodChannel _channel = MethodChannel('com.runanywhere.sdk/native');

  /// Initialize platform channels
  static Future<void> initialize() async {
    // Platform channels are initialized automatically
  }

  /// Call native method
  static Future<dynamic> callMethod(String method, [Map<String, dynamic>? arguments]) async {
    try {
      return await _channel.invokeMethod(method, arguments);
    } on PlatformException catch (e) {
      throw Exception('Platform error: ${e.message}');
    }
  }

  /// Audio session management (iOS/Android)
  static Future<void> configureAudioSession({
    required String mode,
  }) async {
    await callMethod('configureAudioSession', {'mode': mode});
  }

  /// Request microphone permission
  static Future<bool> requestMicrophonePermission() async {
    final result = await callMethod('requestMicrophonePermission');
    return result as bool? ?? false;
  }

  /// Check microphone permission
  static Future<bool> hasMicrophonePermission() async {
    final result = await callMethod('hasMicrophonePermission');
    return result as bool? ?? false;
  }

  /// Get device capabilities
  static Future<Map<String, dynamic>> getDeviceCapabilities() async {
    final result = await callMethod('getDeviceCapabilities');
    return result as Map<String, dynamic>? ?? {};
  }

  /// Load native model (if using native SDKs)
  static Future<bool> loadNativeModel({
    required String modelId,
    required String modelPath,
  }) async {
    final result = await callMethod('loadNativeModel', {
      'modelId': modelId,
      'modelPath': modelPath,
    });
    return result as bool? ?? false;
  }

  /// Unload native model
  static Future<void> unloadNativeModel(String modelId) async {
    await callMethod('unloadNativeModel', {'modelId': modelId});
  }
}

