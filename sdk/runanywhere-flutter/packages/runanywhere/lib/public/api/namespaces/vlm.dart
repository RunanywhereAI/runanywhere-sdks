// SPDX-License-Identifier: Apache-2.0
//
// `RunAnywhere.vlm` — vision-language generation.

import 'dart:async';

import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/vlm_options.pb.dart'
    show VLMGenerationRequest, VLMStreamEvent;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/public/api/internal/model_gate.dart';
import 'package:runanywhere/public/api/types/events.dart';
import 'package:runanywhere/public/api/types/inputs.dart';
import 'package:runanywhere/public/api/types/options.dart';
import 'package:runanywhere/public/api/types/results.dart';

/// Vision-language generation over one image.
class VlmApi {
  /// Bind the namespace. Reach it through `RunAnywhere.vlm`.
  const VlmApi();

  /// Answer [prompt] about [image].
  ///
  /// ```dart
  /// final r = await RunAnywhere.vlm.generate(img, 'What is in this photo?');
  /// print(r.text);
  /// ```
  ///
  /// Throws [SDKException] when no vision model is loadable or generation
  /// fails.
  Future<GenerationResult> generate(
    ImageInput image,
    String prompt, {
    LlmOptions? options,
  }) async {
    final request = await _request(image, prompt, options);
    final result = await DartBridge.vlm.processImageProto(request);
    return GenerationResult.fromVlm(
      result,
      requestId: request.requestId,
      model: request.modelId,
    );
  }

  /// Stream an answer to [prompt] about [image] token by token.
  ///
  /// Throws [SDKException] into the consumer when generation fails.
  Stream<GenerationEvent> generateStream(
    ImageInput image,
    String prompt, {
    LlmOptions? options,
  }) {
    final controller = StreamController<GenerationEvent>();
    controller.onListen = () {
      unawaited(_pump(controller, image, prompt, options));
    };
    controller.onCancel = cancel;
    return controller.stream;
  }

  /// Cancel the in-flight vision generation, if any.
  void cancel() {
    if (!DartBridge.isInitialized) return;
    DartBridge.vlm.cancel();
  }

  Future<void> _pump(
    StreamController<GenerationEvent> controller,
    ImageInput image,
    String prompt,
    LlmOptions? options,
  ) async {
    try {
      final request = await _request(image, prompt, options);
      controller.add(GenerationStarted(request.requestId));
      final buffer = StringBuffer();
      VLMStreamEvent? terminal;

      await for (final event in DartBridge.vlm.processImageStreamProto(
        request,
      )) {
        if (event.token.isNotEmpty) {
          buffer.write(event.token);
          controller.add(GenerationToken(event.token));
        }
        if (event.isFinal) {
          terminal = event;
          break;
        }
      }

      if (terminal != null && terminal.errorMessage.isNotEmpty) {
        throw SDKException.vlmProcessingFailed(terminal.errorMessage);
      }
      final result = terminal != null && terminal.hasResult()
          ? GenerationResult.fromVlm(
              terminal.result,
              requestId: request.requestId,
              model: request.modelId,
            )
          : GenerationResult(
              text: buffer.toString(),
              requestId: request.requestId,
              model: request.modelId,
            );
      controller.add(GenerationCompleted(result));
    } catch (error, stack) {
      controller.addError(
        error is SDKException
            ? error
            : SDKException.vlmProcessingFailed('$error'),
        stack,
      );
    } finally {
      await controller.close();
    }
  }

  Future<VLMGenerationRequest> _request(
    ImageInput image,
    String prompt,
    LlmOptions? options,
  ) async {
    await ModelGate.ensureLoaded(
      modelId: options?.model,
      category: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
    );
    final modelId =
        await ModelGate.currentId(ModelCategory.MODEL_CATEGORY_MULTIMODAL) ??
        await ModelGate.currentId(ModelCategory.MODEL_CATEGORY_VISION);
    if (modelId == null) {
      throw SDKException.vlmNotInitialized();
    }
    return VLMGenerationRequest(
      requestId: 'vlm-${DateTime.now().microsecondsSinceEpoch}',
      images: [image.toVlmImage()],
      options: (options ?? LlmOptions()).toVlmProto(prompt),
      modelId: modelId,
    );
  }
}
