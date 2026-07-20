/**
 * ONNX/Sherpa BackendWorker entrypoint (scaffold).
 *
 * Speech modalities still load on the main-thread SherpaONNXBridge today.
 * This worker completes the BackendWorker handshake so apps can probe
 * worker availability; load/stream handlers remain unimplemented until the
 * Sherpa ownership migration mirrors LlamaCPP.
 */

import {
  runBackendWorker,
  type BackendWorkerScope,
} from '@runanywhere/web/backend';

runBackendWorker(self as unknown as BackendWorkerScope, {
  async init(): Promise<void> {
    // Handshake only — model ownership stays on the main-thread bridge until
    // STT/TTS lifecycle streams move here (parity with LlamaCPP backendWorker).
  },
  health() {
    return {
      healthy: true,
      details: { backend: 'onnx-sherpa', ownership: 'main-thread' },
    };
  },
});
