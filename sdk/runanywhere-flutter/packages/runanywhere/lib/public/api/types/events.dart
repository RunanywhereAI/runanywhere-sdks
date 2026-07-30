// SPDX-License-Identifier: Apache-2.0
//
// Public event types for the v3 API surface. Every stream follows one grammar:
// a started event, then deltas, then a completed event or a thrown error.

import 'dart:typed_data';

import 'package:runanywhere/generated/model_types.pb.dart' show ModelInfo;
import 'package:runanywhere/generated/model_types.pbenum.dart'
    show ModelCategory;
import 'package:runanywhere/generated/tool_calling.pb.dart' show ToolCall;
import 'package:runanywhere/public/api/types/results.dart';

/// Whether a streamed token is answer text or chain-of-thought.
enum TokenKind {
  /// Answer content the user should see.
  text,

  /// Chain-of-thought content, emitted only when reasoning output is enabled.
  thought,
}

/// Events emitted by `llm.generateStream` and `vlm.generateStream`.
sealed class GenerationEvent {
  const GenerationEvent();
}

/// The request was accepted and decoding is about to begin.
final class GenerationStarted extends GenerationEvent {
  /// Announce a request id for correlation.
  const GenerationStarted(this.requestId);

  /// Correlation id for the generation.
  final String requestId;
}

/// One decoded token.
final class GenerationToken extends GenerationEvent {
  /// Carry a token and its semantic category.
  const GenerationToken(this.text, {this.kind = TokenKind.text});

  /// Token text.
  final String text;

  /// Whether this is answer text or a thought.
  final TokenKind kind;
}

/// The model asked to call a tool.
final class GenerationToolCall extends GenerationEvent {
  /// Carry the requested call.
  const GenerationToolCall(this.call);

  /// Tool name and arguments the model produced.
  final ToolCall call;
}

/// Decoding finished; carries the aggregate result and metrics.
final class GenerationCompleted extends GenerationEvent {
  /// Carry the terminal result.
  const GenerationCompleted(this.result);

  /// Full text, tool calls, and metrics.
  final GenerationResult result;
}

/// Events emitted by `stt.transcribeStream`.
sealed class TranscriptionEvent {
  const TranscriptionEvent();
}

/// The session opened and is waiting for audio.
final class TranscriptionStarted extends TranscriptionEvent {
  /// Announce session start.
  const TranscriptionStarted();
}

/// An in-progress hypothesis that may still change.
final class TranscriptionPartial extends TranscriptionEvent {
  /// Carry the current hypothesis.
  const TranscriptionPartial(this.text);

  /// Hypothesis text so far.
  final String text;
}

/// The session closed with a settled transcript.
final class TranscriptionFinal extends TranscriptionEvent {
  /// Carry the settled transcript.
  const TranscriptionFinal(this.transcription);

  /// Final transcript with timings.
  final Transcription transcription;
}

/// What the voice agent is doing right now.
enum AgentState {
  /// Waiting for the user to speak.
  listening,

  /// Generating a reply.
  thinking,

  /// Speaking the reply.
  speaking,
}

/// Events emitted by a [VoiceEvent] stream on a voice session.
sealed class VoiceEvent {
  const VoiceEvent();
}

/// The user's speech was transcribed.
final class VoiceUserTranscribed extends VoiceEvent {
  /// Carry a user hypothesis or settled transcript.
  const VoiceUserTranscribed(this.text, {required this.isFinal});

  /// Transcribed text.
  final String text;

  /// True when the transcript will not change again.
  final bool isFinal;
}

/// The agent moved between listening, thinking, and speaking.
final class VoiceAgentStateChanged extends VoiceEvent {
  /// Carry the new state.
  const VoiceAgentStateChanged(this.state);

  /// What the agent is doing now.
  final AgentState state;
}

/// The agent produced reply text.
final class VoiceAgentResponse extends VoiceEvent {
  /// Carry the reply text.
  const VoiceAgentResponse(this.text);

  /// Reply text, accumulated so far.
  final String text;
}

/// Speech was detected on the microphone.
final class VoiceSpeechStarted extends VoiceEvent {
  /// Announce speech onset.
  const VoiceSpeechStarted();
}

