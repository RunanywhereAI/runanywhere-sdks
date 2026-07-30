// SPDX-License-Identifier: Apache-2.0
//
// `RunAnywhere.images`, `RunAnywhere.diarization`, `RunAnywhere.segmentation`.

import 'dart:async';
import 'dart:typed_data';

import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/diarization.pb.dart'
    show DiarizationRequest;
import 'package:runanywhere/generated/diffusion_options.pbenum.dart'
    show DiffusionStreamEventKind;
import 'package:runanywhere/generated/segmentation.pb.dart'
    show SegmentationRequest;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_diarization.dart';
import 'package:runanywhere/native/dart_bridge_segmentation.dart';
import 'package:runanywhere/public/api/internal/model_gate.dart';
import 'package:runanywhere/public/api/types/events.dart';
import 'package:runanywhere/public/api/types/inputs.dart';
import 'package:runanywhere/public/api/types/options.dart';
import 'package:runanywhere/public/api/types/results.dart';
import 'package:runanywhere/public/capabilities/runanywhere_diffusion.dart';

/// Diffusion image generation.
class ImagesApi {
  /// Bind the namespace. Reach it through `RunAnywhere.images`.
  const ImagesApi();

  /// Generate an image for [prompt].
  ///
  /// ```dart
  /// final r = await RunAnywhere.images.generate('a red bicycle');
  /// showImage(r.images.first.bytes);
  /// ```
  ///
  /// Throws [SDKException] when no diffusion model is loadable or the platform
  /// has no diffusion backend.
  Future<ImageResult> generate(
    String prompt, {
    ImageOptions? options,
  }) async {
    final effective = options ?? ImageOptions();
    await ModelGate.ensureLoaded(
      modelId: null,
      category: ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION,
    );
    final result = await RunAnywhereDiffusion.shared.generateImage(
      effective.toProto(prompt),
    );
    if (result.errorMessage.isNotEmpty) {
      throw SDKException.processingFailed(result.errorMessage);
    }
    return ImageResult.fromProto(result, steps: effective.steps);
  }

  /// Generate an image for [prompt], reporting progress per denoising step.
  ///
  /// Throws [SDKException] into the consumer when generation fails.
  Stream<ImageEvent> generateStream(
    String prompt, {
    ImageOptions? options,
  }) async* {
    final effective = options ?? ImageOptions();
    await ModelGate.ensureLoaded(
      modelId: null,
      category: ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION,
    );
    yield const ImageStarted();
    await for (final event in RunAnywhereDiffusion.shared.generateImageStream(
      effective.toProto(prompt),
    )) {
      switch (event.kind) {
        case DiffusionStreamEventKind.DIFFUSION_STREAM_EVENT_KIND_PROGRESS:
        case DiffusionStreamEventKind
            .DIFFUSION_STREAM_EVENT_KIND_INTERMEDIATE_IMAGE:
          if (event.hasProgress()) {
            yield ImageProgress(
              step: event.progress.currentStep,
              totalSteps: event.progress.totalSteps,
              partialImage: event.progress.hasIntermediateImageData()
                  ? Uint8List.fromList(event.progress.intermediateImageData)
                  : null,
            );
          }
        case DiffusionStreamEventKind.DIFFUSION_STREAM_EVENT_KIND_COMPLETED:
          if (event.hasResult()) {
            yield ImageCompleted(
              ImageResult.fromProto(event.result, steps: effective.steps),
            );
          }
        case DiffusionStreamEventKind.DIFFUSION_STREAM_EVENT_KIND_ERROR:
          throw SDKException.processingFailed(
            event.errorMessage.isEmpty
                ? 'Image generation failed'
                : event.errorMessage,
          );
        case DiffusionStreamEventKind.DIFFUSION_STREAM_EVENT_KIND_STARTED:
        case DiffusionStreamEventKind.DIFFUSION_STREAM_EVENT_KIND_UNSPECIFIED:
          break;
      }
    }
  }
}

/// Speaker diarization.
class DiarizationApi {
  /// Bind the namespace. Reach it through `RunAnywhere.diarization`.
  const DiarizationApi();

  /// Attribute spans of [audio] to speakers.
  ///
  /// ```dart
  /// final d = await RunAnywhere.diarization.diarize(AudioInput.pcm16(pcm));
  /// print(d.speakerCount);
  /// ```
  ///
  /// Throws [SDKException] when no diarization model is loaded.
  Future<DiarizationResult> diarize(
    AudioInput audio, {
    DiarizationOptions? options,
  }) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    await DartBridge.ensureServicesReady();
    final modelId = await ModelGate.currentId(
      ModelCategory.MODEL_CATEGORY_SPEAKER_DIARIZATION,
    );
    if (modelId == null) {
      throw SDKException.componentNotReady('Diarization');
    }
    final result = DartBridgeDiarization.shared.diarize(
      DiarizationRequest(
        audioData: audio.bytes,
        options: (options ?? DiarizationOptions()).toProto(audio),
      ),
    );
    return DiarizationResult.fromProto(result);
  }
}

/// Semantic image segmentation.
class SegmentationApi {
  /// Bind the namespace. Reach it through `RunAnywhere.segmentation`.
  const SegmentationApi();

  /// Assign a class to every pixel of [image].
  ///
  /// ```dart
  /// final s = await RunAnywhere.segmentation.segment(rgbImage);
  /// print(s.classes.map((c) => c.label));
  /// ```
  ///
  /// Throws [SDKException] when no segmentation model is loaded or the image
  /// is not packed RGB8.
  Future<SegmentationResult> segment(
    ImageInput image, {
    SegmentationOptions? options,
  }) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    await DartBridge.ensureServicesReady();
    final modelId = await ModelGate.currentId(
      ModelCategory.MODEL_CATEGORY_SEMANTIC_SEGMENTATION,
    );
    if (modelId == null) {
      throw SDKException.componentNotReady('Segmentation');
    }
    final result = DartBridgeSegmentation.shared.segment(
      SegmentationRequest(
        image: image.toSegmentationImage(),
        options: (options ?? const SegmentationOptions()).toProto(),
      ),
    );
    return SegmentationResult.fromProto(result);
  }
}
