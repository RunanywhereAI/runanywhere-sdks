import { SDKLogger } from '../../../Foundation/Logging';

/**
 * Represents the current state of the audio pipeline to prevent feedback loops
 */
export enum AudioPipelineState {
  /** System is idle, ready to start listening */
  Idle = 'idle',

  /** Actively listening for speech via VAD */
  Listening = 'listening',

  /** Processing detected speech with STT */
  ProcessingSpeech = 'processingSpeech',

  /** Generating response with LLM */
  GeneratingResponse = 'generatingResponse',

  /** Playing TTS output */
  PlayingTTS = 'playingTTS',

  /** Cooldown period after TTS to prevent feedback */
  Cooldown = 'cooldown',

  /** Error state requiring reset */
  Error = 'error',
}

/**
 * Configuration for feedback prevention
 */
export interface AudioPipelineStateConfiguration {
  /** Duration to wait after TTS before allowing microphone (seconds) */
  cooldownDuration: number;

  /** Whether to enforce strict state transitions */
  strictTransitions: boolean;

  /** Maximum TTS duration before forced timeout (seconds) */
  maxTTSDuration: number;
}

/**
 * Default configuration values
 */
const DEFAULT_CONFIGURATION: AudioPipelineStateConfiguration = {
  cooldownDuration: 0.8, // 800ms - better feedback prevention while maintaining responsiveness
  strictTransitions: true,
  maxTTSDuration: 30.0,
};

/**
 * State change handler type
 */
export type AudioPipelineStateChangeHandler = (
  oldState: AudioPipelineState,
  newState: AudioPipelineState
) => void;

/**
 * Manages audio pipeline state transitions and feedback prevention
 */
export class AudioPipelineStateManager {
  private currentState: AudioPipelineState = AudioPipelineState.Idle;
  private lastTTSEndTime: Date | null = null;
  private readonly cooldownDuration: number;
  private stateChangeHandler: AudioPipelineStateChangeHandler | null = null;
  private readonly configuration: AudioPipelineStateConfiguration;
  private readonly logger: SDKLogger;
  private cooldownTimer: NodeJS.Timeout | null = null;

  constructor(configuration: Partial<AudioPipelineStateConfiguration> = {}) {
    this.configuration = {
      ...DEFAULT_CONFIGURATION,
      ...configuration,
    };
    this.cooldownDuration = this.configuration.cooldownDuration;
    this.logger = new SDKLogger('AudioPipelineState');
  }

  /**
   * Get the current state
   */
  public get state(): AudioPipelineState {
    return this.currentState;
  }

  /**
   * Set a handler for state changes
   */
  public setStateChangeHandler(handler: AudioPipelineStateChangeHandler): void {
    this.stateChangeHandler = handler;
  }

  /**
   * Check if microphone can be activated
   */
  public canActivateMicrophone(): boolean {
    switch (this.currentState) {
      case AudioPipelineState.Idle:
      case AudioPipelineState.Listening:
        // Check cooldown if we recently finished TTS
        if (this.lastTTSEndTime !== null) {
          const timeSinceTTS =
            (Date.now() - this.lastTTSEndTime.getTime()) / 1000;
          return timeSinceTTS >= this.cooldownDuration;
        }
        return true;

      case AudioPipelineState.ProcessingSpeech:
      case AudioPipelineState.GeneratingResponse:
      case AudioPipelineState.PlayingTTS:
      case AudioPipelineState.Cooldown:
        return false;

      case AudioPipelineState.Error:
        return false;

      default:
        return false;
    }
  }

  /**
   * Check if TTS can be played
   */
  public canPlayTTS(): boolean {
    switch (this.currentState) {
      case AudioPipelineState.GeneratingResponse:
        return true;
      default:
        return false;
    }
  }

  /**
   * Transition to a new state with validation
   */
  public transition(to: AudioPipelineState): boolean {
    const oldState = this.currentState;

    // Validate transition
    if (!this.isValidTransition(oldState, to)) {
      if (this.configuration.strictTransitions) {
        this.logger.warning(
          `Invalid state transition from ${oldState} to ${to}`
        );
        return false;
      }
    }

    // Update state
    this.currentState = to;
    this.logger.debug(`State transition: ${oldState} → ${to}`);

    // Handle special state actions
    switch (to) {
      case AudioPipelineState.PlayingTTS:
        // Don't use timeout for System TTS as it manages its own completion
        break;

      case AudioPipelineState.Cooldown:
        this.lastTTSEndTime = new Date();
        // Clear any existing timer
        if (this.cooldownTimer !== null) {
          clearTimeout(this.cooldownTimer);
        }
        // Automatically transition to idle after cooldown
        this.cooldownTimer = setTimeout(() => {
          if (this.currentState === AudioPipelineState.Cooldown) {
            this.transition(AudioPipelineState.Idle);
          }
        }, this.cooldownDuration * 1000);
        break;

      default:
        break;
    }

    // Notify handler
    if (this.stateChangeHandler !== null) {
      this.stateChangeHandler(oldState, to);
    }

    return true;
  }

  /**
   * Force reset to idle state (use in error recovery)
   */
  public reset(): void {
    this.logger.info('Force resetting audio pipeline state to idle');
    this.currentState = AudioPipelineState.Idle;
    this.lastTTSEndTime = null;
    if (this.cooldownTimer !== null) {
      clearTimeout(this.cooldownTimer);
      this.cooldownTimer = null;
    }
  }

  /**
   * Cleanup resources
   */
  public cleanup(): void {
    if (this.cooldownTimer !== null) {
      clearTimeout(this.cooldownTimer);
      this.cooldownTimer = null;
    }
    this.stateChangeHandler = null;
  }

  /**
   * Check if a state transition is valid
   */
  private isValidTransition(
    from: AudioPipelineState,
    to: AudioPipelineState
  ): boolean {
    // From idle
    if (from === AudioPipelineState.Idle) {
      if (to === AudioPipelineState.Listening) {
        return true;
      }
      if (to === AudioPipelineState.Cooldown) {
        // Allow idle to cooldown for cases where TTS completes quickly
        // or when we need to enforce cooldown after other operations
        return true;
      }
    }

    // From listening
    if (from === AudioPipelineState.Listening) {
      if (
        to === AudioPipelineState.Idle ||
        to === AudioPipelineState.ProcessingSpeech
      ) {
        return true;
      }
    }

    // From processing speech
    if (from === AudioPipelineState.ProcessingSpeech) {
      if (
        to === AudioPipelineState.Idle ||
        to === AudioPipelineState.GeneratingResponse ||
        to === AudioPipelineState.Listening
      ) {
        return true;
      }
    }

    // From generating response
    if (from === AudioPipelineState.GeneratingResponse) {
      if (
        to === AudioPipelineState.PlayingTTS ||
        to === AudioPipelineState.Idle ||
        to === AudioPipelineState.Cooldown
      ) {
        // Allow direct transition to cooldown if TTS is skipped
        return true;
      }
    }

    // From playing TTS
    if (from === AudioPipelineState.PlayingTTS) {
      if (
        to === AudioPipelineState.Cooldown ||
        to === AudioPipelineState.Idle
      ) {
        // Allow transition to idle if cooldown is not needed
        return true;
      }
    }

    // From cooldown
    if (from === AudioPipelineState.Cooldown) {
      if (to === AudioPipelineState.Idle) {
        return true;
      }
    }

    // Error state can transition to idle
    if (from === AudioPipelineState.Error) {
      if (to === AudioPipelineState.Idle) {
        return true;
      }
    }

    // Any state can transition to error
    if (to === AudioPipelineState.Error) {
      return true;
    }

    return false;
  }
}
