import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import '../../models/hardware/battery_info.dart';
import '../../models/hardware/device_capabilities.dart';
import '../../models/hardware/processor_info.dart';
import '../../models/hardware/hardware_acceleration.dart';

/// Thermal state enumeration.
/// Mirrors ProcessInfo.ThermalState from iOS/macOS Foundation.
enum ThermalState {
  nominal,
  fair,
  serious,
  critical;

  String get rawValue => name;

  static ThermalState fromRawValue(String value) {
    return ThermalState.values.firstWhere(
      (s) => s.name == value,
      orElse: () => ThermalState.nominal,
    );
  }
}

/// Protocol for hardware detection.
/// Matches iOS HardwareDetector from Infrastructure/Device/
abstract interface class HardwareDetector {
  /// Detect current device capabilities
  Future<DeviceCapabilities> detectCapabilities();

  /// Get available memory in bytes
  int getAvailableMemory();

  /// Get total memory in bytes
  int getTotalMemory();

  /// Check if Neural Engine is available
  bool hasNeuralEngine();

  /// Check if GPU is available
  bool hasGPU();

  /// Get processor information
  ProcessorInfo getProcessorInfo();

  /// Get thermal state
  ThermalState getThermalState();

  /// Get battery information (null if not available, e.g., on desktop)
  BatteryInfo? getBatteryInfo();
}

/// Default implementation of HardwareDetector using device_info_plus.
/// Matches iOS DeviceInfo from Infrastructure/Device/Models/Domain/DeviceInfo.swift
class DefaultHardwareDetector implements HardwareDetector {
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  // Cached device info
  IosDeviceInfo? _iosInfo;
  AndroidDeviceInfo? _androidInfo;
  bool _isInitialized = false;

  /// Initialize the detector and cache device info
  Future<void> _initialize() async {
    if (_isInitialized) return;

    if (Platform.isIOS) {
      _iosInfo = await _deviceInfo.iosInfo;
    } else if (Platform.isAndroid) {
      _androidInfo = await _deviceInfo.androidInfo;
    }
    _isInitialized = true;
  }

  @override
  Future<DeviceCapabilities> detectCapabilities() async {
    await _initialize();

    if (Platform.isIOS && _iosInfo != null) {
      return _buildIOSCapabilities(_iosInfo!);
    } else if (Platform.isAndroid && _androidInfo != null) {
      return _buildAndroidCapabilities(_androidInfo!);
    }

    // Fallback for unsupported platforms
    return DeviceCapabilities(
      totalMemory: getTotalMemory(),
      availableMemory: getAvailableMemory(),
      hasNeuralEngine: false,
      hasGPU: true,
      processorCount: Platform.numberOfProcessors,
      processorType: ProcessorType.unknown,
      supportedAccelerators: const [HardwareAcceleration.cpu],
      osVersion: const OperatingSystemVersion(majorVersion: 0, minorVersion: 0),
      modelIdentifier: 'Unknown',
    );
  }

  DeviceCapabilities _buildIOSCapabilities(IosDeviceInfo iosInfo) {
    final modelId = iosInfo.utsname.machine;
    final osVersion = _parseOSVersion(iosInfo.systemVersion);
    final processorType = _detectProcessorType(modelId);
    final hasNE = _hasNeuralEngineFromModel(modelId);

    return DeviceCapabilities(
      totalMemory: getTotalMemory(),
      availableMemory: getAvailableMemory(),
      hasNeuralEngine: hasNE,
      hasGPU: true,
      processorCount: Platform.numberOfProcessors,
      processorType: processorType,
      supportedAccelerators: _getIOSAccelerators(hasNE),
      osVersion: osVersion,
      modelIdentifier: modelId,
    );
  }

  DeviceCapabilities _buildAndroidCapabilities(AndroidDeviceInfo androidInfo) {
    final osVersion = OperatingSystemVersion(
      majorVersion: androidInfo.version.sdkInt,
      minorVersion: 0,
    );

    return DeviceCapabilities(
      totalMemory: getTotalMemory(),
      availableMemory: getAvailableMemory(),
      hasNeuralEngine: false, // Android uses NNAPI instead
      hasGPU: true,
      processorCount: Platform.numberOfProcessors,
      processorType: ProcessorType.arm,
      supportedAccelerators: const [
        HardwareAcceleration.cpu,
        HardwareAcceleration.gpu,
      ],
      osVersion: osVersion,
      modelIdentifier: androidInfo.model,
    );
  }

  @override
  int getAvailableMemory() {
    // ProcessInfo.processPhysicalMemory is not available in Dart
    // Return a percentage of total memory as estimation
    // In production, this would use platform channels or FFI
    final total = getTotalMemory();
    // Estimate 60% of total memory as available
    return (total * 0.6).toInt();
  }

  @override
  int getTotalMemory() {
    // Platform.localeName doesn't provide memory info
    // Use platform-specific estimation based on device type
    // Default to 4GB for mobile devices
    if (Platform.isIOS || Platform.isAndroid) {
      return 4 * 1024 * 1024 * 1024; // 4GB
    }
    return 8 * 1024 * 1024 * 1024; // 8GB for desktop
  }

  @override
  bool hasNeuralEngine() {
    if (!Platform.isIOS) return false;
    if (_iosInfo == null) return false;
    return _hasNeuralEngineFromModel(_iosInfo!.utsname.machine);
  }

