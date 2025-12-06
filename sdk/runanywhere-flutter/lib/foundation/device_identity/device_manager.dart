import 'dart:async';
import 'dart:io';

import 'package:uuid/uuid.dart';
import '../security/keychain_manager.dart';

/// Device identity manager
class DeviceManager {
  static final DeviceManager shared = DeviceManager._();

  DeviceManager._();

  final _uuid = const Uuid();
  String? _cachedDeviceId;

  /// Get or generate device identifier
  Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) {
      return _cachedDeviceId!;
    }

    // Try to retrieve from secure storage
    final storedId = await KeychainManager.shared.retrieveDeviceUUID();
    if (storedId != null && storedId.isNotEmpty) {
      _cachedDeviceId = storedId;
      return storedId;
    }

    // Generate new device ID
    final deviceId = _generateDeviceIdentifier();
    await KeychainManager.shared.storeDeviceUUID(deviceId);
    _cachedDeviceId = deviceId;
    return deviceId;
  }

  /// Generate a unique device identifier
  String _generateDeviceIdentifier() {
    // Use platform-specific identifier if available
    if (Platform.isAndroid) {
      // On Android, we could use AndroidId (requires platform channel)
      // For now, generate UUID
      return 'android-${_uuid.v4()}';
    } else if (Platform.isIOS) {
      // On iOS, we could use identifierForVendor (requires platform channel)
      // For now, generate UUID
      return 'ios-${_uuid.v4()}';
    }

    // Fallback to random UUID
    return _uuid.v4();
  }

  /// Clear cached device ID
  void clearCache() {
    _cachedDeviceId = null;
  }
}
