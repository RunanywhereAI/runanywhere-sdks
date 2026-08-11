// SPDX-License-Identifier: Apache-2.0
//
// Public v4 event grammar: one shape throughout — `started`, then deltas,
// then a terminal `completed`/`failed`/`cancelled`. A stream never fabricates
// a successful `completed` after an in-flight failure or cancellation; the
// terminal event carries whatever partial output was produced instead.
//
// Reference: bindings/swift/Sources/RunAnywhere/Public/API/Events.swift,
// bindings/web/packages/core/src/Public/API/Events.ts, and
// .claude/handoff/plans/public_api_spec.md.

import 'dart:typed_data';

import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/model_types.pb.dart' show ModelInfo;
import 'package:runanywhere/generated/model_types.pbenum.dart'
    show ModelCategory;
import 'package:runanywhere/generated/tool_calling.pb.dart' show ToolCall;
import 'package:runanywhere/public/api/types/results.dart';

/// Whether a streamed delta is answer text or chain-of-thought.
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

/// The request was admitted and generation began.
final class GenerationStarted extends GenerationEvent {
  /// Announce a request id for correlation.
  const GenerationStarted(this.requestId);

  /// Correlation id for the generation.
  final String requestId;
}

/// One answer-text delta.
final class GenerationTextDelta extends GenerationEvent {
  /// Carry the text produced since the previous delta.
  const GenerationTextDelta(this.text, {this.requestId = ''});

  /// Text produced since the previous delta.
  final String text;

  /// Correlation id for the generation.
  final String requestId;
}

/// One reasoning/thinking delta, emitted only when reasoning output is
/// enabled.
final class GenerationReasoningDelta extends GenerationEvent {
  /// Carry the reasoning text produced since the previous delta.
  const GenerationReasoningDelta(this.text, {this.requestId = ''});

  /// Reasoning text produced since the previous delta.
  final String text;

  /// Correlation id for the generation.
  final String requestId;
}

/// Deprecated v3 shape: one decoded token tagged with [kind] instead of a
/// dedicated event per stream.
///
/// `llm`/`vlm` `generateStream` no longer emit this — they emit
/// [GenerationTextDelta] (`kind == TokenKind.text`) or
/// [GenerationReasoningDelta] (`kind == TokenKind.thought`) — but the type
/// remains for source compatibility.
@Deprecated(
  'Use GenerationTextDelta for answer text or GenerationReasoningDelta '
  'for thoughts',
)
final class GenerationToken extends GenerationEvent {
  /// Carry a token and its semantic category.
  const GenerationToken(
    this.text, {
    this.kind = TokenKind.text,
    this.requestId = '',
  });

  /// Token text.
  final String text;

  /// Whether this is answer text or a thought.
  final TokenKind kind;

  /// Correlation id for the generation.
  final String requestId;
}

/// The model asked to call a tool.
final class GenerationToolCallAdded extends GenerationEvent {
  /// Carry the requested call.
  const GenerationToolCallAdded(this.call, {this.requestId = ''});

  /// Tool name and arguments the model produced.
  final ToolCall call;

  /// Correlation id for the generation.
  final String requestId;
}

/// Deprecated v3 name for [GenerationToolCallAdded].
@Deprecated('Use GenerationToolCallAdded')
final class GenerationToolCall extends GenerationEvent {
  /// Carry the requested call.
  const GenerationToolCall(this.call, {this.requestId = ''});

  /// Tool name and arguments the model produced.
  final ToolCall call;

  /// Correlation id for the generation.
  final String requestId;
}

/// Token accounting for the request so far.
final class GenerationUsage extends GenerationEvent {
  /// Carry running token counts.
  const GenerationUsage({
    required this.inputTokens,
    required this.outputTokens,
    this.requestId = '',
  });

  /// Prompt tokens consumed.
  final int inputTokens;

  /// Completion tokens produced so far.
  final int outputTokens;

