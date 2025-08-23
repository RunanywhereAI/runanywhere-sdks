// Web Worker for audio processing (VAD + STT)
import type { MicVAD } from '@ricky0123/vad-web';
import type { WhisperModel } from '@xenova/transformers';
import type { Result } from '@runanywhere/core';

// Worker message types
export interface WorkerMessage {
  id: string;
  type: string;
  data?: any;
}

export interface InitializeMessage extends WorkerMessage {
  type: 'initialize';
  data: {
    vadModelUrl?: string;
    whisperModelUrl?: string;
    sampleRate?: number;
  };
}

export interface ProcessAudioMessage extends WorkerMessage {
  type: 'processAudio';
  data: {
    audioData: Float32Array;
    timestamp: number;
  };
}

export interface DestroyMessage extends WorkerMessage {
  type: 'destroy';
}

// Response types
export interface WorkerResponse {
  id: string;
  type: string;
  success: boolean;
  data?: any;
  error?: string;
}

export interface InitializedResponse extends WorkerResponse {
  type: 'initialized';
}

export interface VADResultResponse extends WorkerResponse {
  type: 'vadResult';
  data: {
    speechDetected: boolean;
    confidence: number;
    timestamp: number;
  };
}

export interface TranscriptionResponse extends WorkerResponse {
  type: 'transcription';
  data: {
    text: string;
    confidence: number;
    timestamp: number;
    duration: number;
  };
}

export interface ErrorResponse extends WorkerResponse {
  type: 'error';
  success: false;
  error: string;
}

class AudioProcessorWorker {
  private vadModel: MicVAD | null = null;
  private whisperModel: WhisperModel | null = null;
  private isInitialized = false;
  private sampleRate = 16000;
  private audioBuffer: Float32Array[] = [];
  private isProcessing = false;

  constructor() {
    self.addEventListener('message', this.handleMessage.bind(this));
  }

