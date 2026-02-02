import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../diffusion_types.dart';

/// FFI bindings for the Diffusion native library
class DiffusionBindings {
  late final DynamicLibrary _lib;
  bool _isLoaded = false;
  Pointer<Void> _handle = nullptr;

  DiffusionBindings() {
    try {
      _lib = _loadLibrary();
      _isLoaded = true;
      _bindFunctions();
    } catch (e) {
      print('[Diffusion] Warning: Native library not loaded: $e');
      _isLoaded = false;
    }
  }

  static DynamicLibrary _loadLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('librac_backend_diffusion_jni.so');
    } else if (Platform.isIOS) {
      // iOS uses statically linked libraries
      return DynamicLibrary.process();
    } else if (Platform.isMacOS) {
      return DynamicLibrary.process();
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('rac_backend_diffusion.dll');
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('librac_backend_diffusion.so');
    }
    throw UnsupportedError('Platform not supported');
  }

  // Function pointers
  late final RacDiffusionRegisterDart _register;
  late final RacDiffusionComponentCreateDart _componentCreate;
  late final RacDiffusionComponentDestroyDart _componentDestroy;
  late final RacDiffusionComponentConfigureDart _componentConfigure;
  late final RacDiffusionComponentLoadModelDart _componentLoadModel;
  late final RacDiffusionComponentUnloadDart _componentUnload;
  late final RacDiffusionComponentIsLoadedDart _componentIsLoaded;
  late final RacDiffusionComponentGenerateDart _componentGenerate;
  late final RacDiffusionComponentCancelDart _componentCancel;
  late final RacDiffusionResultFreeDart _resultFree;

  void _bindFunctions() {
    if (!_isLoaded) return;

    _register = _lib
        .lookup<NativeFunction<RacDiffusionRegisterNative>>(
            'rac_backend_diffusion_onnx_register')
        .asFunction();

    _componentCreate = _lib
        .lookup<NativeFunction<RacDiffusionComponentCreateNative>>(
            'rac_diffusion_component_create')
        .asFunction();

    _componentDestroy = _lib
        .lookup<NativeFunction<RacDiffusionComponentDestroyNative>>(
            'rac_diffusion_component_destroy')
        .asFunction();

    _componentConfigure = _lib
        .lookup<NativeFunction<RacDiffusionComponentConfigureNative>>(
            'rac_diffusion_component_configure_json')
        .asFunction();

    _componentLoadModel = _lib
        .lookup<NativeFunction<RacDiffusionComponentLoadModelNative>>(
            'rac_diffusion_component_load')
        .asFunction();

    _componentUnload = _lib
        .lookup<NativeFunction<RacDiffusionComponentUnloadNative>>(
            'rac_diffusion_component_unload')
        .asFunction();

    _componentIsLoaded = _lib
        .lookup<NativeFunction<RacDiffusionComponentIsLoadedNative>>(
            'rac_diffusion_component_is_loaded')
        .asFunction();

    _componentGenerate = _lib
        .lookup<NativeFunction<RacDiffusionComponentGenerateNative>>(
            'rac_diffusion_component_generate_json')
        .asFunction();

    _componentCancel = _lib
        .lookup<NativeFunction<RacDiffusionComponentCancelNative>>(
            'rac_diffusion_component_cancel')
        .asFunction();

    _resultFree = _lib
        .lookup<NativeFunction<RacDiffusionResultFreeNative>>(
            'rac_string_free')
        .asFunction();
  }

  /// Check if native library is loaded
  bool get isLoaded => _isLoaded;

  /// Check if model is loaded
  bool get isModelLoaded {
    if (!_isLoaded || _handle == nullptr) return false;
    return _componentIsLoaded(_handle) == 1;
  }

  /// Register the Diffusion backend
  int register() {
    if (!_isLoaded) return -1;
    return _register();
  }

  /// Create the component if needed
  void _ensureComponent() {
    if (_handle == nullptr) {
      final handlePtr = calloc<Pointer<Void>>();
      final result = _componentCreate(handlePtr);
      if (result == 0) {
        _handle = handlePtr.value;
      }
      calloc.free(handlePtr);
    }
  }

  /// Configure the diffusion component
  int configure({
    required int modelVariant,
    required bool enableSafetyChecker,
    required bool reduceMemory,
    required int tokenizerSource,
    String? tokenizerCustomURL,
  }) {
    if (!_isLoaded) return -1;
    _ensureComponent();
    if (_handle == nullptr) return -1;

    final config = {
      'model_variant': modelVariant,
      'enable_safety_checker': enableSafetyChecker,
      'reduce_memory': reduceMemory,
      'tokenizer_source': tokenizerSource,
      if (tokenizerCustomURL != null) 'tokenizer_custom_url': tokenizerCustomURL,
    };

    final configJson = jsonEncode(config);
    final configPtr = configJson.toNativeUtf8();

    try {
      return _componentConfigure(_handle, configPtr);
    } finally {
      calloc.free(configPtr);
    }
  }

  /// Load a diffusion model
  int loadModel({
    required String path,
    required String modelId,
    String? modelName,
  }) {
    if (!_isLoaded) return -1;
    _ensureComponent();
    if (_handle == nullptr) return -1;

    final pathPtr = path.toNativeUtf8();
    final modelIdPtr = modelId.toNativeUtf8();
    final modelNamePtr = modelName?.toNativeUtf8() ?? nullptr;

    try {
      return _componentLoadModel(_handle, pathPtr, modelIdPtr, modelNamePtr);
    } finally {
      calloc.free(pathPtr);
      calloc.free(modelIdPtr);
      if (modelNamePtr != nullptr) {
        calloc.free(modelNamePtr);
      }
    }
  }

  /// Unload the current model
  void unloadModel() {
    if (!_isLoaded || _handle == nullptr) return;
    _componentUnload(_handle);
  }

  /// Generate an image
  Future<DiffusionResult> generate(DiffusionGenerationOptions options) async {
    if (!_isLoaded) {
      throw Exception('Native library not loaded');
    }
    if (_handle == nullptr) {
      throw Exception('Diffusion component not initialized');
    }

    final optionsMap = {
      'prompt': options.prompt,
      'negative_prompt': options.negativePrompt,
      'width': options.width,
      'height': options.height,
      'steps': options.steps,
      'guidance_scale': options.guidanceScale,
      'seed': options.seed,
      'scheduler': options.scheduler.cValue,
      'mode': options.mode.cValue,
      'denoise_strength': options.denoiseStrength,
      'report_intermediate_images': options.reportIntermediateImages,
      'progress_stride': options.progressStride,
    };

    // Add input image if present (for img2img/inpainting)
    if (options.inputImage != null) {
      optionsMap['input_image_base64'] = base64Encode(options.inputImage!);
    }
    if (options.maskImage != null) {
      optionsMap['mask_image_base64'] = base64Encode(options.maskImage!);
    }

    final optionsJson = jsonEncode(optionsMap);
    final optionsPtr = optionsJson.toNativeUtf8();

    try {
      final resultPtr = _componentGenerate(_handle, optionsPtr);
      if (resultPtr == nullptr) {
        throw Exception('Generation failed: null result');
      }

      final resultJson = resultPtr.toDartString();
      _resultFree(resultPtr);

      return _parseResult(resultJson);
    } finally {
      calloc.free(optionsPtr);
    }
  }

  /// Parse JSON result into DiffusionResult
  DiffusionResult _parseResult(String resultJson) {
    final result = jsonDecode(resultJson) as Map<String, dynamic>;

    Uint8List? imageData;
    if (result.containsKey('image_base64')) {
      imageData = base64Decode(result['image_base64'] as String);
    }

    return DiffusionResult(
      imageData: imageData ?? Uint8List(0),
      width: result['width'] as int? ?? 0,
      height: result['height'] as int? ?? 0,
      seedUsed: result['seed_used'] as int? ?? 0,
      generationTimeMs: result['generation_time_ms'] as int? ?? 0,
    );
  }

  /// Cancel ongoing generation
  void cancel() {
    if (!_isLoaded || _handle == nullptr) return;
    _componentCancel(_handle);
  }

  /// Destroy and cleanup
  void dispose() {
    if (_handle != nullptr) {
      _componentDestroy(_handle);
      _handle = nullptr;
    }
  }
}

