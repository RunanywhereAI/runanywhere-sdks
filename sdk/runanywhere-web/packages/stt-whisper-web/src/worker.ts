import { pipeline, WhisperTextStreamer } from "@huggingface/transformers";
import { WHISPER_WEB_CONSTANTS, MODELS } from "./constants.js";

// Pipeline Factory Pattern (EXACT from fork)
class PipelineFactory {
  static task: string | null = null;
  static model: string | null = null;
  static dtype: string | null = null;
  static gpu: boolean = false;
  static instance: any = null;

  static async getInstance(progress_callback: any = null) {
    if (this.instance === null) {
      this.instance = pipeline(this.task as any, this.model as string, {
        dtype: this.dtype as any,
        device: this.gpu ? "webgpu" : "wasm",  // CRITICAL: Device config
        progress_callback,
      });
    }
    return this.instance;
  }
}

class AutomaticSpeechRecognitionPipelineFactory extends PipelineFactory {
  static task = "automatic-speech-recognition";
}

// Transcription function (EXACT pattern from fork)
const transcribe = async ({ audio, model, dtype, gpu, subtask, language }: any) => {
  // DEBUG: Log transcribe function inputs
  console.log('[Worker transcribe] Input params:', {
    hasAudio: !!audio,
    audioType: audio?.constructor?.name,
    audioLength: audio?.length,
    audioSample: audio ? audio.slice(0, 5) : undefined,
    model,
    dtype,
    gpu,
    subtask,
    language
  });

  // CRITICAL: Check if audio is actually defined
  if (!audio || !(audio instanceof Float32Array)) {
    console.error('[Worker] CRITICAL ERROR: Audio is not a Float32Array!', {
      audio,
      audioType: typeof audio,
      audioConstructor: audio?.constructor?.name
    });
    throw new Error('Audio data is invalid or missing');
  }

  const p = AutomaticSpeechRecognitionPipelineFactory;

  // Model lifecycle management (EXACT from fork)
  if (p.model !== model || p.dtype !== dtype || p.gpu !== gpu) {
    // Set properties FIRST
    p.model = model;
    p.dtype = dtype;
    p.gpu = gpu;

    if (p.instance !== null) {
      (await p.getInstance()).dispose();  // CRITICAL: Disposal
      p.instance = null;
    }
  }

  // Get transcriber instance
  const transcriber = await p.getInstance((data: any) => {
    self.postMessage(data);  // Progress updates
  });

  const time_precision = transcriber.processor.feature_extractor.config.chunk_length / transcriber.model.config.max_source_positions;

  // Storage for chunks to be processed (EXACT from fork)
  const chunks: Array<{
    text: string;
    offset: number;
    timestamp: [number, number | null];
    finalised: boolean;
  }> = [];

  // Streaming configuration
  const isDistilWhisper = model.startsWith("distil-whisper/");
  const chunk_length_s = isDistilWhisper ? 20 : 30;
  const stride_length_s = isDistilWhisper ? 3 : 5;

  let chunk_count = 0;
  let start_time: number | null = null;
  let num_tokens = 0;
  let tps: number = 0;

  // WhisperTextStreamer setup (EXACT from fork)
  const streamer = new WhisperTextStreamer(transcriber.tokenizer, {
    time_precision,
    on_chunk_start: (x: any) => {
      const offset = (chunk_length_s - stride_length_s) * chunk_count;
      chunks.push({
        text: "",
        timestamp: [offset + x, null],
        finalised: false,
        offset,
      });
    },
    token_callback_function: (x: any) => {
      start_time ??= performance.now();
      if (num_tokens++ > 0) {
        tps = (num_tokens / (performance.now() - start_time)) * 1000;
      }
    },
    callback_function: (x: any) => {
      if (chunks.length === 0) return;
      // Append text to the last chunk
      chunks.at(-1)!.text += x;

      self.postMessage({
        status: "update",
        data: {
          text: "", // No need to send full text yet
          chunks,
          tps,
        },
      });
    },
    on_chunk_end: (x: any) => {
      const current = chunks.at(-1)!;
      current.timestamp[1] = x + current.offset;
      current.finalised = true;
    },
    on_finalize: () => {
      start_time = null;
      num_tokens = 0;
      ++chunk_count;
    },
  });

  // CRITICAL DEBUG: Final validation before transcriber
  const audioValidation = {
    isFloat32Array: audio instanceof Float32Array,
    length: audio?.length || 0,
    first10: Array.from(audio?.slice(0, 10) || []),
    last10: Array.from(audio?.slice(-10) || []),
    hasRealData: audio?.some((v: number) => v !== 0 && !isNaN(v)) || false,
    nanCount: audio?.filter((v: number) => isNaN(v)).length || 0,
    infinityCount: audio?.filter((v: number) => !isFinite(v)).length || 0,
    bufferValid: audio?.buffer instanceof ArrayBuffer,
    byteLength: audio?.buffer?.byteLength || 0,
    expectedBytes: (audio?.length || 0) * 4,
    bytesMatch: audio?.buffer?.byteLength === (audio?.length || 0) * 4
  };

  console.log('[Worker] CRITICAL: Final audio validation:', audioValidation);

  if (!audioValidation.bytesMatch) {
    console.error('[Worker] WARNING: Buffer size mismatch!');
  }

  if (!audioValidation.hasRealData) {
    console.error('[Worker] WARNING: Audio appears to be silent/corrupted!');
  }

  // Log the exact audio being sent
  console.log('[Worker] FINAL CHECK - Audio to transcriber:', {
    type: Object.prototype.toString.call(audio),
    constructor: audio?.constructor?.name,
    isFloat32: audio instanceof Float32Array,
    length: audio?.length,
    byteLength: audio?.byteLength,
    buffer: audio?.buffer,
    bufferByteLength: audio?.buffer?.byteLength,
    BYTES_PER_ELEMENT: audio?.BYTES_PER_ELEMENT,
    sample: Array.from(audio?.slice(100, 120) || []) // Get samples after the silence
  });

  // Actually run transcription (EXACT from fork)
  const output = await transcriber(audio, {
    // Greedy decoding
    top_k: 0,
    do_sample: false,

    // Sliding window
    chunk_length_s,
    stride_length_s,

    // Language and task
    language,
    task: subtask,

    // Timestamps
    return_timestamps: true,
    force_full_sequences: false,

    // Streaming
    streamer,
  }).catch((error: any) => {
    console.error(error);
    self.postMessage({
      status: "error",
      data: error,
    });
    return null;
  });

  return {
    tps,
    ...output,
  };
};

