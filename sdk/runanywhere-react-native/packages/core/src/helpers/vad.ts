/**
 * helpers/vad
 *
 * Swift-parity conveniences for generated VAD proto types.
 */

import {
  SpeechActivityKind,
  type SpeechActivityEvent,
  type VADConfiguration,
  type VADResult,
} from '@runanywhere/proto-ts/vad_options';

export {
  VADConfiguration,
  VADOptions,
  SpeechActivityKind,
  type VADResult,
  type SpeechActivityEvent,
  type VADStatistics,
  type VADAudioSource,
  type VADProcessRequest,
  type VADServiceState,
  type VADStreamEvent,
} from '@runanywhere/proto-ts/vad_options';

export function vadConfigurationFrameLengthSeconds(
  config: VADConfiguration
): number {
  return config.frameLengthMs / 1000;
}

export function vadResultDuration(result: VADResult): number {
  return result.durationMs / 1000;
}

export function speechActivityEventTimestamp(event: SpeechActivityEvent): Date {
  return new Date(event.timestampMs);
}

export function speechActivityEventDuration(event: SpeechActivityEvent): number {
  return event.durationMs / 1000;
}

export function speechActivityKindIsTransition(
  kind: SpeechActivityKind
): boolean {
  return (
    kind === SpeechActivityKind.SPEECH_ACTIVITY_KIND_SPEECH_STARTED ||
    kind === SpeechActivityKind.SPEECH_ACTIVITY_KIND_SPEECH_ENDED
  );
}
