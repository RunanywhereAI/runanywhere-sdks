/**
 * VoiceSessionHandle.ts
 *
 * v2 close-out Phase 13 (P2-8). The pre-Phase-13 implementation was a
 * ~600-LOC class that re-implemented the entire voice pipeline in TS:
 * AudioCaptureManager + AudioPlaybackManager wiring, RMS-based VAD,
 * silence-window detection, processCurrentAudio() STT → LLM → TTS
 * orchestration, async-iterator events, EventBus republishing.
 *
 * All of that duplicates the C++ voice agent (rac_voice_agent_*) and
 * the Wave C `VoiceAgentStreamAdapter`
 * (sdk/runanywhere-react-native/packages/core/src/Adapters/VoiceAgentStreamAdapter.ts).
 *
 * New code MUST use:
 *
 *     for await (const event of new VoiceAgentStreamAdapter(handle).stream()) {
 *         handleEvent(event);
 *     }
 *
 * This file is preserved as a thin deprecation shell so existing call
 * sites compile. The events() async-iterator emits a one-time
 * deprecation warning + 'started' + 'stopped'.
 */

import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';

const logger = new SDKLogger('VoiceSession');

// ============================================================================
// Types — preserved verbatim from the pre-Phase-13 file (public API contract).
// ============================================================================

export interface VoiceSessionConfig {
  silenceDuration?: number;
  speechThreshold?: number;
  autoPlayTTS?: boolean;
  continuousMode?: boolean;
  language?: string;
  systemPrompt?: string;
  onEvent?: VoiceSessionEventCallback;
}

export const DEFAULT_VOICE_SESSION_CONFIG: Required<Omit<VoiceSessionConfig, 'onEvent'>> = {
  silenceDuration: 1.5,
  speechThreshold: 0.1,
  autoPlayTTS: true,
  continuousMode: true,
  language: 'en',
  systemPrompt: '',
};

export type VoiceSessionEventType =
  | 'started' | 'listening' | 'speechStarted' | 'speechEnded'
  | 'processing' | 'transcribed' | 'responded' | 'speaking'
  | 'turnCompleted' | 'stopped' | 'error';

export interface VoiceSessionEvent {
  type: VoiceSessionEventType;
  timestamp: number;
  audioLevel?: number;
  transcription?: string;
  response?: string;
  audio?: string;
  error?: string;
}

export type VoiceSessionEventCallback = (event: VoiceSessionEvent) => void;

export type VoiceSessionState =
  | 'idle' | 'starting' | 'listening' | 'processing' | 'speaking' | 'stopped' | 'error';

// ============================================================================
// VoiceSessionHandle — thin deprecation shell.
// ============================================================================

/**
 * @deprecated Use `VoiceAgentStreamAdapter` from `Adapters/VoiceAgentStreamAdapter.ts`.
 * Orchestration body deleted in v2 close-out Phase 13.
 */
export class VoiceSessionHandle {
  private config: Required<Omit<VoiceSessionConfig, 'onEvent'>>;
  private eventCallback: VoiceSessionEventCallback | null = null;
  private eventListeners: VoiceSessionEventCallback[] = [];
  private state: VoiceSessionState = 'idle';
  private warned = false;

  constructor(config: VoiceSessionConfig = {}) {
    const { onEvent, ...rest } = config;
    this.config = { ...DEFAULT_VOICE_SESSION_CONFIG, ...rest };
    if (onEvent) this.eventCallback = onEvent;
  }

  get sessionState(): VoiceSessionState { return this.state; }
  get isRunning(): boolean {
    return this.state !== 'idle' && this.state !== 'stopped' && this.state !== 'error';
  }
  get isSpeaking(): boolean { return false; }     // playback handled by C++ agent now
  get audioLevel(): number { return 0; }          // VAD handled by C++ agent now

  async start(): Promise<void> {
    if (this.isRunning) return;
    if (!this.warned) {
      logger.warning(
        'VoiceSessionHandle is deprecated since v2 close-out Phase 13. ' +
        'Migrate to new VoiceAgentStreamAdapter(handle).stream().',
      );
      this.warned = true;
    }
    this.state = 'listening';
    this.emit({ type: 'started', timestamp: Date.now() });
  }

  async stop(): Promise<void> {
    if (!this.isRunning) return;
    this.state = 'stopped';
    this.emit({ type: 'stopped', timestamp: Date.now() });
  }

  /** Push-to-talk send. No-op since v2 close-out — handled by C++ voice agent. */
  async sendNow(): Promise<void> {
    logger.debug('sendNow: no-op since v2 close-out — use VoiceAgentStreamAdapter.');
  }

  /** Async-iterator event consumer. Returns immediately after the agent stops. */
  async *events(): AsyncGenerator<VoiceSessionEvent> {
    const queue: VoiceSessionEvent[] = [];
    let resolveNext: (() => void) | null = null;
    let done = false;

    const onEvent = (event: VoiceSessionEvent) => {
      queue.push(event);
      if (resolveNext) { resolveNext(); resolveNext = null; }
      if (event.type === 'stopped' || event.type === 'error') done = true;
    };
    this.addEventListener(onEvent);

    try {
      while (!done || queue.length > 0) {
        if (queue.length === 0) {
          await new Promise<void>(r => { resolveNext = r; });
        }
        while (queue.length > 0) yield queue.shift()!;
      }
    } finally {
      this.removeEventListener(onEvent);
    }
  }

  addEventListener(callback: VoiceSessionEventCallback): void {
    this.eventListeners.push(callback);
  }

  removeEventListener(callback: VoiceSessionEventCallback): void {
    const idx = this.eventListeners.indexOf(callback);
    if (idx >= 0) this.eventListeners.splice(idx, 1);
  }

  private emit(event: VoiceSessionEvent): void {
    if (this.eventCallback) {
      try { this.eventCallback(event); } catch (e) {
        logger.error('Event callback error', e);
      }
    }
    for (const listener of this.eventListeners) {
      try { listener(event); } catch (e) {
        logger.error('Event listener error', e);
      }
    }
  }
}
