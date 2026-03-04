/**
 * AnalyticsEventsBridge.ts
 *
 * Bridges C++ analytics events (rac_analytics_events_set_callback) to the
 * TypeScript EventBus. Mirrors the role of TelemetryBridge.cpp in React Native.
 *
 * Responsibilities:
 * 1. Register a JS function pointer via module.addFunction() using Emscripten's
 *    dynamic function table — signature 'viii' (void, i32 type, ptr data, ptr userData)
 * 2. Call _rac_analytics_events_set_callback(callbackPtr, 0) to wire up WASM
 * 3. On each callback: read event_type + union fields from WASM memory
 * 4. Emit typed events to TypeScript EventBus
 * 5. Forward raw event+data to TelemetryService for batching
 */

import { EventBus, SDKEventType, SDKLogger } from '@runanywhere/web';
import type { LlamaCppModule } from './LlamaCppBridge';

const logger = new SDKLogger('AnalyticsEventsBridge');

// ---------------------------------------------------------------------------
// C++ rac_event_type_t constants (from rac_analytics_events.h)
// ---------------------------------------------------------------------------

const enum RACEventType {
  // LLM (100-199)
  LLM_MODEL_LOAD_STARTED   = 100,
  LLM_MODEL_LOAD_COMPLETED = 101,
  LLM_MODEL_LOAD_FAILED    = 102,
  LLM_MODEL_UNLOADED       = 103,
  LLM_GENERATION_STARTED   = 110,
  LLM_GENERATION_COMPLETED = 111,
  LLM_GENERATION_FAILED    = 112,
  LLM_FIRST_TOKEN          = 113,
  LLM_STREAMING_UPDATE     = 114,

  // STT (200-299)
  STT_MODEL_LOAD_STARTED    = 200,
  STT_MODEL_LOAD_COMPLETED  = 201,
  STT_MODEL_LOAD_FAILED     = 202,
  STT_MODEL_UNLOADED        = 203,
  STT_TRANSCRIPTION_STARTED   = 210,
  STT_TRANSCRIPTION_COMPLETED = 211,
  STT_TRANSCRIPTION_FAILED    = 212,
  STT_PARTIAL_TRANSCRIPT      = 213,

  // TTS (300-399)
  TTS_VOICE_LOAD_STARTED   = 300,
  TTS_VOICE_LOAD_COMPLETED = 301,
  TTS_VOICE_LOAD_FAILED    = 302,
  TTS_VOICE_UNLOADED       = 303,
  TTS_SYNTHESIS_STARTED    = 310,
  TTS_SYNTHESIS_COMPLETED  = 311,
  TTS_SYNTHESIS_FAILED     = 312,
  TTS_SYNTHESIS_CHUNK      = 313,

  // VAD (400-499)
  VAD_STARTED       = 400,
  VAD_STOPPED       = 401,
  VAD_SPEECH_STARTED = 402,
  VAD_SPEECH_ENDED   = 403,
  VAD_PAUSED        = 404,
  VAD_RESUMED       = 405,

  // Voice Agent (500-599)
  VOICE_AGENT_TURN_STARTED      = 500,
  VOICE_AGENT_TURN_COMPLETED    = 501,
  VOICE_AGENT_TURN_FAILED       = 502,
  VOICE_AGENT_STT_STATE_CHANGED = 510,
  VOICE_AGENT_LLM_STATE_CHANGED = 511,
  VOICE_AGENT_TTS_STATE_CHANGED = 512,
  VOICE_AGENT_ALL_READY         = 513,

  // SDK Lifecycle (600-699)
  SDK_INIT_STARTED   = 600,
  SDK_INIT_COMPLETED = 601,
  SDK_INIT_FAILED    = 602,
  SDK_MODELS_LOADED  = 603,

  // Model Download (700-719)
  MODEL_DOWNLOAD_STARTED    = 700,
  MODEL_DOWNLOAD_PROGRESS   = 701,
  MODEL_DOWNLOAD_COMPLETED  = 702,
  MODEL_DOWNLOAD_FAILED     = 703,
  MODEL_DOWNLOAD_CANCELLED  = 704,

  // Model Extraction (710-719)
  MODEL_EXTRACTION_STARTED   = 710,
  MODEL_EXTRACTION_PROGRESS  = 711,
  MODEL_EXTRACTION_COMPLETED = 712,
  MODEL_EXTRACTION_FAILED    = 713,

  // Model Deletion (720-729)
  MODEL_DELETED = 720,

  // Storage (800-899)
  STORAGE_CACHE_CLEARED      = 800,
  STORAGE_CACHE_CLEAR_FAILED = 801,
  STORAGE_TEMP_CLEANED       = 802,

  // Device (900-999)
  DEVICE_REGISTERED          = 900,
  DEVICE_REGISTRATION_FAILED = 901,

  // Network (1000-1099)
  NETWORK_CONNECTIVITY_CHANGED = 1000,

  // Error (1100-1199)
  SDK_ERROR = 1100,

  // Framework (1200-1299)
  FRAMEWORK_MODELS_REQUESTED = 1200,
  FRAMEWORK_MODELS_RETRIEVED = 1201,
}

