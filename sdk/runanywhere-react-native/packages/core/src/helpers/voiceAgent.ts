/**
 * helpers/voiceAgent
 *
 * Public type aliases plus Swift-parity conveniences for generated voice
 * agent / voice session proto types.
 */

import { ComponentLifecycleState } from '@runanywhere/proto-ts/component_types';
import type {
  VoiceAgentComposeConfig,
  VoiceAgentResult,
  VoiceSessionConfig,
} from '@runanywhere/proto-ts/voice_agent_service';
import type {
  VoiceAgentComponentStates,
  VoiceSessionError,
} from '@runanywhere/proto-ts/voice_events';

export { ComponentLifecycleState } from '@runanywhere/proto-ts/component_types';
export {
  type VoiceAgentResult,
  type VoiceAgentComposeConfig,
  type VoiceAgentRequest,
  type VoiceAgentTurnRequest,
  type VoiceSessionConfig,
} from '@runanywhere/proto-ts/voice_agent_service';
export {
  type VoiceAgentComponentStates,
  type VoiceEvent,
  type VoiceSessionError,
} from '@runanywhere/proto-ts/voice_events';

export type VoiceAgentConfig = VoiceAgentComposeConfig;

export function componentLifecycleStateIsLoaded(
  state: ComponentLifecycleState
): boolean {
  return state === ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY;
}

export function componentLifecycleStateIsLoading(
  state: ComponentLifecycleState
): boolean {
  return state === ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_LOADING;
}

export function voiceSessionConfigSilenceDuration(
  config: VoiceSessionConfig
): number {
  return config.silenceDurationMs / 1000;
}

export function withVoiceSessionConfigSilenceDuration(
  config: VoiceSessionConfig,
  seconds: number
): VoiceSessionConfig {
  return {
    ...config,
    silenceDurationMs: Math.round(seconds * 1000),
  };
}

export function voiceSessionConfigAutoPlayTTS(
  config: VoiceSessionConfig
): boolean {
  return config.autoPlayTts;
}

export function withVoiceSessionConfigAutoPlayTTS(
  config: VoiceSessionConfig,
  autoPlayTTS: boolean
): VoiceSessionConfig {
  return {
    ...config,
    autoPlayTts: autoPlayTTS,
  };
}

export function voiceSessionErrorDescription(
  error: VoiceSessionError
): string | undefined {
  return error.message.length > 0 ? error.message : undefined;
}

export function voiceAgentResultTotalTime(result: VoiceAgentResult): number {
  return result.totalTimeMs / 1000;
}

export function voiceAgentComponentStatesReady(
  states: VoiceAgentComponentStates
): boolean {
  return states.ready;
}
