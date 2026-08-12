/**
 * Transcript text hygiene shared by every STT consumer in the Web SDK.
 *
 * Whisper (and the Sherpa wrapper around it) reports "there was nothing to
 * transcribe" by emitting a bracketed marker as the transcript itself —
 * `[ Silence ]`, `[BLANK_AUDIO]`, `(silence)`, `<|nospeech|>`. Those are the
 * model describing its own input, not words anyone said, and passing them
 * through makes a silent recording render in the same typography as real
 * speech and makes a silent microphone turn look like a user utterance the
 * agent should answer.
 *
 * The rule is deliberately structural rather than a list of known strings: a
 * transcript made up only of bracketed/parenthesised/angle-bracketed tokens
 * contains no words, whatever the model chose to write inside them. Whisper
 * repeats its marker once per window on a long stretch of non-speech — an
 * 8-second recording of a quiet room comes back as `[Music] [Music] [Music] …` —
 * so matching a single token is not enough. Text with any words outside the
 * brackets is left exactly as the model produced it: this normalises "no
 * speech", it does not edit transcripts.
 */

/** A transcript that is nothing but markers: `[ Silence ]`, `(music)`, `<|nospeech|>`, `[Music] [Music]`. */
const MARKER_ONLY = /^(?:\s*(?:\[[^\][]*\]|\([^()]*\)|<[^<>]*>))+\s*$/;

/**
 * The transcript as spoken, or `''` when the model reported no speech.
 *
 * Returns the input untouched for anything that carries real words, so callers
 * can treat `''` as the single "nothing was said" signal and render their own
 * empty state instead of the model's marker.
 */
export function spokenTranscript(text: string | undefined): string {
  const trimmed = text?.trim() ?? '';
  if (!trimmed) return '';
  return MARKER_ONLY.test(trimmed) ? '' : text ?? '';
}

/** True when the model reported no speech (blank, or a marker-only transcript). */
export function isNoSpeechTranscript(text: string | undefined): boolean {
  return spokenTranscript(text) === '';
}
