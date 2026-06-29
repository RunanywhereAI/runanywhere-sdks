/**
 * Param list for the self-contained NPU (QHexRT) section's nested stack.
 * Home is the section root (reached from More → NPU); the others are pushed.
 */
export type NpuStackParamList = {
  Home: undefined;
  Llm: undefined;
  Vlm: undefined;
  Stt: undefined;
  Tts: undefined;
};