/// Speech on the microphone ended.
final class VoiceSpeechEnded extends VoiceEvent {
  /// Announce speech offset.
  const VoiceSpeechEnded();
}

/// A component of the session hit trouble.
final class VoiceError extends VoiceEvent {
  /// Carry the failure and whether the session survives it.
  const VoiceError(this.message, {required this.recoverable});

  /// What went wrong.
  final String message;

  /// True when the session keeps running.
  final bool recoverable;
}

/// Events emitted by `RagSession.queryStream`.
sealed class RagEvent {
  const RagEvent();
}

/// Retrieval finished and produced these chunks.
final class RagRetrieved extends RagEvent {
  /// Carry the retrieved chunks.
  const RagRetrieved(this.matches);

  /// Chunks that will ground the answer.
  final List<Match> matches;
}

/// One decoded answer token.
final class RagToken extends RagEvent {
  /// Carry a token and its semantic category.
  const RagToken(this.text, {this.kind = TokenKind.text});

  /// Token text.
  final String text;

  /// Whether this is answer text or a thought.
  final TokenKind kind;
}

/// The query finished; carries the grounded answer.
final class RagCompleted extends RagEvent {
  /// Carry the terminal result.
  const RagCompleted(this.result);

  /// Answer, sources, and metrics.
  final RagResult result;
}

/// Events emitted by `images.generateStream`.
sealed class ImageEvent {
  const ImageEvent();
}

/// Sampling began.
final class ImageStarted extends ImageEvent {
  /// Announce the start of sampling.
  const ImageStarted();
}

/// One denoising step completed.
final class ImageProgress extends ImageEvent {
  /// Carry step counters and an optional preview.
  const ImageProgress({
    required this.step,
    required this.totalSteps,
    this.partialImage,
  });

  /// Steps completed.
  final int step;

  /// Steps in the schedule.
  final int totalSteps;

  /// Preview image, when partial reporting is enabled.
  final Uint8List? partialImage;
}

/// Sampling finished; carries the images.
final class ImageCompleted extends ImageEvent {
  /// Carry the terminal result.
  const ImageCompleted(this.result);

  /// Generated images and the sampling parameters used.
  final ImageResult result;
}

/// Events emitted by `models.download`.
sealed class DownloadEvent {
  const DownloadEvent();
}

/// Bytes are arriving.
final class DownloadProgressEvent extends DownloadEvent {
  /// Carry transfer counters.
  const DownloadProgressEvent({
    required this.bytesDone,
    required this.bytesTotal,
    required this.percent,
  });

  /// Bytes received so far.
  final int bytesDone;

  /// Total bytes expected. Zero when the server did not report a length.
  final int bytesTotal;

  /// Overall completion in `[0.0, 1.0]`.
  final double percent;
}

/// The transfer finished and the archive is being unpacked.
final class DownloadExtracting extends DownloadEvent {
  /// Announce the extraction phase.
  const DownloadExtracting();
}

/// The model is on disk and registered.
final class DownloadCompleted extends DownloadEvent {
  /// Carry the registered model.
  const DownloadCompleted(this.model);

  /// Registry entry with its resolved local path.
  final ModelInfo model;
}

/// Lifecycle, download, and error breadcrumbs from `RunAnywhere.events`.
sealed class SdkEvent {
  const SdkEvent();
}

/// Local inference became usable.
final class SdkReady extends SdkEvent {
  /// Announce readiness.
  const SdkReady();
}

/// A model finished loading.
final class SdkModelLoaded extends SdkEvent {
  /// Carry the loaded model's identity.
  const SdkModelLoaded(this.id, this.category);

  /// Model id.
  final String id;

  /// Category the model was loaded under.
  final ModelCategory category;
}

/// A model was unloaded.
final class SdkModelUnloaded extends SdkEvent {
  /// Carry the unloaded model's id.
  const SdkModelUnloaded(this.id);

  /// Model id.
  final String id;
}

/// Something went wrong outside a caller's request.
final class SdkError extends SdkEvent {
  /// Carry the failure and whether the SDK survives it.
  const SdkError(this.message, {required this.recoverable});

  /// What went wrong.
  final String message;

  /// True when the SDK keeps working.
  final bool recoverable;
}
