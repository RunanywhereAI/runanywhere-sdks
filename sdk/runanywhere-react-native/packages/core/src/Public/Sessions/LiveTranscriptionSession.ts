/**
 * LiveTranscriptionSession.ts
 *
 * High-level API for live/streaming transcription. Combines audio capture
 * and streaming transcription into a single abstraction. RN counterpart of
 * the Swift `@MainActor` `ObservableObject` in
 * `Sources/RunAnywhere/Public/Sessions/LiveTranscriptionSession.swift`.
 *
 * The Swift class uses Combine `@Published` properties; the RN version
 * exposes the same state via:
 *   - getter properties for synchronous reads
 *   - `transcriptions: AsyncIterable<string>` async stream for
 *     `for await` consumption
 *   - `subscribe(listener)` for legacy callback-style consumption
 *     (React components can wire this into `useState` / `useEffect`)
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Sessions/LiveTranscriptionSession.swift
 */

import { AudioCaptureManager } from '../../Features/VoiceSession/AudioCaptureManager';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import {
  transcribeStream,
  stopStreamingTranscription,
} from '../Extensions/RunAnywhere+STT';
import {
  type STTOptions,
  STTLanguage,
} from '@runanywhere/proto-ts/stt_options';

/** Default proto STTOptions for live transcription. */
function defaultLiveSTTOptions(): STTOptions {
  return {
    language: STTLanguage.STT_LANGUAGE_AUTO,
    enablePunctuation: true,
    enableDiarization: false,
    maxSpeakers: 0,
    vocabularyList: [],
    enableWordTimestamps: false,
    beamSize: 0,
  };
}

/**
 * Errors specific to live transcription.
 *
 * Matches Swift `LiveTranscriptionError` (microphonePermissionDenied /
 * alreadyActive / notActive).
 */
export class LiveTranscriptionError extends Error {
  readonly code: 'microphone_permission_denied' | 'already_active' | 'not_active';

  constructor(
    code: 'microphone_permission_denied' | 'already_active' | 'not_active',
    message: string
  ) {
    super(message);
    this.code = code;
    this.name = 'LiveTranscriptionError';
  }

  static microphonePermissionDenied(): LiveTranscriptionError {
    return new LiveTranscriptionError(
      'microphone_permission_denied',
      'Microphone permission is required for live transcription'
    );
  }

  static alreadyActive(): LiveTranscriptionError {
    return new LiveTranscriptionError(
      'already_active',
      'Live transcription session is already active'
    );
  }

  static notActive(): LiveTranscriptionError {
    return new LiveTranscriptionError(
      'not_active',
      'Live transcription session is not active'
    );
  }
}

/** Listener for live transcription state changes (React-friendly). */
export interface LiveTranscriptionListener {
  onText?: (text: string) => void;
  onAudioLevel?: (level: number) => void;
  onActiveChange?: (active: boolean) => void;
  onError?: (error: Error) => void;
}

/**
 * Live transcription session.
 *
 * Mirrors Swift's `LiveTranscriptionSession`. Use `transcriptions` to
 * `for await` over partial text, or call `subscribe()` to register
 * imperative callbacks (handy from React components).
 *
 * Example usage:
 * ```ts
 * const session = await RunAnywhere.startLiveTranscription();
 *
 * // Async-iterable consumption
 * for await (const text of session.transcriptions) {
 *   console.log('Partial:', text);
 * }
 *
 * // Or callback-style for React components
 * const unsubscribe = session.subscribe({ onText: setText });
 * await session.stop();
 * unsubscribe();
 * ```
 */
export class LiveTranscriptionSession {
  private readonly logger = new SDKLogger('LiveTranscription');
  private readonly audioCapture: AudioCaptureManager;
  private readonly options: STTOptions;
  private readonly listeners = new Set<LiveTranscriptionListener>();

  private _currentText = '';
  private _isActive = false;
  private _audioLevel = 0;
  private _error: Error | null = null;

  // Async-iterable backing store. Each entry corresponds to a partial result.
  private readonly textQueue: string[] = [];
  private textResolver: ((value: IteratorResult<string>) => void) | null = null;
  private streamFinished = false;

  constructor(options: STTOptions = defaultLiveSTTOptions()) {
    this.audioCapture = new AudioCaptureManager({ sampleRate: 16000 });
    this.options = options;
  }

  // ------------------------------------------------------------------------
  // Published state (matches Swift's `@Published` properties)
  // ------------------------------------------------------------------------

  /** Current transcription text (updates in real-time). */
  get currentText(): string {
    return this._currentText;
  }

  /** Whether the session is actively transcribing. */
  get isActive(): boolean {
    return this._isActive;
  }

  /** Current audio level (0.0 - 1.0) for visualization. */
  get audioLevel(): number {
    return this._audioLevel;
  }

  /** Last transcription error, if any. */
  get error(): Error | null {
    return this._error;
  }

  /** Get the final transcription text. Matches Swift's `finalText`. */
  get finalText(): string {
    return this._currentText;
  }

  // ------------------------------------------------------------------------
  // Async-iterable transcription stream
  // ------------------------------------------------------------------------

