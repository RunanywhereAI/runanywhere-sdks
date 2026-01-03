import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// PermissionService - Centralized permission handling for the app
///
/// Handles microphone and speech recognition permissions with proper
/// user guidance for denied/permanently denied states.
class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  static PermissionService get shared => _instance;

  PermissionService._internal();

  /// Request microphone permission with proper handling of all states
  ///
  /// Returns true if permission is granted, false otherwise.
  /// Shows appropriate dialogs for denied/permanently denied states.
  Future<bool> requestMicrophonePermission(BuildContext context) async {
    final status = await Permission.microphone.status;

    if (status.isGranted) {
      return true;
    }

    if (status.isPermanentlyDenied) {
      if (!context.mounted) return false;
      // Permission was permanently denied, show settings dialog
      final shouldOpenSettings = await _showSettingsDialog(
        context,
        title: 'Microphone Permission Required',
        message:
            'Microphone access is required for voice features. Please enable it in Settings.',
      );

      if (shouldOpenSettings) {
        await openAppSettings();
      }
      return false;
    }

    // Request permission
    final result = await Permission.microphone.request();

    if (result.isGranted) {
      return true;
    }

    if (!context.mounted) return false;

    if (result.isPermanentlyDenied) {
      // User denied with "Don't ask again", show settings dialog
      final shouldOpenSettings = await _showSettingsDialog(
        context,
        title: 'Microphone Permission Required',
        message:
            'Microphone access is required for voice features. Please enable it in Settings.',
      );

      if (shouldOpenSettings) {
        await openAppSettings();
      }
    } else if (result.isDenied) {
      // User denied, show explanation
      _showDeniedSnackbar(
        context,
        'Microphone permission is required for voice features.',
      );
    }

    return false;
  }

  /// Request speech recognition permission (iOS only)
  ///
  /// On Android, speech recognition uses microphone permission.
  /// On iOS, a separate speech recognition permission is required.
  Future<bool> requestSpeechRecognitionPermission(BuildContext context) async {
    // Speech recognition permission is only needed on iOS
    if (!Platform.isIOS) {
      return true;
    }

    final status = await Permission.speech.status;

    if (status.isGranted) {
      return true;
    }

    if (status.isPermanentlyDenied) {
      if (!context.mounted) return false;
      final shouldOpenSettings = await _showSettingsDialog(
        context,
        title: 'Speech Recognition Permission Required',
        message:
            'Speech recognition access is required for voice-to-text features. Please enable it in Settings.',
      );

      if (shouldOpenSettings) {
        await openAppSettings();
      }
      return false;
    }

    final result = await Permission.speech.request();

    if (result.isGranted) {
      return true;
    }

    if (!context.mounted) return false;

    if (result.isPermanentlyDenied) {
      final shouldOpenSettings = await _showSettingsDialog(
        context,
        title: 'Speech Recognition Permission Required',
        message:
            'Speech recognition access is required for voice-to-text features. Please enable it in Settings.',
      );

      if (shouldOpenSettings) {
        await openAppSettings();
      }
    } else if (result.isDenied) {
      _showDeniedSnackbar(
        context,
        'Speech recognition permission is required for voice-to-text features.',
      );
    }

    return false;
  }

  /// Request all permissions needed for STT (Speech-to-Text) features
  ///
  /// On iOS: Requests both microphone and speech recognition permissions.
  /// On Android: Requests microphone permission only.
  Future<bool> requestSTTPermissions(BuildContext context) async {
    final micGranted = await requestMicrophonePermission(context);
    if (!micGranted) {
      return false;
    }

    // On iOS, also request speech recognition permission
    if (Platform.isIOS) {
      if (!context.mounted) return false;
      final speechGranted = await requestSpeechRecognitionPermission(context);
      return speechGranted;
    }

    return true;
  }

  /// Check if microphone permission is granted without requesting
  Future<bool> isMicrophonePermissionGranted() async {
    final status = await Permission.microphone.status;
    return status.isGranted;
  }

  /// Check if all STT permissions are granted without requesting
  Future<bool> areSTTPermissionsGranted() async {
    final micGranted = await isMicrophonePermissionGranted();
    if (!micGranted) {
      return false;
    }

    if (Platform.isIOS) {
      final speechStatus = await Permission.speech.status;
      return speechStatus.isGranted;
    }

    return true;
  }

  /// Show dialog to guide user to settings
  Future<bool> _showSettingsDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  /// Show snackbar for denied permission
  void _showDeniedSnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: const SnackBarAction(
          label: 'Settings',
          onPressed: openAppSettings,
        ),
      ),
    );
  }
}
