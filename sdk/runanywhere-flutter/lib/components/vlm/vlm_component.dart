import 'dart:async';
import 'dart:typed_data';

import '../../core/components/base_component.dart';
import '../../core/types/sdk_component.dart';
import '../../core/protocols/component/component_configuration.dart';
import '../../core/module_registry.dart' as core show ModuleRegistry, VLMService;
import '../../public/events/component_initialization_event.dart';

export '../../core/module_registry.dart' show VLMService;

// MARK: - VLM Configuration

/// Image preprocessing mode
enum ImagePreprocessing {
  none,
  normalize,
  centerCrop,
  resize,
}

/// Image format
enum ImageFormat {
  jpeg,
  png,
  heic,
  raw,
}

/// Configuration for VLM component
/// Matches iOS VLMConfiguration from VLMComponent.swift
class VLMConfiguration implements ComponentConfiguration {
  /// Model ID
  final String? modelId;

  // VLM-specific parameters
  /// Square image size (e.g., 224, 384, 512)
  final int imageSize;

  /// Maximum image tokens
  final int maxImageTokens;

  /// Context length
  final int contextLength;

  /// Whether to use GPU if available
  final bool useGPUIfAvailable;

  /// Image preprocessing mode
  final ImagePreprocessing imagePreprocessing;

  VLMConfiguration({
    this.modelId,
    this.imageSize = 384,
    this.maxImageTokens = 576,
    this.contextLength = 2048,
    this.useGPUIfAvailable = true,
    this.imagePreprocessing = ImagePreprocessing.normalize,
  });

  @override
  void validate() {
    const validImageSizes = [224, 256, 384, 512, 768, 1024];
    if (!validImageSizes.contains(imageSize)) {
      throw ArgumentError('Image size must be one of: $validImageSizes');
    }
    if (maxImageTokens <= 0 || maxImageTokens > 2048) {
      throw ArgumentError('Max image tokens must be between 1 and 2048');
    }
    if (contextLength <= 0 || contextLength > 32768) {
      throw ArgumentError('Context length must be between 1 and 32768');
    }
  }
}

// MARK: - VLM Input/Output Models

/// Input for Vision Language Model
/// Matches iOS VLMInput from VLMComponent.swift
class VLMInput implements ComponentInput {
  /// Image data to process
  final Uint8List image;

  /// Text prompt or question about the image
  final String prompt;

  /// Image format
  final ImageFormat imageFormat;

  /// Optional processing options
  final VLMOptions? options;

  VLMInput({
    required this.image,
    required this.prompt,
    this.imageFormat = ImageFormat.jpeg,
    this.options,
  });

  @override
  void validate() {
    if (image.isEmpty) {
      throw ArgumentError('Image data cannot be empty');
    }
    if (prompt.isEmpty) {
      throw ArgumentError('Prompt cannot be empty');
    }
  }
}

/// Output from Vision Language Model
/// Matches iOS VLMOutput from VLMComponent.swift
class VLMOutput implements ComponentOutput {
  /// Generated text response
  final String text;

  /// Detected objects in the image
  final List<DetectedObject>? detectedObjects;

  /// Regions of interest
  final List<ImageRegion>? regions;

  /// Overall confidence score
  final double confidence;

  /// Processing metadata
  final VLMMetadata metadata;

  /// Timestamp (required by ComponentOutput)
  @override
  final DateTime timestamp;