// Worker message handling
self.addEventListener("message", async (event) => {
  const message = event.data;

  // COMPREHENSIVE DEBUG: Analyze audio data thoroughly
  let audioDebugInfo: any = { hasAudio: false };
  if (message?.audio) {
    try {
      const audio = message.audio;
      const first100 = audio.slice(0, Math.min(100, audio.length));
      const nonZeroSamples = first100.filter((v: number) => v !== 0);

      audioDebugInfo = {
        hasAudio: true,
        audioType: audio.constructor.name,
        audioLength: audio.length,
        // Sample analysis
        first10Samples: Array.from(audio.slice(0, 10)),
        last10Samples: Array.from(audio.slice(-10)),
        middle10Samples: Array.from(audio.slice(Math.floor(audio.length/2), Math.floor(audio.length/2) + 10)),
        // Zero analysis
        nonZeroCount: nonZeroSamples.length,
        percentNonZero: ((nonZeroSamples.length / first100.length) * 100).toFixed(1) + '%',
        firstNonZeroIdx: audio.findIndex((v: number) => v !== 0),
        // Range analysis
        minValue: Math.min(...Array.from(audio.slice(0, Math.min(1000, audio.length)) as Float32Array)),
        maxValue: Math.max(...Array.from(audio.slice(0, Math.min(1000, audio.length)) as Float32Array)),
        // Type checks
        isFloat32: audio instanceof Float32Array,
        bufferBytes: audio.buffer?.byteLength || 0,
        bytesPerElement: audio.BYTES_PER_ELEMENT
      };
    } catch (err) {
      audioDebugInfo = { hasAudio: true, analysisError: String(err) };
    }
  }

  console.log('[Worker] Audio analysis:', audioDebugInfo);
  console.log('[Worker] Model config:', {
    model: message?.model,
    dtype: message?.dtype,
    gpu: message?.gpu,
    subtask: message?.subtask,
    language: message?.language
  });

  try {
    const transcript = await transcribe(message);
    if (transcript === null) return;

    self.postMessage({
      status: "complete",
      data: transcript,
    });
  } catch (error) {
    console.error(error);
    self.postMessage({
      status: "error",
      data: error,
    });
  }
});

// Don't send worker_ready - fork doesn't have this
// self.postMessage({ status: "worker_ready" });