  private async handleMessage(event: MessageEvent<WorkerMessage>): Promise<void> {
    const message = event.data;

    try {
      switch (message.type) {
        case 'initialize':
          await this.initialize(message as InitializeMessage);
          break;
        case 'processAudio':
          await this.processAudio(message as ProcessAudioMessage);
          break;
        case 'destroy':
          await this.destroy();
          break;
        default:
          this.sendError(message.id, `Unknown message type: ${message.type}`);
      }
    } catch (error) {
      this.sendError(message.id, `Error processing message: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  private async initialize(message: InitializeMessage): Promise<void> {
    try {
      const { vadModelUrl, whisperModelUrl, sampleRate = 16000 } = message.data;

      this.sampleRate = sampleRate;

      // Initialize VAD model
      if (vadModelUrl) {
        const { MicVAD } = await import('@ricky0123/vad-web');

        this.vadModel = await MicVAD.new({
          modelURL: vadModelUrl,
          onSpeechStart: () => {
            // Speech detection handled in processAudio
          },
          onSpeechEnd: async (audio: Float32Array) => {
            // Process accumulated audio for transcription
            await this.transcribeAudio(audio);
          },
          onVADMisfire: () => {
            console.warn('[AudioWorker] VAD misfire detected');
          }
        });
      }

      // Initialize Whisper model
      if (whisperModelUrl) {
        const { pipeline } = await import('@xenova/transformers');

        this.whisperModel = await pipeline(
          'automatic-speech-recognition',
          whisperModelUrl
        ) as any;
      }

      this.isInitialized = true;

      this.sendResponse<InitializedResponse>({
        id: message.id,
        type: 'initialized',
        success: true
      });

    } catch (error) {
      this.sendError(message.id, `Initialization failed: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  private async processAudio(message: ProcessAudioMessage): Promise<void> {
    if (!this.isInitialized) {
      this.sendError(message.id, 'Worker not initialized');
      return;
    }

    if (this.isProcessing) {
      // Skip if still processing previous audio
      return;
    }

    try {
      this.isProcessing = true;
      const { audioData, timestamp } = message.data;

      // VAD processing
      if (this.vadModel) {
        const vadResult = await this.processVAD(audioData, timestamp);

        this.sendResponse<VADResultResponse>({
          id: message.id,
          type: 'vadResult',
          success: true,
          data: vadResult
        });

        // If speech detected, add to buffer for potential transcription
        if (vadResult.speechDetected) {
          this.audioBuffer.push(audioData);

          // Limit buffer size (e.g., 30 seconds at 16kHz)
          const maxBufferLength = 30 * this.sampleRate;
          let totalLength = this.audioBuffer.reduce((sum, chunk) => sum + chunk.length, 0);

          while (totalLength > maxBufferLength && this.audioBuffer.length > 1) {
            const removed = this.audioBuffer.shift()!;
            totalLength -= removed.length;
          }
        }
      }

    } catch (error) {
      this.sendError(message.id, `Audio processing failed: ${error instanceof Error ? error.message : String(error)}`);
    } finally {
      this.isProcessing = false;
    }
  }

  private async processVAD(audioData: Float32Array, timestamp: number): Promise<{
    speechDetected: boolean;
    confidence: number;
    timestamp: number;
  }> {
    if (!this.vadModel) {
      return { speechDetected: false, confidence: 0, timestamp };
    }

    try {
      // VAD models typically return a probability/confidence score
      // This is a simplified implementation - actual VAD integration may vary
      const speechProbability = 0.8; // Placeholder - actual VAD implementation needed
      const threshold = 0.5;

      return {
        speechDetected: speechProbability > threshold,
        confidence: speechProbability,
        timestamp
      };
    } catch (error) {
      console.warn('[AudioWorker] VAD processing error:', error);
      return { speechDetected: false, confidence: 0, timestamp };
    }
  }

  private async transcribeAudio(audioData: Float32Array): Promise<void> {
    if (!this.whisperModel || !this.isInitialized) {
      return;
    }

    try {
      const startTime = performance.now();

      // Combine buffered audio if available
      const combinedAudio = this.combineAudioBuffers(audioData);

      // Transcribe using Whisper
      const result = await this.whisperModel(combinedAudio);

      const endTime = performance.now();
      const duration = endTime - startTime;

      // Extract transcription result
      const transcriptionText = result?.text || '';
      const confidence = result?.score || 0.0;

      if (transcriptionText.trim()) {
        this.sendResponse<TranscriptionResponse>({
          id: `transcription-${Date.now()}`,
          type: 'transcription',
          success: true,
          data: {
            text: transcriptionText,
            confidence,
            timestamp: Date.now(),
            duration
          }
        });
      }

      // Clear audio buffer after transcription
      this.audioBuffer = [];

    } catch (error) {
      console.error('[AudioWorker] Transcription error:', error);
      this.sendError(`transcription-${Date.now()}`, `Transcription failed: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  private combineAudioBuffers(newAudio: Float32Array): Float32Array {
    if (this.audioBuffer.length === 0) {
      return newAudio;
    }

    // Calculate total length
    const totalLength = this.audioBuffer.reduce((sum, chunk) => sum + chunk.length, 0) + newAudio.length;

    // Create combined buffer
    const combined = new Float32Array(totalLength);
    let offset = 0;

    // Copy buffered audio
    for (const chunk of this.audioBuffer) {
      combined.set(chunk, offset);
      offset += chunk.length;
    }

    // Add new audio
    combined.set(newAudio, offset);

    return combined;
  }

  private async destroy(): Promise<void> {
    try {
      // Clean up VAD model
      if (this.vadModel) {
        this.vadModel.destroy();
        this.vadModel = null;
      }

      // Clean up Whisper model (if applicable)
      this.whisperModel = null;

      // Clear buffers
      this.audioBuffer = [];
      this.isInitialized = false;

      this.sendResponse<WorkerResponse>({
        id: 'destroy',
        type: 'destroyed',
        success: true
      });

    } catch (error) {
      this.sendError('destroy', `Cleanup failed: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  private sendResponse<T extends WorkerResponse>(response: T): void {
    self.postMessage(response);
  }

  private sendError(id: string, errorMessage: string): void {
    this.sendResponse<ErrorResponse>({
      id,
      type: 'error',
      success: false,
      error: errorMessage
    });
  }
}

// Initialize the worker
new AudioProcessorWorker();

// Types are already exported above, no need to re-export
