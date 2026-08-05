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
    // onCancel also fires on normal completion; only cancel a generation that is
    // still running so a finished stream doesn't emit a spurious cancellation.
    var completed = false;
    var cancelled = false;
    controller.onListen = () {
      unawaited(
        _pump(
          controller,
          image,
          prompt,
          options,
          () => completed = true,
          () => cancelled,
        ),
      );
    };
    controller.onCancel = () {
      if (!completed) {
        cancelled = true;
        cancel();
      }
    };
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
    void Function() markCompleted,
    bool Function() isCancelled,
  ) async {
    var started = false;
    var requestId = '';
    try {
      final request = await _request(image, prompt, options);
      requestId = request.requestId;
      controller.add(GenerationStarted(requestId));
      started = true;
      final buffer = StringBuffer();
      VLMStreamEvent? terminal;

      await for (final event in DartBridge.vlm.processImageStreamProto(
        request,
      )) {
        if (event.token.isNotEmpty) {
          buffer.write(event.token);
          controller.add(GenerationTextDelta(event.token, requestId: requestId));
        }
        if (event.isFinal) {
          terminal = event;
          break;
        }
      }

      if (terminal != null && terminal.hasError()) {
        markCompleted();
        controller.add(
          GenerationFailed(
            SDKException.vlmProcessingFailed(terminal.error.message),
            partial: buffer.isEmpty ? null : buffer.toString(),
            requestId: requestId,
          ),
        );
        return;
      }

      if (terminal == null && isCancelled()) {
        markCompleted();
        controller.add(
          GenerationCancelled(
            partial: buffer.isEmpty ? null : buffer.toString(),
            requestId: requestId,
          ),
        );
        return;
      }

      final result = terminal != null && terminal.hasResult()
          ? GenerationResult.fromVlm(
              terminal.result,
              requestId: requestId,
              model: request.modelId,
            )
          : GenerationResult(
              text: buffer.toString(),
              requestId: requestId,
              model: request.modelId,
            );
      controller.add(
        GenerationUsage(
          inputTokens: result.inputTokens,
          outputTokens: result.outputTokens,
          requestId: requestId,
        ),
      );
      markCompleted();
      controller.add(GenerationCompleted(result, requestId: requestId));
    } catch (error, stack) {
      // Terminal reached; don't let teardown fire a spurious cancel after it.
      markCompleted();
      final sdkError = error is SDKException
          ? error
          : SDKException.vlmProcessingFailed('$error');
      if (started) {
        controller.add(GenerationFailed(sdkError, requestId: requestId));
      } else {
        controller.addError(sdkError, stack);
      }
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
