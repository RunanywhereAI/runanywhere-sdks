export const WHISPER_WEB_CONSTANTS = {
  SAMPLING_RATE: 16000,
  DEFAULT_SUBTASK: "transcribe" as const,
  DEFAULT_DTYPE: "q8" as const,
  DEFAULT_GPU: false,
  DEFAULT_QUANTIZED: true,
};

export const MODELS: Record<string, [string, string]> = {
  "onnx-community/whisper-tiny": ["tiny", ""],
  "onnx-community/whisper-base": ["base", ""],
  "onnx-community/whisper-small": ["small", ""],
  "onnx-community/whisper-medium-ONNX": ["medium", ""],
  "onnx-community/whisper-large-v3-turbo": ["large-v3-turbo", ""],
};

export const DTYPES: string[] = [
  "fp32", "fp16", "q8", "int8", "uint8", "q4", "bnb4", "q4f16"
];