  /// Correlation id for the generation.
  final String requestId;
}

/// Decoding finished; carries the aggregate result and metrics. Terminal —
/// no event follows.
final class GenerationCompleted extends GenerationEvent {
  /// Carry the terminal result. [requestId] defaults to `result.requestId`
  /// when not given explicitly.
  GenerationCompleted(this.result, {String? requestId})
    : requestId = requestId ?? result.requestId;

  /// Full text, tool calls, and metrics.
  final GenerationResult result;

  /// Correlation id for the generation.
  final String requestId;
}

/// Generation failed in flight. Terminal — no event follows.
///
/// `llm`/`vlm` `generateStream` never fabricate a [GenerationCompleted]
/// after this.
final class GenerationFailed extends GenerationEvent {
  /// Carry the failure and any partial text produced before it.
  const GenerationFailed(this.error, {this.partial, this.requestId = ''});

  /// What went wrong.
  final SDKException error;

  /// Text produced before the failure, when any was.
  final String? partial;

  /// Correlation id for the generation.
  final String requestId;
}

/// Generation was cancelled by the caller. Terminal — no event follows.
final class GenerationCancelled extends GenerationEvent {
  /// Carry any partial text produced before cancellation.
  const GenerationCancelled({this.partial, this.requestId = ''});

  /// Text produced before cancellation, when any was.
  final String? partial;

  /// Correlation id for the generation.
  final String requestId;
}

/// Events emitted by `stt.transcribeStream`.
sealed class TranscriptionEvent {
  const TranscriptionEvent();
}

/// The session opened and is waiting for audio.
final class TranscriptionStarted extends TranscriptionEvent {
  /// Announce session start, optionally with a correlation id.
  const TranscriptionStarted([this.requestId = '']);

  /// Correlation id for this stream, when one was assigned.
  final String requestId;
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

/// The stream settled — [TranscriptionFinal] (when the session produced
/// one) has already been emitted. Terminal.
final class TranscriptionCompleted extends TranscriptionEvent {
  /// Announce a clean finish.
  const TranscriptionCompleted();
}

/// The stream ended because of an error. Terminal — no event follows.
///
/// `stt.openStream` never fabricates a [TranscriptionFinal]/completion when
/// the native session ends without one; this is what it emits instead.
final class TranscriptionFailed extends TranscriptionEvent {
  /// Carry the failure.
  const TranscriptionFailed(this.error);

  /// What went wrong.
  final SDKException error;
}

/// The stream was cancelled before it produced a final transcript. Terminal.
final class TranscriptionCancelled extends TranscriptionEvent {
  /// Announce cancellation.
  const TranscriptionCancelled();
}

/// Events emitted by `vad.openStream`.
sealed class VadEvent {
  const VadEvent();
}

/// Speech began after a run of silence (or stream start).
final class VadSpeechStarted extends VadEvent {
  /// Carry the frame timestamp that crossed the boundary, when known.
  const VadSpeechStarted(this.timestampMs);

  /// Timestamp of the triggering frame.
  final int? timestampMs;
}

/// Speech ended after a run of activity.
final class VadSpeechEnded extends VadEvent {
  /// Carry the frame timestamp that crossed the boundary, when known.
  const VadSpeechEnded(this.timestampMs);

  /// Timestamp of the triggering frame.
  final int? timestampMs;
}

/// One frame's verdict, with no state transition implied.
final class VadActivity extends VadEvent {
  /// Carry one frame's detection result.
  const VadActivity({
    required this.isSpeech,
    required this.probability,
    this.timestampMs,
  });

  /// True when this frame was classified as speech.
  final bool isSpeech;

  /// Speech probability for this frame.
  final double probability;

  /// Timestamp of this frame.
  final int? timestampMs;
}

/// The stream failed in flight. Terminal — no event follows.
final class VadFailed extends VadEvent {
  /// Carry the failure.
  const VadFailed(this.error);

