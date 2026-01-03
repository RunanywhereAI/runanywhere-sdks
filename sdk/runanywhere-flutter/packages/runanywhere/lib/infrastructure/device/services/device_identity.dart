import 'dart:async';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/foundation/security/keychain_manager.dart';
import 'package:uuid/uuid.dart';

/// Simple utility for device identity management.
///
/// Mirrors iOS `DeviceIdentity` from RunAnywhere SDK.
/// Provides persistent UUID that survives app reinstalls.
class DeviceIdentity {
  static final _logger = SDKLogger('DeviceIdentity');
  static const _uuid = Uuid();

  // Cached value for performance
  static String? _cachedUUID;

  /// Get a persistent device UUID that survives app reinstalls.
  /// Uses secure storage for persistence, generates new UUID if none exists.
  static Future<String> get persistentUUID async {
    // Return cached value if available
    if (_cachedUUID != null) {
      return _cachedUUID!;
    }

    // Strategy 1: Try to get from secure storage (survives app reinstalls)
    final storedUUID = await KeychainManager.shared.retrieveDeviceUUID();
    if (storedUUID != null && storedUUID.isNotEmpty) {
      _cachedUUID = storedUUID;
      return storedUUID;
    }

    // Strategy 2: Generate new UUID and store it
    final newUUID = _uuid.v4();
    try {
      await KeychainManager.shared.storeDeviceUUID(newUUID);
      _logger.debug('Generated and stored new device UUID');
    } catch (e) {
      _logger.warning('Failed to store device UUID: $e');
    }
    _cachedUUID = newUUID;
    return newUUID;
  }

  /// Validate if a device UUID is properly formatted.
  static bool validateUUID(String uuid) {
    return uuid.length == 36 && uuid.contains('-');
  }

  /// Clear cached UUID (for testing).
  static void clearCache() {
    _cachedUUID = null;
  }
}