// ---------------------------------------------------------------------------
// Callback for TelemetryService
// ---------------------------------------------------------------------------

export type AnalyticsEventCallback = (eventType: number, dataPtr: number) => void;

// ---------------------------------------------------------------------------
// AnalyticsEventsBridge
// ---------------------------------------------------------------------------

/**
 * Registers the analytics callback with the WASM module and translates
 * C++ analytics events into TypeScript EventBus emissions.
 */
export class AnalyticsEventsBridge {
  private _module: LlamaCppModule | null = null;
  private _callbackPtr: number = 0;
  private _telemetryCallback: AnalyticsEventCallback | null = null;

  /**
   * Register this bridge with the WASM module.
   * Must be called after the module is loaded.
   */
  register(module: LlamaCppModule, telemetryCallback?: AnalyticsEventCallback): void {
    if (this._callbackPtr !== 0) {
      logger.warning('AnalyticsEventsBridge already registered');
      return;
    }

    this._module = module;
    this._telemetryCallback = telemetryCallback ?? null;

    if (typeof module._rac_analytics_events_set_callback !== 'function') {
      logger.warning('_rac_analytics_events_set_callback not available in WASM module');
      return;
    }

    // Register JS function as WASM function pointer.
    // Signature 'viii': void(i32 type, i32 dataPtr, i32 userData)
    this._callbackPtr = module.addFunction(
      (eventType: number, dataPtr: number, _userData: number) => {
        this.handleEvent(eventType, dataPtr);
      },
      'viii',
    );

    const result = module._rac_analytics_events_set_callback(this._callbackPtr, 0);
    if (result === 0) {
      logger.info('Analytics events callback registered');
    } else {
      logger.warning(`Analytics events callback registration returned: ${result}`);
    }
  }

  /**
   * Unregister and free the function pointer.
   */
  cleanup(): void {
    if (!this._module || this._callbackPtr === 0) return;

    if (typeof this._module._rac_analytics_events_set_callback === 'function') {
      this._module._rac_analytics_events_set_callback(0, 0);
    }

    if (typeof this._module.removeFunction === 'function') {
      this._module.removeFunction(this._callbackPtr);
    }

    this._callbackPtr = 0;
    this._module = null;
    this._telemetryCallback = null;
    logger.debug('Analytics events callback unregistered');
  }

  // ---------------------------------------------------------------------------
  // Event dispatch
  // ---------------------------------------------------------------------------

  private handleEvent(eventType: number, dataPtr: number): void {
    // Forward to TelemetryService (before reading memory, which is valid only during callback)
    if (this._telemetryCallback) {
      try {
        this._telemetryCallback(eventType, dataPtr);
      } catch {
        // Silent — telemetry must never crash the app
      }
    }

    // Emit to public TypeScript EventBus
    try {
      this.emitToEventBus(eventType, dataPtr);
    } catch {
      // Silent — analytics events must never crash the app
    }
  }

