import 'dart:async';

import '../models/device_info_data.dart';

/// Device information repository protocol for specialized device operations
/// DeviceInfoRepositoryImpl will implement both this AND Repository<DeviceInfoData>
/// Matches iOS DeviceInfoRepository from DeviceInfoRepository.swift
abstract class DeviceInfoRepository {
  /// Fetch current device information
  Future<DeviceInfoData> fetchCurrentDeviceInfo();

  /// Update device information
  Future<void> updateDeviceInfo(DeviceInfoData deviceInfo);

  /// Get stored device information
  Future<DeviceInfoData?> getStoredDeviceInfo();

  /// Refresh device information
  Future<DeviceInfoData> refreshDeviceInfo();
}
