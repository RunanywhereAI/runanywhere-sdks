/**
 * @file stt_transcript_text.h
 * @brief Turn an engine's non-speech marker into an honest empty transcript.
 *
 * Whisper (and the Sherpa/QHexRT wrappers around it) answer a recording with no
 * speech in it by emitting one of its own markers — `[ Silence ]`,
 * `[BLANK_AUDIO]`, `[Music]`, `(wind)` — as the transcription text. Every SDK
 * then rendered that string in the same typography as real speech, so a silent
 * recording read as if the speaker had said "(wind)", and the same token turned
 * up inside a voice-agent user bubble. Two runs of the same silence disagreed on
 * the wording, which made it worse: the reader had no way to tell an engine
 * artifact from a transcript.
 *
 * The apps all own a correct empty state already ("Your transcript will appear
 * here", the waveform placeholder). They just never got the chance to use it,
 * because the text was non-empty. Emptying it here is what hands them that
 * chance — and doing it in commons means iOS, Android, Flutter, React Native and
 * Web are all fixed at once, instead of five near-identical marker lists
 * drifting apart.
 *
 * Deliberately conservative: a transcript is cleared only when *every*
 * non-whitespace character belongs to a bracketed or parenthesised span. Real
 * speech that merely contains an aside — "the answer (I think) is Paris" — has
 * words outside the span and is left exactly as the engine produced it.
 */

#ifndef RAC_FEATURES_STT_TRANSCRIPT_TEXT_H
#define RAC_FEATURES_STT_TRANSCRIPT_TEXT_H

#include <cctype>
#include <string>

namespace rac::stt {

/**
 * Whether @p text carries no speech — it is empty, or consists only of
 * bracketed/parenthesised engine markers.
 */
inline bool transcript_is_non_speech(const char* text) {
    if (text == nullptr) {
        return true;
    }
    for (const char* cursor = text; *cursor != '\0'; ++cursor) {
        const unsigned char ch = static_cast<unsigned char>(*cursor);
        if (std::isspace(ch) != 0) {
            continue;
        }
        const char closer = (*cursor == '[') ? ']' : (*cursor == '(') ? ')' : '\0';
        if (closer == '\0') {
            // A character outside any marker span: this is real transcript text.
            return false;
        }
        // Skip to the closing bracket. An unterminated span runs to the end of
        // the string, which is still no speech (a truncated marker).
        while (*cursor != '\0' && *cursor != closer) {
            ++cursor;
        }
        if (*cursor == '\0') {
            break;
        }
    }
    // Nothing outside a marker span. An all-whitespace or empty string lands
    // here too, which is the same answer for every caller.
    return true;
}

/**
 * @p text as the caller should publish it: unchanged when it carries speech,
 * empty when it is only engine markers.
 */
inline std::string transcript_for_display(const char* text) {
    if (transcript_is_non_speech(text)) {
        return std::string();
    }
    return std::string(text);
}

}  // namespace rac::stt

#endif  // RAC_FEATURES_STT_TRANSCRIPT_TEXT_H
