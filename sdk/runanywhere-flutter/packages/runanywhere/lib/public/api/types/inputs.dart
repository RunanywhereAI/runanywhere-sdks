// SPDX-License-Identifier: Apache-2.0
//
// Public input types for the v3 API surface.

import 'dart:io';
import 'dart:typed_data';

import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/chat.pb.dart' as chat_pb;
import 'package:runanywhere/generated/chat.pbenum.dart' show MessageRole;
// Prefixed because the public API declares its own AudioEncoding.
import 'package:runanywhere/generated/model_types.pbenum.dart' as model_pb;
import 'package:runanywhere/generated/ra_defaults_pool.dart';
import 'package:runanywhere/generated/segmentation.pb.dart' as seg_pb;
import 'package:runanywhere/generated/segmentation.pbenum.dart'
    show SegmentationPixelFormat;
import 'package:runanywhere/generated/stt_options.pb.dart'
    show STTAudioSource;
import 'package:runanywhere/generated/vad_options.pb.dart' show VADAudioSource;
import 'package:runanywhere/generated/vlm_options.pb.dart' as vlm_pb;

/// Sample encoding of the bytes carried by an [AudioInput].
enum AudioEncoding {
  /// Signed 16-bit little-endian PCM.
  pcm16,

  /// 32-bit little-endian float PCM.
  float32,

  /// Container-framed audio (WAV, MP3, FLAC, …) detected from the bytes.
  container,
}

/// Sample-rate, channel-count, and encoding of an [AudioInput].
class AudioFormatSpec {
  /// Describe raw or container-framed audio bytes.
  const AudioFormatSpec({
    required this.encoding,
    required this.sampleRate,
    this.channels = 1,
  });

  /// How individual samples are laid out in the buffer.
  final AudioEncoding encoding;

  /// Samples per second.
  final int sampleRate;

  /// Interleaved channel count.
  final int channels;
}

/// One PCM frame pushed into a live stream opened by `stt.openStream` or
/// `vad.openStream`. Samples must match the format the stream was opened
/// with; live streams take raw PCM only.
class AudioFrame {
  /// Wrap one PCM frame.
  const AudioFrame({
    required this.samples,
    required this.sampleCount,
    this.timestampMs,
  });

  /// Raw PCM bytes in the stream's established encoding.
  final Uint8List samples;

  /// Sample count carried by [samples].
  final int sampleCount;

  /// Capture timestamp, when the caller tracks one.
  final int? timestampMs;
}

/// Audio handed to `stt`, `vad`, and `diarization`.
class AudioInput {
  const AudioInput._(this.bytes, this.format);

  /// Wrap signed 16-bit little-endian PCM samples.
  factory AudioInput.pcm16(
    Uint8List bytes, {
    int sampleRate = RADefaultsAudioCapture.micSampleRateHz,
    int channels = 1,
  }) => AudioInput._(
    bytes,
    AudioFormatSpec(
      encoding: AudioEncoding.pcm16,
      sampleRate: sampleRate,
      channels: channels,
    ),
  );

  /// Wrap 32-bit float samples in `[-1.0, 1.0]`.
  factory AudioInput.float32(
    Float32List samples, {
    int sampleRate = RADefaultsAudioCapture.micSampleRateHz,
    int channels = 1,
  }) {
    final buffer = ByteData(samples.lengthInBytes);
    for (var i = 0; i < samples.length; i++) {
      buffer.setFloat32(i * 4, samples[i], Endian.little);
    }
    return AudioInput._(
      buffer.buffer.asUint8List(),
      AudioFormatSpec(
        encoding: AudioEncoding.float32,
        sampleRate: sampleRate,
        channels: channels,
      ),
    );
  }

  /// Wrap a complete WAV file, header included.
  factory AudioInput.wav(Uint8List bytes) => AudioInput._(
    bytes,
    const AudioFormatSpec(
      encoding: AudioEncoding.container,
      sampleRate: 0,
      channels: 1,
    ),
  );

