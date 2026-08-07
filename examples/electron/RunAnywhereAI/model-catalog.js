// model-catalog.js — THIS APP's model table, ported from the Android sample's
// ModelCatalog.kt (the non-NPU rows). The catalog lives in the app, not the SDK;
// each row is registered at boot as a ModelRegistration so it can be named by id.
//
// Frameworks: llama.cpp (GGUF), sherpa-onnx (speech), onnx (embeddings/VAD/
// segmentation). QHexRT / HNPU (NPU) models are intentionally excluded — this
// desktop build links no NPU backend.
//
// Row shape:
//   { type, framework, label, files:[{url,filename}], sizeMB,
//     archive?:{type,structure}, contextLength?, thinking?, params? }
// A row is an archive if `archive` is set, multi-file if it has >1 file, else a
// single-file URL. `filename` defaults to the URL basename.

const mb = (bytes) => Math.round(bytes / 1e6);
const file = (url, filename) => ({ url, filename: filename || url.split('/').pop() });

// Single-file GGUF language model (llama.cpp).
const llm = (label, url, bytes, extra = {}) => ({ type: 'llm', framework: 'llamaCpp', label, files: [file(url)], sizeMB: mb(bytes), ...extra });
// Multi-file GGUF vision-language model: primary + mmproj projector.
const vlm = (label, modelUrl, mmprojUrl, bytes, extra = {}) => ({ type: 'vlm', framework: 'llamaCpp', label, files: [file(modelUrl), file(mmprojUrl)], sizeMB: mb(bytes), ...extra });
// Multi-file model (sherpa STT / onnx embeddings / segmentation / diarization).
// `multiFile` forces multi-file registration even for a single descriptor, so its
// on-disk filename is controlled (some onnx providers expect exactly model.onnx).
const multi = (type, framework, label, urls, bytes, extra = {}) => ({ type, framework, label, files: urls.map((u) => (Array.isArray(u) ? file(u[0], u[1]) : file(u))), sizeMB: mb(bytes), multiFile: true, ...extra });
// Single-file model of any framework (onnx VAD, GGUF embedder).
const single = (type, framework, label, url, bytes, extra = {}) => ({ type, framework, label, files: [file(url)], sizeMB: mb(bytes), ...extra });
// Extracted archive (sherpa whisper/piper, llama.cpp SmolVLM dir).
const archive = (type, framework, label, url, bytes, structure, extra = {}) => ({ type, framework, label, files: [file(url)], sizeMB: mb(bytes), archive: { type: 'tar.gz', structure }, ...extra });

const HF = 'https://huggingface.co';
const REL = 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download';

