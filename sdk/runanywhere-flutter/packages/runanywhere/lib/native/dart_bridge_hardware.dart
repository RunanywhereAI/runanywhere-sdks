// SPDX-License-Identifier: Apache-2.0
//
// dart_bridge_hardware.dart — thin FFI helpers for the commons hardware
// proto-byte ABI.

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/generated/hardware_profile.pb.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/native/types/basic_types.dart';

/// C++ hardware profile bridge.
class DartBridgeHardware {
  DartBridgeHardware._();

  /// Query commons for the canonical generated hardware profile result.
  ///
  /// Returns null when the bundled native library does not expose the
  /// hardware ABI yet, allowing callers to keep a platform fallback during
  /// the migration.
  static HardwareProfileResult? getProfile() {
    try {
      final lib = PlatformLoader.loadCommons();
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
        if (result != RAC_SUCCESS || outBytes.value == nullptr) {
          return null;
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
    } catch (_) {
      return null;
    }
  }

  /// Set the commons accelerator preference for subsequent routing decisions.
  static bool setAcceleratorPreference(AcceleratorPreference preference) {
    try {
      final lib = PlatformLoader.loadCommons();
      final setPreference =
          lib.lookupFunction<Int32 Function(Int32), int Function(int)>(
        'rac_hardware_set_accelerator_preference',
      );
      return setPreference(preference.value) == RAC_SUCCESS;
    } catch (_) {
      return false;
    }
  }
}