  /// Read a container-framed audio file from disk.
  ///
  /// Throws [SDKException] when the path does not exist.
  static Future<AudioInput> file(String path) async {
    final handle = File(path);
    if (!handle.existsSync()) {
      throw SDKException.invalidInput('Audio file not found: $path');
    }
    return AudioInput._(
      await handle.readAsBytes(),
      const AudioFormatSpec(
        encoding: AudioEncoding.container,
        sampleRate: 0,
        channels: 1,
      ),
    );
  }

  /// Raw audio bytes.
  final Uint8List bytes;

  /// Layout of [bytes].
  final AudioFormatSpec format;

  /// Build the generated STT audio source for this input.
  ///
  /// `bits_per_sample` was deleted outright (idl/stt_options.proto) — it is
  /// implied by `encoding` now, so this no longer sets it.
  STTAudioSource toSttSource() => STTAudioSource(
    audioData: bytes,
    encoding: _sttEncoding,
    sampleRate: format.sampleRate > 0
        ? format.sampleRate
        : RADefaultsAudioCapture.micSampleRateHz,
    channels: format.channels,
  );

  /// Build the generated VAD audio source for this input.
  VADAudioSource toVadSource() => VADAudioSource(
    audioData: bytes,
    encoding: format.encoding == AudioEncoding.float32
        ? model_pb.AudioEncoding.AUDIO_ENCODING_PCM_F32_LE
        : model_pb.AudioEncoding.AUDIO_ENCODING_PCM_S16_LE,
    sampleRate: format.sampleRate > 0
        ? format.sampleRate
        : RADefaultsAudioCapture.micSampleRateHz,
    channels: format.channels,
  );

  model_pb.AudioEncoding get _sttEncoding {
    switch (format.encoding) {
      case AudioEncoding.pcm16:
        return model_pb.AudioEncoding.AUDIO_ENCODING_PCM_S16_LE;
      case AudioEncoding.float32:
        return model_pb.AudioEncoding.AUDIO_ENCODING_PCM_F32_LE;
      case AudioEncoding.container:
        return model_pb.AudioEncoding.AUDIO_ENCODING_CONTAINER;
    }
  }

}

/// Image handed to `vlm` and `segmentation`.
class ImageInput {
  const ImageInput._({
    required this.bytes,
    this.path,
    this.width = 0,
    this.height = 0,
    this.isRawRgb = false,
    this.mediaType = 'image/png',
  });

  /// Reference an encoded image file on disk.
  factory ImageInput.file(String path) =>
      ImageInput._(bytes: Uint8List(0), path: path);

  /// Wrap encoded image bytes (PNG, JPEG, WebP, …).
  ///
  /// `VLMImage.format` (an enum) was deleted outright — [mediaType] (a plain
  /// MIME string, e.g. `"image/jpeg"`) replaces the closed format enum
  /// entirely so a new container type is not a proto change
  /// (idl/vlm_options.proto). Defaults to `"image/png"`; pass the true MIME
  /// type when [data] is not PNG.
  factory ImageInput.bytes(Uint8List data, {String mediaType = 'image/png'}) =>
      ImageInput._(bytes: data, mediaType: mediaType);

  /// Wrap tightly packed 8-bit RGB pixels.
  factory ImageInput.rawRgb(Uint8List data, int width, int height) =>
      ImageInput._(
        bytes: data,
        width: width,
        height: height,
        isRawRgb: true,
      );

  /// Encoded or raw pixel bytes. Empty when [path] carries the image.
  final Uint8List bytes;

  /// Filesystem path, when the image was supplied by reference.
  final String? path;

  /// Pixel width. Non-zero only for [ImageInput.rawRgb].
  final int width;

  /// Pixel height. Non-zero only for [ImageInput.rawRgb].
  final int height;

  /// True when [bytes] holds packed RGB8 pixels rather than an encoded file.
  final bool isRawRgb;

  /// MIME type of [bytes] when it holds a compressed container (PNG/JPEG/
  /// WebP). Unused for [path] or raw-RGB inputs.
  final String mediaType;

