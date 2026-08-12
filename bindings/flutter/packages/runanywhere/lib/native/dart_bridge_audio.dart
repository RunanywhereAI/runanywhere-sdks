// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/platform_loader.dart';

/// Audio conversion bridge over the commons C ABI
/// (`rac/core/rac_audio_utils.h`).
///
/// Matches Swift `CppBridge`'s `convertPCMToWAV` path
/// (`RunAnywhere+TTS.swift:118-127` calls `rac_audio_float32_to_wav`), so the
/// WAV container the SDK plays/uploads is byte-identical across platforms.
class DartBridgeAudio {
  DartBridgeAudio._();

  static final _logger = SDKLogger('DartBridge.Audio');

  static final DynamicLibrary _lib = PlatformLoader.loadCommons();

  static final int Function(
    Pointer<Void>,
    int,
    int,
    Pointer<Pointer<Void>>,
    Pointer<Size>,
  ) _float32ToWav = _lib.lookupFunction<
      Int32 Function(
        Pointer<Void>,
        Size,
        Int32,
        Pointer<Pointer<Void>>,
        Pointer<Size>,
      ),
      int Function(
        Pointer<Void>,
        int,
        int,
        Pointer<Pointer<Void>>,
        Pointer<Size>,
      )>('rac_audio_float32_to_wav');

  static final int Function(
    Pointer<Void>,
    int,
    int,
    Pointer<Pointer<Void>>,
    Pointer<Size>,
  ) _int16ToWav = _lib.lookupFunction<
      Int32 Function(
        Pointer<Void>,
        Size,
        Int32,
        Pointer<Pointer<Void>>,
        Pointer<Size>,
      ),
      int Function(
        Pointer<Void>,
        int,
        int,
        Pointer<Pointer<Void>>,
        Pointer<Size>,
      )>('rac_audio_int16_to_wav');

  static final void Function(Pointer<Void>) _racFree = _lib.lookupFunction<
      Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('rac_free');

  /// Wrap Float32 PCM samples (`[-1.0, 1.0]`, little-endian bytes) in a WAV
  /// container via `rac_audio_float32_to_wav`. Returns null on failure.
  static Uint8List? float32ToWav(Uint8List pcmBytes, int sampleRate) {
    return _toWav(_float32ToWav, 'rac_audio_float32_to_wav', pcmBytes, sampleRate);
  }

  /// Wrap Int16 PCM samples (little-endian bytes) in a WAV container via
  /// `rac_audio_int16_to_wav`. Returns null on failure.
  static Uint8List? int16ToWav(Uint8List pcmBytes, int sampleRate) {
    return _toWav(_int16ToWav, 'rac_audio_int16_to_wav', pcmBytes, sampleRate);
  }

  static Uint8List? _toWav(
    int Function(
      Pointer<Void>,
      int,
      int,
      Pointer<Pointer<Void>>,
      Pointer<Size>,
    ) convert,
    String symbol,
    Uint8List pcmBytes,
    int sampleRate,
  ) {
    if (pcmBytes.isEmpty) return null;
    final pcmPtr = calloc<Uint8>(pcmBytes.length);
    final outData = calloc<Pointer<Void>>();
    final outSize = calloc<Size>();
    try {
      pcmPtr.asTypedList(pcmBytes.length).setAll(0, pcmBytes);
      final rc = convert(
        pcmPtr.cast<Void>(),
        pcmBytes.length,
        sampleRate,
        outData,
        outSize,
      );
      if (rc != 0 || outData.value == nullptr || outSize.value == 0) {
        _logger.error('$symbol failed: rc=$rc');
        return null;
      }
      // Copy out before releasing the commons-owned buffer with rac_free.
      final wav = Uint8List.fromList(
        outData.value.cast<Uint8>().asTypedList(outSize.value),
      );
      _racFree(outData.value);
      return wav;
    } catch (e) {
      _logger.error('$symbol threw: $e');
      return null;
    } finally {
      calloc.free(pcmPtr);
      calloc.free(outData);
      calloc.free(outSize);
    }
  }
}
