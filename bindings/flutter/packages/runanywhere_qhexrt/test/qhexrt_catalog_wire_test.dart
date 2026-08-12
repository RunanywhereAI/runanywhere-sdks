import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/generated/hardware_profile.pb.dart';
import 'package:runanywhere/generated/model_types.pb.dart';
import 'package:runanywhere_qhexrt/native/qhexrt_bindings.dart';

void main() {
  test('model definition crosses FFI as canonical proto bytes', () {
    final request = RegisterModelFromUrlRequest(
      id: 'catalog-contract-model',
      name: 'Catalog Contract Model',
      url:
          'https://huggingface.co/runanywhere/catalog-contract-model_HNPU/model.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
      source: ModelSource.MODEL_SOURCE_REMOTE,
    );

    final bytes = QhexrtCatalogWire.encodeRequest(request);

    expect(
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
      '0a4968747470733a2f2f68756767696e67666163652e636f2f72756e616e7977686572652f636174616c6f672d636f6e74726163742d6d6f64656c5f484e50552f6d6f64656c2e6a736f6e1216436174616c6f6720436f6e7472616374204d6f64656c1818200128016a16636174616c6f672d636f6e74726163742d6d6f64656c',
    );
    expect(RegisterModelFromUrlRequest.fromBuffer(bytes), request);
  });

  final hostLibrary = Platform.environment['QHEXRT_HOST_LIBRARY'];
  test(
    'Flutter wrapper calls native device-aware registration ABI',
    () {
      final bindings = QhexrtBindings.fromDynamicLibrary(
        DynamicLibrary.open(hostLibrary!),
      );
      expect(
        bindings.modelSupportsArchitecture(
          'qwen3_5_0_8b',
          HexagonArch.HEXAGON_ARCH_V81,
        ),
        isTrue,
      );
      expect(bindings.modelRequiresHfAuth('qwen3_0_6b'), isTrue);
      expect(bindings.modelRequiresHfAuth('qwen3_5_0_8b'), isFalse);
      final request = RegisterModelFromUrlRequest(
        id: 'flutter-qhexrt-native-contract',
        name: 'Flutter QHexRT Native Contract',
        url: 'https://cdn.example.test/model.json',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
        category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
        source: ModelSource.MODEL_SOURCE_REMOTE,
      );

      final registered = bindings.registerModelForDevice(request);

      // A host has no Qualcomm NPU. The important contract is that the Dart
      // wrapper called the real exported symbol and decoded its normal
      // ineligible result instead of duplicating chip policy in Dart.
      expect(registered, isNull);
    },
    skip: hostLibrary == null
        ? 'Set QHEXRT_HOST_LIBRARY to a host-built QHexRT dylib/so'
        : false,
  );
}