  private emitToEventBus(eventType: number, dataPtr: number): void {
    const m = this._module;
    if (!m) return;

    // The rac_analytics_event_data_t struct layout (WASM32):
    //   offset 0: int32 type  (4 bytes)
    //   offset 4: union data  (largest member determines size)
    const DATA_OFFSET = 4; // after the type field

    switch (eventType) {
      // ------- LLM events -------
      case RACEventType.LLM_GENERATION_COMPLETED: {
        // rac_analytics_llm_generation_t fields (all at DATA_OFFSET):
        //   char* generation_id   [+0]
        //   char* model_id        [+4]
        //   char* model_name      [+8]
        //   int32 input_tokens    [+12]
        //   int32 output_tokens   [+16]
        //   double duration_ms    [+20] (8 bytes, aligned to 8)
        //   double tps            [+28]
        //   int32 is_streaming    [+36]
        //   double ttft_ms        [+40] (8 bytes)
        const base = dataPtr + DATA_OFFSET;
        const modelId = this.readStringAt(m, base + 4);
        const outputTokens = m.getValue(base + 16, 'i32');
        const durationMs = m.getValue(base + 20, 'double');
        const tokensPerSec = m.getValue(base + 28, 'double');

        EventBus.shared.emit('generation.completed', SDKEventType.Generation, {
          tokensUsed: outputTokens,
          latencyMs: durationMs,
        });
        // tokensPerSec and modelId are available for observers that need them
        logger.debug(`LLM generation completed: modelId=${modelId} tps=${tokensPerSec.toFixed(1)}`);
        break;
      }

      case RACEventType.LLM_GENERATION_STARTED: {
        EventBus.shared.emit('generation.started', SDKEventType.Generation, { prompt: '' });
        break;
      }

      case RACEventType.LLM_GENERATION_FAILED: {
        const base = dataPtr + DATA_OFFSET;
        const errPtr = m.getValue(base + 60, 'i32'); // error_message is near end of struct
        const error = errPtr ? m.UTF8ToString(errPtr) : 'generation failed';
        EventBus.shared.emit('generation.failed', SDKEventType.Error, { error });
        break;
      }

      case RACEventType.LLM_MODEL_LOAD_COMPLETED: {
        // rac_analytics_llm_model_t: char* model_id [+0], char* model_name [+4], int64 size [+8], double duration_ms [+16]
        const base = dataPtr + DATA_OFFSET;
        const modelId = this.readStringAt(m, base);
        const durationMs = m.getValue(base + 16, 'double');

        EventBus.shared.emit('model.loadCompleted', SDKEventType.Model, {
          modelId,
          component: 'llm',
          category: 'llm',
          loadTimeMs: durationMs,
        });
        break;
      }

      case RACEventType.LLM_MODEL_LOAD_FAILED: {
        const base = dataPtr + DATA_OFFSET;
        const modelId = this.readStringAt(m, base);
        const errPtr = m.getValue(base + 28, 'i32');
        const error = errPtr ? m.UTF8ToString(errPtr) : 'model load failed';
        EventBus.shared.emit('model.loadFailed', SDKEventType.Model, { modelId, error });
        break;
      }

      case RACEventType.LLM_MODEL_UNLOADED: {
        const base = dataPtr + DATA_OFFSET;
        const modelId = this.readStringAt(m, base);
        EventBus.shared.emit('model.unloaded', SDKEventType.Model, { modelId, category: 'llm' });
        break;
      }

      // ------- STT events -------
      case RACEventType.STT_TRANSCRIPTION_COMPLETED: {
        // rac_analytics_stt_transcription_t (WASM32, 4-byte aligned doubles):
        //   char* transcription_id [+0], char* model_id [+4], char* model_name [+8],
        //   char* text [+12], float confidence [+16],
        //   double duration_ms [+20], double audio_length_ms [+28],
        //   int32 audio_size_bytes [+36], int32 word_count [+40],
        //   double real_time_factor [+44], char* language [+52],
        //   int32 sample_rate [+56], int32 is_streaming [+60],
        //   int32 framework [+64], int32 error_code [+68], char* error_message [+72]
        const base = dataPtr + DATA_OFFSET;
        const textPtr = m.getValue(base + 12, 'i32');
        const text = textPtr ? m.UTF8ToString(textPtr) : '';
        const confidence = m.getValue(base + 16, 'float');
        const audioDurationMs = m.getValue(base + 28, 'double');
        const wordCount = m.getValue(base + 40, 'i32');

        EventBus.shared.emit('stt.transcribed', SDKEventType.Voice, {
          text,
          confidence,
          audioDurationMs,
          wordCount,
        });
        break;
      }

      case RACEventType.STT_TRANSCRIPTION_FAILED: {
        // rac_analytics_stt_transcription_t: error_message at [+72]
        const base = dataPtr + DATA_OFFSET;
        const errPtr = m.getValue(base + 72, 'i32');
        const error = errPtr ? m.UTF8ToString(errPtr) : 'transcription failed';
        EventBus.shared.emit('stt.transcriptionFailed', SDKEventType.Error, { error });
        break;
      }

      case RACEventType.STT_MODEL_LOAD_COMPLETED: {
        const base = dataPtr + DATA_OFFSET;
        const modelId = this.readStringAt(m, base);
        EventBus.shared.emit('model.loadCompleted', SDKEventType.Model, {
          modelId,
          component: 'stt',
          category: 'stt',
        });
        break;
      }

      // ------- TTS events -------
      case RACEventType.TTS_SYNTHESIS_COMPLETED: {
        // rac_analytics_tts_synthesis_t (WASM32, 4-byte aligned doubles):
        //   char* synthesis_id [+0], char* model_id [+4], char* model_name [+8],
        //   int32 character_count [+12],
        //   double audio_duration_ms [+16], int32 audio_size_bytes [+24],
        //   double processing_duration_ms [+28], double characters_per_second [+36],
        //   int32 sample_rate [+44], int32 framework [+48],
        //   int32 error_code [+52], char* error_message [+56]
        const base = dataPtr + DATA_OFFSET;
        const characterCount = m.getValue(base + 12, 'i32');
        const audioDurationMs = m.getValue(base + 16, 'double');
        const processingMs = m.getValue(base + 28, 'double');
        const charsPerSec = m.getValue(base + 36, 'double');
        const sampleRate = m.getValue(base + 44, 'i32');

        EventBus.shared.emit('tts.synthesized', SDKEventType.Voice, {
          durationMs: audioDurationMs,
          processingMs,
          sampleRate,
          characterCount,
          charsPerSec,
        });
        logger.debug(`TTS synthesis completed: durationMs=${audioDurationMs.toFixed(0)} processingMs=${processingMs.toFixed(0)}`);
        break;
      }

      case RACEventType.TTS_SYNTHESIS_FAILED: {
        // rac_analytics_tts_synthesis_t: error_message at [+56]
        const base = dataPtr + DATA_OFFSET;
        const errPtr = m.getValue(base + 56, 'i32');
        const error = errPtr ? m.UTF8ToString(errPtr) : 'synthesis failed';
        EventBus.shared.emit('tts.synthesisFailed', SDKEventType.Error, { error });
        break;
      }

      case RACEventType.TTS_VOICE_LOAD_COMPLETED: {
        const base = dataPtr + DATA_OFFSET;
        const modelId = this.readStringAt(m, base);
        EventBus.shared.emit('model.loadCompleted', SDKEventType.Model, {
          modelId,
          component: 'tts',
          category: 'tts',
        });
        break;
      }

      // ------- VAD events -------
      case RACEventType.VAD_SPEECH_STARTED:
        EventBus.shared.emit('vad.speechStarted', SDKEventType.Voice, { activity: 'started' });
        break;

      case RACEventType.VAD_SPEECH_ENDED: {
        // rac_analytics_vad_t: double speech_duration_ms [+0], float energy_level [+8]
        const base = dataPtr + DATA_OFFSET;
        const speechDurationMs = m.getValue(base, 'double');
        EventBus.shared.emit('vad.speechEnded', SDKEventType.Voice, {
          activity: 'ended',
          speechDurationMs,
        });
        break;
      }

      // ------- Model download events -------
      case RACEventType.MODEL_DOWNLOAD_PROGRESS: {
        // rac_analytics_model_download_t: char* model_id [+0], double progress [+4 or aligned 8], int64 bytes_downloaded, int64 total_bytes
        const base = dataPtr + DATA_OFFSET;
        const modelId = this.readStringAt(m, base);
        // progress field: after char* (4 bytes), aligned to 8 → offset 8
        const progress = m.getValue(base + 8, 'double');
        const bytesDownloaded = m.getValue(base + 16, 'i64') as unknown as number;
        const totalBytes = m.getValue(base + 24, 'i64') as unknown as number;

        EventBus.shared.emit('model.downloadProgress', SDKEventType.Model, {
          modelId,
          progress,
          bytesDownloaded,
          totalBytes,
        });
        break;
      }

      case RACEventType.MODEL_DOWNLOAD_COMPLETED: {
        const base = dataPtr + DATA_OFFSET;
        const modelId = this.readStringAt(m, base);
        const sizeBytes = m.getValue(base + 40, 'i64') as unknown as number; // size_bytes field

        EventBus.shared.emit('model.downloadCompleted', SDKEventType.Model, {
          modelId,
          sizeBytes,
        });
        break;
      }

      case RACEventType.MODEL_DOWNLOAD_FAILED: {
        const base = dataPtr + DATA_OFFSET;
        const modelId = this.readStringAt(m, base);
        const errPtr = m.getValue(base + 56, 'i32');
        const error = errPtr ? m.UTF8ToString(errPtr) : 'download failed';
        EventBus.shared.emit('model.downloadFailed', SDKEventType.Model, { modelId, error });
        break;
      }

      default:
        // Other events (SDK lifecycle, storage, etc.) are telemetry-only
        logger.debug(`Unhandled analytics event type: ${eventType}`);
        break;
    }
  }

  private readStringAt(m: LlamaCppModule, ptrAddr: number): string {
    const ptr = m.getValue(ptrAddr, 'i32');
    if (!ptr) return '';
    return m.UTF8ToString(ptr);
  }
}