  VLMOutput({
    required this.text,
    this.detectedObjects,
    this.regions,
    required this.confidence,
    required this.metadata,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// VLM processing metadata
class VLMMetadata {
  final String modelId;
  final double processingTime;
  final Size imageSize;
  final int tokenCount;

  VLMMetadata({
    required this.modelId,
    required this.processingTime,
    required this.imageSize,
    required this.tokenCount,
  });
}

/// Size type for image dimensions
class Size {
  final double width;
  final double height;

  const Size(this.width, this.height);
}

/// Detected object in image
class DetectedObject {
  final String label;
  final double confidence;
  final BoundingBox boundingBox;

  DetectedObject({
    required this.label,
    required this.confidence,
    required this.boundingBox,
  });
}

/// Image region of interest
class ImageRegion {
  final String id;
  final String description;
  final BoundingBox boundingBox;
  final double importance;

  ImageRegion({
    required this.id,
    required this.description,
    required this.boundingBox,
    required this.importance,
  });
}

/// Bounding box for object detection
class BoundingBox {
  final double x;
  final double y;
  final double width;
  final double height;

  const BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}

/// Options for VLM processing
class VLMOptions {
  final int imageSize;
  final int maxTokens;
  final double temperature;
  final double? topP;

  VLMOptions({
    this.imageSize = 384,
    this.maxTokens = 100,
    this.temperature = 0.7,
    this.topP,
  });
}

/// Errors for VLM services
class VLMServiceError implements Exception {
  final String message;
  final VLMErrorType type;

  VLMServiceError(this.message, this.type);

  @override
  String toString() => 'VLMServiceError: $message';
}

enum VLMErrorType {
  notInitialized,
  modelNotFound,
  processingFailed,
  imageInvalid,
  promptInvalid,
}

// MARK: - VLM Component

/// VLM (Vision Language Model) Component
/// Matches iOS VLMComponent from VLMComponent.swift
class VLMComponent extends BaseComponent<core.VLMService> {
  @override
  SDKComponent get componentType => SDKComponent.vlm;

  final VLMConfiguration vlmConfig;
  bool _isModelLoaded = false;
  String? _modelPath;

  VLMComponent({
    required this.vlmConfig,
    super.serviceContainer,
  }) : super(configuration: vlmConfig);

  @override
  Future<core.VLMService> createService() async {
    // Emit model checking event
    eventBus.publish(ComponentInitializationEvent.componentChecking(
      component: componentType,
      modelId: vlmConfig.modelId,
    ));

    // Check if model needs downloading
    // Model download support will be added when ML-based providers are available
    if (vlmConfig.modelId != null) {
      _modelPath = vlmConfig.modelId;

      final needsDownload = await _checkNeedsDownload(vlmConfig.modelId!);
      if (needsDownload) {
        // Emit download required event
        eventBus.publish(ComponentInitializationEvent.componentDownloadRequired(
          component: componentType,
          modelId: vlmConfig.modelId!,
          sizeBytes: 2000000000, // 2GB example for VLM models
        ));

        // Download model
        await _downloadModel(vlmConfig.modelId!);
      }
    }

    // Try to get a registered VLM provider
    final provider =
        core.ModuleRegistry.shared.vlmProvider(modelId: vlmConfig.modelId);
    if (provider == null) {
      throw VLMServiceError(
        'VLM service requires an external implementation. '
        'Please add a vision model provider as a dependency and register it '
        'with ModuleRegistry.shared.registerVLM(provider).',
        VLMErrorType.notInitialized,
      );
    }

    final service = await provider.createVLMService(vlmConfig);
    await service.initialize(modelPath: _modelPath);
    _isModelLoaded = true;

    return service;
  }

  @override
  Future<void> initializeService() async {
    // Track model loading state
    eventBus.publish(ComponentInitializationEvent.componentInitializing(
      component: componentType,
      modelId: vlmConfig.modelId,
    ));
  }

  /// Check if model needs to be downloaded
  /// Currently returns false - will be implemented when ML providers are available
  Future<bool> _checkNeedsDownload(String modelId) async {
    // In real implementation, check if model file exists on disk
    return false;
  }

  Future<void> _downloadModel(String modelId) async {
    // Emit download started event
    eventBus.publish(ComponentInitializationEvent.componentDownloadStarted(
      component: componentType,
      modelId: modelId,
    ));

    // Simulate download with progress (VLM models are typically large)
    for (double progress = 0.0; progress <= 1.0; progress += 0.05) {
      eventBus.publish(ComponentInitializationEvent.componentDownloadProgress(
        component: componentType,
        modelId: modelId,
        progress: progress,
      ));
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Emit download completed event
    eventBus.publish(ComponentInitializationEvent.componentDownloadCompleted(
      component: componentType,
      modelId: modelId,
    ));
  }

  @override
  Future<void> performCleanup() async {
    await service?.cleanup();
    _isModelLoaded = false;
    _modelPath = null;
  }

  // MARK: - Public API

  /// Analyze an image with a text prompt
  Future<VLMOutput> analyze(
    Uint8List image,
    String prompt, {
    ImageFormat format = ImageFormat.jpeg,
  }) async {
    ensureReady();

    final input = VLMInput(image: image, prompt: prompt, imageFormat: format);
    return process(input);
  }

  /// Describe an image
  Future<VLMOutput> describeImage(
    Uint8List image, {
    ImageFormat format = ImageFormat.jpeg,
  }) async {
    ensureReady();

    final input = VLMInput(
      image: image,
      prompt: 'Describe this image in detail',
      imageFormat: format,
    );
    return process(input);
  }

  /// Answer a question about an image
  Future<VLMOutput> answerQuestion(
    Uint8List image,
    String question, {
    ImageFormat format = ImageFormat.jpeg,
  }) async {
    ensureReady();

    final input = VLMInput(image: image, prompt: question, imageFormat: format);
    return process(input);
  }

  /// Detect objects in an image
  Future<List<DetectedObject>> detectObjects(
    Uint8List image, {
    ImageFormat format = ImageFormat.jpeg,
  }) async {
    ensureReady();

    final input = VLMInput(
      image: image,
      prompt: 'Detect and list all objects in this image',
      imageFormat: format,
    );
    final output = await process(input);
    return output.detectedObjects ?? [];
  }

  /// Process VLM input
  Future<VLMOutput> process(VLMInput input) async {
    ensureReady();

    final vlmService = service;
    if (vlmService == null) {
      throw VLMServiceError(
        'VLM service not available',
        VLMErrorType.notInitialized,
      );
    }

    // Validate input
    input.validate();

    // Preprocess image if needed
    final processedImage = _preprocessImage(input.image, input.imageFormat);

    // Track processing time
    final startTime = DateTime.now();

    // Process image
    final result = await vlmService.process(
      prompt: input.prompt,
      imageData: processedImage.toList(),
    );

    final processingTime =
        DateTime.now().difference(startTime).inMilliseconds / 1000.0;

    // Estimate image size (mock - real implementation would extract from image data)
    final imageSize = Size(
      vlmConfig.imageSize.toDouble(),
      vlmConfig.imageSize.toDouble(),
    );

    final metadata = VLMMetadata(
      modelId: vlmConfig.modelId ?? 'unknown',
      processingTime: processingTime,
      imageSize: imageSize,
      tokenCount: (result as dynamic).text?.length ~/ 4 ?? 0,
    );

    return VLMOutput(
      text: (result as dynamic).text ?? '',
      detectedObjects: null, // Would be populated from actual VLM result
      regions: null,
      confidence: 0.9,
      metadata: metadata,
    );
  }

  /// Get service for compatibility
  core.VLMService? getService() {
    return service;
  }

  /// Check if model is loaded
  bool get isModelLoaded => _isModelLoaded;

  // MARK: - Private Helpers

  Uint8List _preprocessImage(Uint8List imageData, ImageFormat format) {
    // Apply preprocessing based on configuration
    switch (vlmConfig.imagePreprocessing) {
      case ImagePreprocessing.none:
        return imageData;
      case ImagePreprocessing.normalize:
        // Normalize image pixels to [0, 1] or [-1, 1]
        // This would require image processing library
        return imageData;
      case ImagePreprocessing.centerCrop:
        // Center crop to target size
        // This would require image processing library
        return imageData;
      case ImagePreprocessing.resize:
        // Resize to target dimensions
        // This would require image processing library
        return imageData;
    }
  }
}