  /**
   * Async-iterable stream of transcription text updates. Each iteration
   * yields the latest partial text. Equivalent to Swift's
   * `transcriptions: AsyncStream<String>`.
   */
  get transcriptions(): AsyncIterable<string> {
    const session = this;
    return {
      [Symbol.asyncIterator](): AsyncIterator<string> {
        return session.makeTextIterator();
      },
    };
  }

  private makeTextIterator(): AsyncIterator<string> {
    const session = this;
    return {
      next: async (): Promise<IteratorResult<string>> => {
        if (session.textQueue.length > 0) {
          return { value: session.textQueue.shift()!, done: false };
        }
        if (session.streamFinished) {
          return { value: undefined as unknown as string, done: true };
        }
        return new Promise<IteratorResult<string>>((resolve) => {
          session.textResolver = resolve;
        });
      },
      return: async (): Promise<IteratorResult<string>> => {
        session.streamFinished = true;
        if (session.textResolver) {
          session.textResolver({ value: undefined as unknown as string, done: true });
          session.textResolver = null;
        }
        return { value: undefined as unknown as string, done: true };
      },
    };
  }

  private pushText(text: string): void {
    this._currentText = text;
    if (this.textResolver) {
      this.textResolver({ value: text, done: false });
      this.textResolver = null;
    } else {
      this.textQueue.push(text);
    }
    for (const listener of this.listeners) {
      listener.onText?.(text);
    }
  }

  // ------------------------------------------------------------------------
  // Subscription helper for React components
  // ------------------------------------------------------------------------

  /**
   * Register a listener for live updates. Returns an unsubscribe function.
   * React components typically wire this into `useEffect` to update state.
   */
  subscribe(listener: LiveTranscriptionListener): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  // ------------------------------------------------------------------------
  // Lifecycle
  // ------------------------------------------------------------------------

  /**
   * Start live transcription.
   *
   * @param onPartial Optional callback for each partial transcription update
   * @throws LiveTranscriptionError.alreadyActive if already running
   * @throws LiveTranscriptionError.microphonePermissionDenied if mic denied
   */
  async start(onPartial?: (text: string) => void): Promise<void> {
    if (this._isActive) {
      throw LiveTranscriptionError.alreadyActive();
    }

    const granted = await this.audioCapture.requestPermission();
    if (!granted) {
      throw LiveTranscriptionError.microphonePermissionDenied();
    }

    if (onPartial) {
      this.subscribe({ onText: onPartial });
    }

    this._isActive = true;
    this._error = null;
    this._currentText = '';
    for (const listener of this.listeners) listener.onActiveChange?.(true);

    try {
      // Kick off the streaming transcription. The native side feeds back
      // partials via the async generator. We deliberately pass an empty
      // buffer because audio is being driven by the audio capture path
      // below — the native streaming STT pipeline reads from its own ring
      // buffer.
      for await (const partial of transcribeStream(new Uint8Array(0), this.options)) {
        this.pushText(partial.text);
        if (partial.isFinal) break;
      }
    } catch (err) {
      this.handleError(err as Error);
    }

    try {
      await this.audioCapture.startRecording((audioData) => {
        // Audio data is forwarded by the C++ native side; the JS-level
        // forwarding here is a no-op fallback for backends that need the
        // bridge to push samples. The audio level is updated by the
        // capture manager itself.
        this._audioLevel = this.audioCapture.audioLevel;
        for (const listener of this.listeners) {
          listener.onAudioLevel?.(this._audioLevel);
        }
        // audioData reference retained so backends with a JS-side push
        // path (custom Nitro backends) can subscribe via subscribe().
        void audioData;
      });
    } catch (err) {
      this._isActive = false;
      for (const listener of this.listeners) listener.onActiveChange?.(false);
      throw err;
    }

    this.logger.info('Live transcription started');
  }

  /** Stop live transcription. Matches Swift `stop()`. */
  async stop(): Promise<void> {
    if (!this._isActive) return;

    this.logger.info('Stopping live transcription');

    await stopStreamingTranscription();

    try {
      await this.audioCapture.stopRecording();
    } catch (err) {
      this.logger.warning(`Error stopping audio capture: ${String(err)}`);
    }

    this._isActive = false;
    this._audioLevel = 0;
    this.streamFinished = true;

    if (this.textResolver) {
      this.textResolver({ value: undefined as unknown as string, done: true });
      this.textResolver = null;
    }

    for (const listener of this.listeners) {
      listener.onActiveChange?.(false);
      listener.onAudioLevel?.(0);
    }

    this.logger.info('Live transcription stopped');
  }

  private handleError(err: Error): void {
    this._error = err;
    this.logger.error(`Transcription error: ${err.message}`);
    for (const listener of this.listeners) listener.onError?.(err);
  }
}

// ============================================================================
// RunAnywhere extension entry point
// ============================================================================

/**
 * Start a new live transcription session.
 *
 * Matches Swift: `RunAnywhere.startLiveTranscription(options:onPartial:)`
 *
 * Example:
 * ```ts
 * const session = await startLiveTranscription();
 * for await (const text of session.transcriptions) {
 *   console.log(text);
 * }
 * await session.stop();
 * ```
 */
export async function startLiveTranscription(
  options?: STTOptions,
  onPartial?: (text: string) => void
): Promise<LiveTranscriptionSession> {
  const session = new LiveTranscriptionSession(options ?? defaultLiveSTTOptions());
  await session.start(onPartial);
  return session;
}
