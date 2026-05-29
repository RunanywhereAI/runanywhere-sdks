// SPDX-License-Identifier: Apache-2.0
//
// dart_bridge_hardware.dart — thin FFI helpers for the commons hardware
// proto-byte ABI.

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/hardware_profile.pb.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/native/types/basic_types.dart';

/// C++ hardware profile bridge.
class DartBridgeHardware {
  DartBridgeHardware._();

  /// Query commons for the canonical generated hardware profile result.
  ///
  /// Throws [SDKException.featureNotAvailable] when the bundled native
  /// library does not expose the hardware ABI; throws
  /// [SDKException.internalError] when the commons call returns a non-success
  /// result. Mirrors Swift `try CppBridge.Hardware.getProfile() throws`.
  static HardwareProfileResult getProfile() {
    final DynamicLibrary lib;
    try {
      lib = PlatformLoader.loadCommons();
    } catch (e) {
      throw SDKException.featureNotAvailable(
        'hardware.getProfile: failed to load commons: $e',
      );
    }
    final getProfile = lib.lookupFunction<
        Int32 Function(Pointer<Pointer<Uint8>>, Pointer<IntPtr>),
        int Function(Pointer<Pointer<Uint8>>, Pointer<IntPtr>)>(
      'rac_hardware_profile_get',
    );
    final freeProfile = lib.lookupFunction<Void Function(Pointer<Uint8>),
        void Function(Pointer<Uint8>)>(
      'rac_hardware_profile_free',
    );

    final outBytes = calloc<Pointer<Uint8>>();
    final outSize = calloc<IntPtr>();
    try {
      final result = getProfile(outBytes, outSize);
      if (result != RAC_SUCCESS) {
        throw SDKException.internalError(
          'rac_hardware_profile_get returned rc=$result',
        );
      }
      if (outBytes.value == nullptr) {
        throw SDKException.internalError(
          'rac_hardware_profile_get returned null buffer',
        );
      }
      final bytes =
          Uint8List.fromList(outBytes.value.asTypedList(outSize.value));
      return HardwareProfileResult.fromBuffer(bytes);
    } finally {
      if (outBytes.value != nullptr) {
        freeProfile(outBytes.value);
      }
      calloc.free(outBytes);
      calloc.free(outSize);
    }
  }

  /// Set the commons accelerator preference for subsequent routing decisions.
  ///
  /// Throws [SDKException.featureNotAvailable] when the commons library is
  /// unavailable or the symbol is missing; throws [SDKException.internalError]
  /// when commons rejects the preference. Mirrors Swift
  /// `try CppBridge.Hardware.setAcceleratorPreference(_:) throws`.
  static void setAccelerationPreference(AccelerationPreference preference) {
    final DynamicLibrary lib;
    try {
      lib = PlatformLoader.loadCommons();
    } catch (e) {
      throw SDKException.featureNotAvailable(
        'hardware.setAcceleratorPreference: failed to load commons: $e',
      );
    }
    final int Function(int) setPreference;
    try {
      setPreference = lib.lookupFunction<Int32 Function(Int32), int Function(int)>(
        'rac_hardware_set_accelerator_preference',
      );
    } catch (e) {
      throw SDKException.featureNotAvailable(
        'rac_hardware_set_accelerator_preference',
      );
    }
    final result = setPreference(preference.value);
    if (result != RAC_SUCCESS) {
      throw SDKException.internalError(
        'rac_hardware_set_accelerator_preference returned rc=$result',
      );
    }
  }

  /// Query the commons accelerator list as the `accelerators` slice of a
  /// HardwareProfileResult.
  ///
  /// Mirrors Swift `CppBridge.Hardware.getAccelerators()`. Returns an empty
  /// list when the commons symbol is unavailable or the call fails.
  static List<AcceleratorInfo> getAccelerators() {
    try {
      final lib = PlatformLoader.loadCommons();
      final getAccel = lib.lookupFunction<
          Int32 Function(Pointer<Pointer<Uint8>>, Pointer<IntPtr>),
          int Function(Pointer<Pointer<Uint8>>, Pointer<IntPtr>)>(
        'rac_hardware_get_accelerators',
      );
      final freeProfile = lib.lookupFunction<Void Function(Pointer<Uint8>),
          void Function(Pointer<Uint8>)>(
        'rac_hardware_profile_free',
      );

      final outBytes = calloc<Pointer<Uint8>>();
      final outSize = calloc<IntPtr>();
      try {
        final result = getAccel(outBytes, outSize);
        if (result != RAC_SUCCESS || outBytes.value == nullptr) {
          return const <AcceleratorInfo>[];
        }
        final bytes =
            Uint8List.fromList(outBytes.value.asTypedList(outSize.value));
        final profile = HardwareProfileResult.fromBuffer(bytes);
        return List<AcceleratorInfo>.unmodifiable(profile.accelerators);
      } finally {
        if (outBytes.value != nullptr) {
          freeProfile(outBytes.value);
        }
        calloc.free(outBytes);
        calloc.free(outSize);
      }
    } catch (_) {
      return const <AcceleratorInfo>[];
    }
  }
}