const CATALOG = {
  // ---- LLM (llama.cpp) ----
  'smollm2-360m-q8_0': llm('SmolLM2 360M Q8_0', `${HF}/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf`, 386_404_416, { params: '360M' }),
  'qwen2.5-0.5b-instruct-q6_k': llm('Qwen 2.5 0.5B Instruct Q6_K', `${HF}/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf`, 600_000_000, { params: '0.5B' }),
  'qwen2.5-1.5b-instruct-q4_k_m': llm('Qwen 2.5 1.5B Instruct Q4_K_M', `${HF}/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf`, 2_500_000_000, { params: '1.5B', heavy: true }),
  'qwen3-0.6b-q4_k_m': llm('Qwen3 0.6B Q4_K_M', `${HF}/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf`, 396_705_472, { params: '0.6B', thinking: true }),
  'qwen3-1.7b-q4_k_m': llm('Qwen3 1.7B Q4_K_M', `${HF}/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf`, 1_200_000_000, { params: '1.7B', thinking: true, heavy: true }),
  'qwen3-4b-q4_k_m': llm('Qwen3 4B Q4_K_M', `${HF}/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf`, 2_800_000_000, { params: '4B', thinking: true, heavy: true }),
  'qwen3.5-0.8b-q4_k_m': llm('Qwen3.5 0.8B Q4_K_M', `${HF}/bartowski/Qwen_Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf`, 620_000_000, { params: '0.8B', thinking: true }),
  'lfm2.5-230m-q4_k_m': llm('LiquidAI LFM2.5 230M Q4_K_M', `${HF}/LiquidAI/LFM2.5-230M-GGUF/resolve/main/LFM2.5-230M-Q4_K_M.gguf`, 190_000_000, { params: '230M' }),
  'lfm2-350m-q4_k_m': llm('LiquidAI LFM2 350M Q4_K_M', `${HF}/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf`, 250_000_000, { params: '350M' }),
  'lfm2-1.2b-tool-q4_k_m': llm('LiquidAI LFM2 1.2B Tool Q4_K_M', `${HF}/LiquidAI/LFM2-1.2B-Tool-GGUF/resolve/main/LFM2-1.2B-Tool-Q4_K_M.gguf`, 800_000_000, { params: '1.2B' }),
  'lfm2.5-1.2b-instruct-q4_k_m': llm('LiquidAI LFM2.5 1.2B Instruct Q4_K_M', `${HF}/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q4_K_M.gguf`, 900_000_000, { params: '1.2B' }),
  'lfm2.5-2.6b-q4_k_m': llm('LiquidAI LFM2.5 2.6B Q4_K_M', `${HF}/LiquidAI/LFM2.5-2.6B-GGUF/resolve/main/LFM2.5-2.6B-Q4_K_M.gguf`, 1_674_000_000, { params: '2.6B', thinking: true, heavy: true }),
  'llama-2-7b-chat-q4_k_m': llm('Llama 2 7B Chat Q4_K_M', `${HF}/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf`, 4_000_000_000, { params: '7B', heavy: true }),
  'mistral-7b-instruct-q4_k_m': llm('Mistral 7B Instruct Q4_K_M', `${HF}/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf`, 4_000_000_000, { params: '7B', heavy: true }),
  'nemotron-mini-4b-instruct-q4_k_m': llm('NVIDIA Nemotron Mini 4B Instruct Q4_K_M', `${HF}/bartowski/Nemotron-Mini-4B-Instruct-GGUF/resolve/fb49cde090c86092d89905bea2ffc41c23c2615e/Nemotron-Mini-4B-Instruct-Q4_K_M.gguf`, 2_697_387_072, { params: '4B', contextLength: 4096, heavy: true }),
  'llama-3.1-nemotron-nano-4b-v1.1-q4_k_m': llm('NVIDIA Llama 3.1 Nemotron Nano 4B v1.1 Q4_K_M', `${HF}/bartowski/nvidia_Llama-3.1-Nemotron-Nano-4B-v1.1-GGUF/resolve/4eb0ffaec9b21a411cf4fa39df2fba0b7a972e11/nvidia_Llama-3.1-Nemotron-Nano-4B-v1.1-Q4_K_M.gguf`, 2_778_285_600, { params: '4B', contextLength: 4096, heavy: true }),
  'llama-3.1-nemotron-nano-8b-v1-q4_k_m': llm('NVIDIA Llama 3.1 Nemotron Nano 8B v1 Q4_K_M', `${HF}/bartowski/nvidia_Llama-3.1-Nemotron-Nano-8B-v1-GGUF/resolve/6f3d46cfbc39ce7a1bec89654305515d904e8102/nvidia_Llama-3.1-Nemotron-Nano-8B-v1-Q4_K_M.gguf`, 4_920_736_864, { params: '8B', contextLength: 4096, heavy: true }),
  'bonsai-1.7b-q1_0': llm('Bonsai-1.7B 1-bit Q1_0 (CPU)', `${HF}/prism-ml/Bonsai-1.7B-gguf/resolve/main/Bonsai-1.7B-Q1_0.gguf`, 248_302_272, { params: '1.7B', contextLength: 1024, thinking: true }),
  'bonsai-4b-q1_0': llm('Bonsai-4B 1-bit Q1_0 (CPU)', `${HF}/prism-ml/Bonsai-4B-gguf/resolve/main/Bonsai-4B-Q1_0.gguf`, 572_270_624, { params: '4B', contextLength: 1024, thinking: true }),
  'bonsai-8b-q1_0': llm('Bonsai-8B 1-bit Q1_0 (CPU)', `${HF}/prism-ml/Bonsai-8B-gguf/resolve/main/Bonsai-8B-Q1_0.gguf`, 1_158_654_496, { params: '8B', contextLength: 1024, thinking: true, heavy: true }),
  'bonsai-27b-q1_0': llm('Bonsai-27B 1-bit Q1_0 (CPU)', `${HF}/prism-ml/Bonsai-27B-gguf/resolve/main/Bonsai-27B-Q1_0.gguf`, 3_803_452_480, { params: '27B', contextLength: 1024, thinking: true, heavy: true }),

  // ---- VLM (llama.cpp, multimodal) ----
  'smolvlm2-256m-video-instruct-q8_0': vlm('SmolVLM2 256M Video Instruct Q8_0', `${HF}/ggml-org/SmolVLM2-256M-Video-Instruct-GGUF/resolve/main/SmolVLM2-256M-Video-Instruct-Q8_0.gguf`, `${HF}/ggml-org/SmolVLM2-256M-Video-Instruct-GGUF/resolve/main/mmproj-SmolVLM2-256M-Video-Instruct-Q8_0.gguf`, 450_000_000, { params: '256M' }),
  'smolvlm2-500m-video-instruct-q8_0': vlm('SmolVLM2 500M Video Instruct Q8_0', `${HF}/ggml-org/SmolVLM2-500M-Video-Instruct-GGUF/resolve/main/SmolVLM2-500M-Video-Instruct-Q8_0.gguf`, `${HF}/ggml-org/SmolVLM2-500M-Video-Instruct-GGUF/resolve/main/mmproj-SmolVLM2-500M-Video-Instruct-Q8_0.gguf`, 800_000_000, { params: '500M' }),
  'smolvlm-500m-instruct-q8_0': archive('vlm', 'llamaCpp', 'SmolVLM 500M Instruct', `${REL}/runanywhere-vlm-models-v1/smolvlm-500m-instruct-q8_0.tar.gz`, 600_000_000, 'directoryBased', { params: '500M' }),
  'qwen2-vl-2b-instruct-q4_k_m': vlm('Qwen2-VL 2B Instruct', `${HF}/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/Qwen2-VL-2B-Instruct-Q4_K_M.gguf`, `${HF}/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf`, 1_800_000_000, { params: '2B', heavy: true }),
  'qwen2.5-vl-3b-instruct-q4_k_m': vlm('Qwen2.5-VL 3B Instruct Q4_K_M', `${HF}/ggml-org/Qwen2.5-VL-3B-Instruct-GGUF/resolve/main/Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf`, `${HF}/ggml-org/Qwen2.5-VL-3B-Instruct-GGUF/resolve/main/mmproj-Qwen2.5-VL-3B-Instruct-Q8_0.gguf`, 2_800_000_000, { params: '3B', heavy: true }),
  'lfm2-vl-450m-q8_0': vlm('LFM2-VL 450M', `${HF}/runanywhere/LFM2-VL-450M-GGUF/resolve/main/LFM2-VL-450M-Q8_0.gguf`, `${HF}/runanywhere/LFM2-VL-450M-GGUF/resolve/main/mmproj-LFM2-VL-450M-Q8_0.gguf`, 600_000_000, { params: '450M' }),
  'gemma-4-e2b-it-q8_0': vlm('Gemma 4 E2B IT Q8_0', `${HF}/ggml-org/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q8_0.gguf`, `${HF}/ggml-org/gemma-4-E2B-it-GGUF/resolve/main/mmproj-gemma-4-E2B-it-Q8_0.gguf`, 3_000_000_000, { params: '2B', heavy: true }),
  'gemma-4-e4b-it-q4_k_m': vlm('Gemma 4 E4B IT Q4_K_M', `${HF}/ggml-org/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf`, `${HF}/ggml-org/gemma-4-E4B-it-GGUF/resolve/main/mmproj-gemma-4-E4B-it-Q8_0.gguf`, 5_500_000_000, { params: '4B', heavy: true }),
  'fara1.5-4b-q4_k_m': vlm('Fara1.5 4B Computer-Use Agent Q4_K_M', `${HF}/runanywhere/Fara1.5-4B-GGUF/resolve/main/Fara1.5-4B-Q4_K_M.gguf`, `${HF}/runanywhere/Fara1.5-4B-GGUF/resolve/main/mmproj-Fara1.5-4B-f16.gguf`, 3_300_000_000, { params: '4B', heavy: true }),

  // ---- STT (sherpa-onnx) ----
  'sherpa-nemo-canary-180m-flash-int8': multi('stt', 'sherpa', 'NVIDIA Canary 180M Flash INT8', [
    `${HF}/csukuangfj/sherpa-onnx-nemo-canary-180m-flash-en-es-de-fr-int8/resolve/9077164e0d3dd1d5353743e89ceaa1d3a770838c/encoder.int8.onnx`,
    `${HF}/csukuangfj/sherpa-onnx-nemo-canary-180m-flash-en-es-de-fr-int8/resolve/9077164e0d3dd1d5353743e89ceaa1d3a770838c/decoder.int8.onnx`,
    `${HF}/csukuangfj/sherpa-onnx-nemo-canary-180m-flash-en-es-de-fr-int8/resolve/9077164e0d3dd1d5353743e89ceaa1d3a770838c/tokens.txt`,
  ], 207_170_046, { params: '180M' }),
  'sherpa-nemo-parakeet-tdt-ctc-110m-en-int8': multi('stt', 'sherpa', 'NVIDIA Parakeet TDT-CTC 110M EN', [
    [`${HF}/csukuangfj/sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000/resolve/3af92f152d32c836acabf38f4c993bc96b80eb2d/model.onnx`, 'model.onnx'],
    [`${HF}/csukuangfj/sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000/resolve/3af92f152d32c836acabf38f4c993bc96b80eb2d/tokens.txt`, 'tokens.txt'],
  ], 458_170_974, { params: '110M' }),
  'sherpa-nemo-parakeet-tdt-0.6b-v2-int8': multi('stt', 'sherpa', 'NVIDIA Parakeet TDT 0.6B v2 INT8', [
    `${HF}/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8/resolve/1ab9323565ddb038682214b292f588070a538ce2/encoder.int8.onnx`,
    `${HF}/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8/resolve/1ab9323565ddb038682214b292f588070a538ce2/decoder.int8.onnx`,
    `${HF}/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8/resolve/1ab9323565ddb038682214b292f588070a538ce2/joiner.int8.onnx`,
    `${HF}/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8/resolve/1ab9323565ddb038682214b292f588070a538ce2/tokens.txt`,
  ], 661_190_513, { params: '0.6B', heavy: true }),
  'sherpa-onnx-whisper-tiny.en': archive('stt', 'sherpa', 'Sherpa Whisper Tiny (ONNX)', `${REL}/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz`, 75_000_000, 'nestedDirectory', { params: '39M' }),

  // ---- TTS (sherpa-onnx Piper VITS) ----
  'vits-piper-en_US-lessac-medium': archive('tts', 'sherpa', 'Piper TTS (US English, Medium)', `${REL}/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz`, 65_000_000),
  'vits-piper-en_GB-alba-medium': archive('tts', 'sherpa', 'Piper TTS (British English)', `${REL}/runanywhere-models-v1/vits-piper-en_GB-alba-medium.tar.gz`, 65_000_000),

  // ---- Embeddings ----
  'all-minilm-l6-v2': multi('embedder', 'onnx', 'All MiniLM L6 v2', [
    [`${HF}/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model_quantized.onnx`, 'model.onnx'],
    [`${HF}/Xenova/all-MiniLM-L6-v2/resolve/main/vocab.txt`, 'vocab.txt'],
  ], 23_203_878, { params: '22M' }),
  'nemotron-3-embed-1b-q4_k_m': single('embedder', 'llamaCpp', 'NVIDIA Nemotron 3 Embed 1B Q4_K_M', `${HF}/zenmagnets/Nemotron-3-Embed-1B-Q4_K_M-GGUF/resolve/06df1fde6f7009c91f6cc3cd520081921929a678/nemotron-3-embed-1b-q4_k_m.gguf`, 749_352_096, { params: '1B' }),
  'llama-nemotron-embed-1b-v2-q4_k_m': single('embedder', 'llamaCpp', 'NVIDIA Llama Nemotron Embed 1B v2 Q4_K_M', `${HF}/mykor/llama-nemotron-embed-1b-v2-GGUF/resolve/bf7c9832b1d76f86777379e58b7b74805ee58006/llama-nemotron-embed-1B-v2-Q4_K_M.gguf`, 807_690_624, { params: '1B' }),

  // ---- Speaker diarization (ONNX, NVIDIA Sortformer) ----
  'sortformer-4spk': multi('diarization', 'onnx', 'Sortformer 4-speaker diarization', [['https://huggingface.co/cgus/diar_streaming_sortformer_4spk-v2.1-onnx/resolve/main/diar_streaming_sortformer_4spk-v2.1.onnx', 'model.onnx']], 113_000_000, { params: '4spk' }),

  // ---- VAD (Silero, ONNX) ----
  'silero-vad': single('vad', 'onnx', 'Silero VAD', 'https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx', 2_327_524),

  // ---- Semantic segmentation (ONNX) ----
  'segformer-b0-ade20k': multi('segmentation', 'onnx', 'SegFormer B0 ADE20K', [
    [`${HF}/Xenova/segformer-b0-finetuned-ade-512-512/resolve/d3e5499fa8701ff0453ca940a8dfeae39b2f1504/onnx/model.onnx`, 'model.onnx'],
    [`${HF}/Xenova/segformer-b0-finetuned-ade-512-512/resolve/d3e5499fa8701ff0453ca940a8dfeae39b2f1504/config.json`, 'config.json'],
    [`${HF}/Xenova/segformer-b0-finetuned-ade-512-512/resolve/d3e5499fa8701ff0453ca940a8dfeae39b2f1504/preprocessor_config.json`, 'preprocessor_config.json'],
  ], 15_342_776, { params: 'B0' }),
};

module.exports = { CATALOG };