  /// What went wrong.
  final SDKException error;
}

/// The stream finished normally, after `finish()` drained the last frame.
final class VadCompleted extends VadEvent {
  /// Announce a clean finish.
  const VadCompleted();
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

/// Events emitted by `models.download`, correlated by [DownloadEvent.operationId]
/// and its per-event `sequence` counter.
///
/// One grammar throughout: `started`, then progress deltas, then a terminal
/// `completed`/`failed`/`cancelled`. `models.download` never fabricates a
/// [DownloadCompleted] after a [DownloadFailed]/[DownloadCancelled].
sealed class DownloadEvent {
  const DownloadEvent();
}

/// The transfer was admitted and began.
final class DownloadStarted extends DownloadEvent {
  /// Announce the start of one download operation.
  const DownloadStarted(this.operationId, {this.sequence = 0});

  /// Correlation id for this download, stable across every event it emits.
  final String operationId;

  /// Monotonic per-operation event counter.
  final int sequence;
}

/// Bytes are arriving.
final class DownloadProgressEvent extends DownloadEvent {
  /// Carry transfer counters and commons-owned overall progress.
  const DownloadProgressEvent({
    required this.operationId,
    required this.bytesDone,
    required this.bytesTotal,
    this.sequence = 0,
    this.file,
    this.overallProgress,
  });

  /// Correlation id for this download.
  final String operationId;

  /// Bytes received so far.
  final int bytesDone;

  /// Total bytes expected. Zero when the server did not report a length.
  final int bytesTotal;

  /// Monotonic per-operation event counter.
  final int sequence;

  /// File currently being fetched, for multi-file downloads.
  final String? file;

  /// Fraction of the whole download that is done, `0.0..1.0`, as reported by
  /// commons (`DownloadProgress.overall_progress`). Null when commons has not
  /// yet reported a positive value — never re-derived from [bytesDone]/
  /// [bytesTotal] (multi-file plans make that a per-file figure).
  final double? overallProgress;
}

/// Downloaded bytes are being checksummed/validated.
final class DownloadVerifying extends DownloadEvent {
  /// Announce the verification phase.
  const DownloadVerifying(this.operationId, {this.sequence = 0});

  /// Correlation id for this download.
  final String operationId;

  /// Monotonic per-operation event counter.
  final int sequence;
}

/// The transfer finished and the archive is being unpacked.
final class DownloadExtracting extends DownloadEvent {
  /// Announce the extraction phase.
  const DownloadExtracting(this.operationId, {this.sequence = 0, this.percent});

  /// Correlation id for this download.
  final String operationId;

  /// Monotonic per-operation event counter.
  final int sequence;

  /// Extraction completion, when the backend reports incremental progress.
  final double? percent;
}

/// The model is on disk and registered. Terminal — no event follows.
final class DownloadCompleted extends DownloadEvent {
  /// Carry the registered model.
  const DownloadCompleted(this.operationId, this.model, {this.sequence = 0});

  /// Correlation id for this download.
  final String operationId;

  /// Registry entry with its resolved local path.
  final ModelInfo model;

  /// Monotonic per-operation event counter.
  final int sequence;
}

/// The transfer failed in flight. Terminal — no event follows.
final class DownloadFailed extends DownloadEvent {
  /// Carry the failure.
  const DownloadFailed(this.operationId, this.error, {this.sequence = 0});

  /// Correlation id for this download.
  final String operationId;

  /// What went wrong.
  final SDKException error;

  /// Monotonic per-operation event counter.
  final int sequence;
}

/// The transfer was cancelled by the caller. Terminal — no event follows.
final class DownloadCancelled extends DownloadEvent {
  /// Announce cancellation.
  const DownloadCancelled(this.operationId, {this.sequence = 0});

  /// Correlation id for this download.
  final String operationId;

  /// Monotonic per-operation event counter.
  final int sequence;
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