  /// Check if device has Neural Engine based on model identifier
  /// Matches iOS DeviceInfo.mapModelIdentifierToName logic
  bool _hasNeuralEngineFromModel(String modelId) {
    // A11 Bionic (iPhone X) and later have Neural Engine
    // iPhone X: iPhone10,3, iPhone10,6
    // All devices after iPhone X have Neural Engine

    // iPhones with Neural Engine (iPhone X and later)
    if (modelId.startsWith('iPhone')) {
      final parts = modelId.replaceAll('iPhone', '').split(',');
      if (parts.isNotEmpty) {
        final major = int.tryParse(parts[0]) ?? 0;
        // iPhone10 and later have Neural Engine
        return major >= 10;
      }
    }

    // iPads with Neural Engine (A12 Bionic and later)
    if (modelId.startsWith('iPad')) {
      final parts = modelId.replaceAll('iPad', '').split(',');
      if (parts.isNotEmpty) {
        final major = int.tryParse(parts[0]) ?? 0;
        // iPad8 and later have Neural Engine (A12 Bionic)
        return major >= 8;
      }
    }

    // All Apple Silicon Macs have Neural Engine
    if (modelId.startsWith('Mac') ||
        modelId.startsWith('Macmini') ||
        modelId.startsWith('MacBook') ||
        modelId.startsWith('iMac')) {
      // Check for Apple Silicon identifiers
      if (modelId.contains('Mac14') ||
          modelId.contains('Mac15') ||
          modelId.contains('Mac16') ||
          modelId.contains('Mac13')) {
        return true;
      }
    }

    return false;
  }

  @override
  bool hasGPU() => true; // All modern devices have GPU

  @override
  ProcessorInfo getProcessorInfo() {
    String architecture;
    if (Platform.isIOS || Platform.isMacOS) {
      // Check if running on Apple Silicon
      architecture = 'arm64';
    } else if (Platform.isAndroid) {
      architecture = 'arm64';
    } else {
      architecture = 'x86_64';
    }

    final coreCount = Platform.numberOfProcessors;
    String chipName = 'Unknown';

    if (_iosInfo != null) {
      chipName = _getChipNameFromModel(_iosInfo!.utsname.machine);
    } else if (_androidInfo != null) {
      chipName = _androidInfo!.hardware;
    }

    return ProcessorInfo(
      chipName: chipName,
      coreCount: coreCount,
      performanceCores: (coreCount / 2).ceil(),
      efficiencyCores: (coreCount / 2).floor(),
      architecture: architecture,
      hasARM64E: Platform.isIOS,
      neuralEngineCores: hasNeuralEngine() ? 16 : 0,
    );
  }

  String _getChipNameFromModel(String modelId) {
    // Map model identifiers to chip names
    // Based on iOS DeviceInfo.mapModelIdentifierToName
    if (modelId.contains('iPhone17')) return 'Apple A18 Pro';
    if (modelId.contains('iPhone16')) return 'Apple A17 Pro';
    if (modelId.contains('iPhone15')) return 'Apple A16 Bionic';
    if (modelId.contains('iPhone14')) return 'Apple A15 Bionic';
    if (modelId.contains('iPhone13')) return 'Apple A14 Bionic';
    if (modelId.contains('iPhone12') || modelId.contains('iPhone11')) {
      return 'Apple A13 Bionic';
    }

    // iPad chips
    if (modelId.contains('iPad16') || modelId.contains('iPad17')) {
      return 'Apple M4';
    }
    if (modelId.contains('iPad14') || modelId.contains('iPad15')) {
      return 'Apple M2';
    }

    // Mac chips
    if (modelId.contains('Mac16')) return 'Apple M4';
    if (modelId.contains('Mac15')) return 'Apple M3';
    if (modelId.contains('Mac14')) return 'Apple M2';
    if (modelId.contains('Mac13')) return 'Apple M1';

    return 'Apple Silicon';
  }

  ProcessorType _detectProcessorType(String modelId) {
    // Detect processor type from model identifier
    if (modelId.contains('iPhone17') || modelId.contains('iPad17')) {
      return ProcessorType.a18Pro;
    }
    if (modelId.contains('iPhone16')) {
      return ProcessorType.a17Pro;
    }
    if (modelId.contains('iPhone15')) {
      return ProcessorType.a16Bionic;
    }
    if (modelId.contains('iPhone14') || modelId.contains('iPhone13')) {
      return ProcessorType.a15Bionic;
    }

    // Mac chips
    if (modelId.contains('Mac16')) return ProcessorType.m4;
    if (modelId.contains('Mac15')) return ProcessorType.m3;
    if (modelId.contains('Mac14')) return ProcessorType.m2;
    if (modelId.contains('Mac13')) return ProcessorType.m1;

    return ProcessorType.arm;
  }

  @override
  ThermalState getThermalState() {
    // Thermal state requires platform-specific APIs
    // Default to nominal - would need platform channels for accurate reading
    return ThermalState.nominal;
  }

  @override
  BatteryInfo? getBatteryInfo() {
    // Battery info requires platform-specific APIs
    // Would need battery_plus package or platform channels
    return null;
  }

  List<HardwareAcceleration> _getIOSAccelerators(bool hasNeuralEngine) {
    final accelerators = <HardwareAcceleration>[
      HardwareAcceleration.cpu,
      HardwareAcceleration.gpu,
      HardwareAcceleration.metal,
    ];

    if (hasNeuralEngine) {
      accelerators.add(HardwareAcceleration.coreML);
    }

    return accelerators;
  }

  OperatingSystemVersion _parseOSVersion(String versionString) {
    final parts = versionString.split('.');
    return OperatingSystemVersion(
      majorVersion: int.tryParse(parts.isNotEmpty ? parts[0] : '0') ?? 0,
      minorVersion: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
      patchVersion: int.tryParse(parts.length > 2 ? parts[2] : '0') ?? 0,
    );
  }
}