// FFI type definitions
typedef RacDiffusionRegisterNative = Int32 Function();
typedef RacDiffusionRegisterDart = int Function();

typedef RacDiffusionComponentCreateNative = Int32 Function(Pointer<Pointer<Void>>);
typedef RacDiffusionComponentCreateDart = int Function(Pointer<Pointer<Void>>);

typedef RacDiffusionComponentDestroyNative = Void Function(Pointer<Void>);
typedef RacDiffusionComponentDestroyDart = void Function(Pointer<Void>);

typedef RacDiffusionComponentConfigureNative = Int32 Function(
    Pointer<Void>, Pointer<Utf8>);
typedef RacDiffusionComponentConfigureDart = int Function(
    Pointer<Void>, Pointer<Utf8>);

typedef RacDiffusionComponentLoadModelNative = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef RacDiffusionComponentLoadModelDart = int Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);

typedef RacDiffusionComponentUnloadNative = Void Function(Pointer<Void>);
typedef RacDiffusionComponentUnloadDart = void Function(Pointer<Void>);

typedef RacDiffusionComponentIsLoadedNative = Int32 Function(Pointer<Void>);
typedef RacDiffusionComponentIsLoadedDart = int Function(Pointer<Void>);

typedef RacDiffusionComponentGenerateNative = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>);
typedef RacDiffusionComponentGenerateDart = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>);

typedef RacDiffusionComponentCancelNative = Void Function(Pointer<Void>);
typedef RacDiffusionComponentCancelDart = void Function(Pointer<Void>);

typedef RacDiffusionResultFreeNative = Void Function(Pointer<Utf8>);
typedef RacDiffusionResultFreeDart = void Function(Pointer<Utf8>);
