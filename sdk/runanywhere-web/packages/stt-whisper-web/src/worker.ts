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

// Worker ready signal
self.postMessage({ status: "worker_ready" });