  /// Build the generated VLM image for this input.
  ///
  /// `VLMImage.format` (an enum) was deleted outright — the `source` oneof
  /// (`filePath`/`data`/`rawRgb`/`base64`/`rawRgba`) is now the sole
  /// declaration of the image's shape, and the compressed-container arm was
  /// renamed `encoded` -> `data` (idl/vlm_options.proto). `media_type` is
  /// required alongside `data`.
  vlm_pb.VLMImage toVlmImage() {
    final image = vlm_pb.VLMImage();
    final filePath = path;
    if (filePath != null) {
      image.filePath = filePath;
    } else if (isRawRgb) {
      image
        ..rawRgb = bytes
        ..width = width
        ..height = height;
    } else {
      image
        ..data = bytes
        ..mediaType = mediaType;
    }
    return image;
  }

  /// Build the generated segmentation image for this input.
  ///
  /// Throws [SDKException] unless the input carries packed RGB8 pixels, which
  /// is the only layout the segmentation ABI accepts.
  seg_pb.SegmentationImage toSegmentationImage() {
    if (!isRawRgb || width <= 0 || height <= 0) {
      throw SDKException.invalidInput(
        'Segmentation requires ImageInput.rawRgb(data, width, height)',
      );
    }
    return seg_pb.SegmentationImage(
      data: bytes,
      width: width,
      height: height,
      pixelFormat: SegmentationPixelFormat.SEGMENTATION_PIXEL_FORMAT_RGB8,
    );
  }
}

/// Conversational role of a [ChatMessage].
enum ChatRole {
  /// System instruction turn.
  system,

  /// End-user turn.
  user,

  /// Model turn.
  assistant,

  /// Tool-result turn.
  tool,
}

/// One turn in a chat conversation.
class ChatMessage {
  /// Build a chat turn.
  const ChatMessage({
    required this.role,
    required this.content,
    this.toolCallId,
  });

  /// Convenience constructor for a system turn.
  const ChatMessage.system(String content)
    : this(role: ChatRole.system, content: content);

  /// Convenience constructor for a user turn.
  const ChatMessage.user(String content)
    : this(role: ChatRole.user, content: content);

  /// Convenience constructor for an assistant turn.
  const ChatMessage.assistant(String content)
    : this(role: ChatRole.assistant, content: content);

  /// Who authored the turn.
  final ChatRole role;

  /// Turn text.
  final String content;

  /// Identifier of the tool call this turn answers.
  final String? toolCallId;

  /// Build the generated chat message for this turn.
  chat_pb.ChatMessage toProto() {
    final message = chat_pb.ChatMessage(role: _protoRole, content: content);
    final callId = toolCallId;
    if (callId != null) {
      message.toolCallId = callId;
    }
    return message;
  }

  MessageRole get _protoRole {
    switch (role) {
      case ChatRole.system:
        return MessageRole.MESSAGE_ROLE_SYSTEM;
      case ChatRole.user:
        return MessageRole.MESSAGE_ROLE_USER;
      case ChatRole.assistant:
        return MessageRole.MESSAGE_ROLE_ASSISTANT;
      case ChatRole.tool:
        return MessageRole.MESSAGE_ROLE_TOOL;
    }
  }
}

/// Reference to a registered model, plus an optional voice for TTS.
class ModelRef {
  /// Point at a model by registry id.
  const ModelRef(this.id, {this.voice});

  /// Registry model id.
  final String id;

  /// Voice id inside a multi-voice TTS model. Never a model id.
  final String? voice;
}

/// Document handed to `RagSession.ingest`.
class RagDocument {
  /// Wrap in-memory text.
  const RagDocument(this.text, {this.metadata, this.sourceUri});

  /// Read a UTF-8 text file from disk.
  ///
  /// Throws [SDKException] when the path does not exist.
  static Future<RagDocument> file(String path) async {
    final handle = File(path);
    if (!handle.existsSync()) {
      throw SDKException.invalidInput('Document file not found: $path');
    }
    return RagDocument(await handle.readAsString(), sourceUri: path);
  }

  /// Document body.
  final String text;

  /// Caller metadata echoed back on every [text] match.
  final Map<String, String>? metadata;

  /// Origin of the document, when it came from a file or URL.
  final String? sourceUri;
}
