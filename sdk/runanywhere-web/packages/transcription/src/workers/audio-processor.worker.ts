import { WhisperService } from '../services/whisper-service';
import type { WhisperConfig } from '../types';

let whisperService: WhisperService | null = null;

interface WorkerMessage {
  type: string;
  payload?: any;
  id?: string;
}

self.addEventListener('message', async (event: MessageEvent<WorkerMessage>) => {
  const { type, payload, id } = event.data;

  switch (type) {
    case 'initialize':
      try {
        whisperService = new WhisperService(payload.config as WhisperConfig);

        // Forward events to main thread
        whisperService.on('downloadProgress', (progress) => {
          self.postMessage({
            type: 'downloadProgress',
            payload: progress
          });
        });

        whisperService.on('partialTranscription', (partial) => {
          self.postMessage({
            type: 'partialTranscription',
            payload: partial
          });
        });

        const result = await whisperService.initialize();

        self.postMessage({
          type: 'initializeComplete',
          id,
          payload: result.success ? null : result.error
        });
      } catch (error) {
        self.postMessage({
          type: 'initializeError',
          id,
          payload: error
        });
      }
      break;

    case 'transcribe':
      if (!whisperService) {
        self.postMessage({
          type: 'transcribeError',
          id,
          payload: new Error('Service not initialized')
        });
        return;
      }

      try {
        const result = await whisperService.transcribe(
          payload.audio,
          payload.options
        );

        self.postMessage({
          type: 'transcribeComplete',
          id,
          payload: result.success ? result.value : null,
          error: result.success ? null : result.error
        });
      } catch (error) {
        self.postMessage({
          type: 'transcribeError',
          id,
          payload: error
        });
      }
      break;

    case 'cancel':
      whisperService?.cancel();
      self.postMessage({
        type: 'cancelComplete',
        id
      });
      break;

    case 'destroy':
      whisperService?.destroy();
      whisperService = null;
      self.postMessage({
        type: 'destroyComplete',
        id
      });
      break;
  }
});

// Handle worker errors
self.addEventListener('error', (event) => {
  self.postMessage({
    type: 'workerError',
    payload: event.error
  });
});
