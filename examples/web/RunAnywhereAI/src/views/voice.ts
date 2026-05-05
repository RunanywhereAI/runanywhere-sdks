/**
 * Voice Tab — placeholder.
 *
 * The voice agent view previously consumed
 * `RunAnywhere.streamVoiceAgent(...)` over a composed transport that fed
 * mic samples through VAD → STT → LLM → TTS. The composed transport
 * required STT/TTS/VAD providers from the ONNX backend package and an LLM
 * provider from the llamacpp backend package; both were emptied in the V2
 * cleanup.
 */

import type { TabLifecycle } from '../app';
import { renderFeatureUnavailable } from '../components/feature-unavailable';

export function initVoiceTab(el: HTMLElement): TabLifecycle {
  renderFeatureUnavailable(el, {
    title: 'Voice',
    description:
      'Real-time voice agent (VAD → STT → LLM → TTS). Returns once the ' +
      "proto-byte voice agent handle is installed via `setRunanywhereModule`.",
    requires: [
      'RunAnywhere.streamVoiceAgent',
      'AudioCapture',
      'AudioPlayback',
      'VADProtoAdapter',
      'STTProtoAdapter',
      'TTSProtoAdapter',
    ],
  });

  return {};
}
