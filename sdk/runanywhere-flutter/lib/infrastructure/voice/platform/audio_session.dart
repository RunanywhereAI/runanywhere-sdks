import '../../platform_channels/platform_channel_manager.dart';

/// Audio session management for voice processing
enum VoiceProcessingMode {
  recording,
  playback,
  conversation,
}

/// Platform-agnostic audio session interface
class AudioSession {
  /// Configure audio session for voice processing
  Future<void> configure(VoiceProcessingMode mode) async {
    await PlatformChannelManager.configureAudioSession(
      mode: mode.name,
    );
  }

  /// Activate audio session
  Future<void> activate() async {
    await PlatformChannelManager.callMethod('activateAudioSession');
  }

  /// Deactivate audio session
  Future<void> deactivate() async {
    await PlatformChannelManager.callMethod('deactivateAudioSession');
  }

  /// Request microphone permission
  Future<bool> requestMicrophonePermission() async {
    return await PlatformChannelManager.requestMicrophonePermission();
  }

  /// Check if microphone permission is granted
  Future<bool> get hasMicrophonePermission async {
    return await PlatformChannelManager.hasMicrophonePermission();
  }
}

