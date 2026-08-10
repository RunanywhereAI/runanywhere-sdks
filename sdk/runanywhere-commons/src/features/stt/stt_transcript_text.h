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
 * Deliberately conservative on two axes. A transcript is cleared only when
 * *every* non-whitespace character sits inside a bracketed span — real speech
 * that merely contains an aside ("the answer (I think) is Paris") has words
 * outside the span and is left exactly as the engine produced it. And every one
 * of those spans must name a marker this file recognises, so "(hello)",
 * "[test]", and a transcript truncated mid-bracket survive as the speech they
 * are. See `span_is_known_marker` for why that allowlist stays narrow.
 */

#ifndef RAC_FEATURES_STT_TRANSCRIPT_TEXT_H
#define RAC_FEATURES_STT_TRANSCRIPT_TEXT_H

#include <cctype>
#include <string>

namespace rac::stt {

/**
 * Whether a bracketed span's contents name a known engine "no speech" marker.
 *
 * The span is normalised before comparison — lowercased, with everything that is
 * not a letter or digit dropped — so `[ Silence ]`, `[SILENCE]` and `[_silence_]`
 * all match the single `silence` entry.
 *
 * This is an ALLOWLIST on purpose, and the reason matters. The first version of
 * this predicate treated EVERY bracketed or parenthesised span as non-speech.
 * That is true of an engine marker, and equally true of a user who says
 * "(hello)", of a transcript that legitimately reads "[test]", and of any
 * transcript truncated mid-bracket — all of which were silently erased for every
 * native consumer.
 *
 * Erasing real speech is the worse failure. An unrecognised marker that slips
 * through is visible, reportable, and cosmetic; a sentence emptied on its way to
 * the user (or to the LLM, as the user's own turn) is gone with no trace. So a
 * backend emitting a marker missing from this list should have it ADDED here,
 * with the literal string it emits recorded alongside — rather than the list
 * being widened back into "anything in brackets".
 */
inline bool span_is_known_marker(const char* begin, const char* end) {
    std::string key;
    key.reserve(static_cast<size_t>(end - begin));
    for (const char* cursor = begin; cursor != end; ++cursor) {
        const unsigned char ch = static_cast<unsigned char>(*cursor);
        if (std::isalnum(ch) != 0) {
            key.push_back(static_cast<char>(std::tolower(ch)));
        }
    }
    if (key.empty()) {
        // "[]" or "(   )" names nothing, and carries no speech either.
        return true;
    }
    // Observed from Whisper (and the Sherpa/QHexRT wrappers around it) and from
    // Piper/Silero-adjacent pipelines. Keep additions literal and evidenced.
    static const char* const kMarkers[] = {
        "blankaudio",  // [BLANK_AUDIO]
        "silence",     // [ Silence ], [SILENCE], [_silence_]
        "silent",
        "nospeech",  // <|nospeech|> once the pipe/angle wrapper is stripped
        "music",     // [Music], [MUSIC]
        "noise",
        "backgroundnoise",
        "inaudible",
        "unintelligible",
        "wind",  // (wind)
        "laughter",
        "laughs",
        "applause",
        "beep",
    };
    for (const char* marker : kMarkers) {
        if (key == marker) {
            return true;
        }
    }
    return false;
}

/**
 * Whether @p text carries no speech — it is empty, whitespace, or consists only
 * of recognised engine markers (see `span_is_known_marker`).
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
            // A character outside any span: this is real transcript text.
            return false;
        }
        const char* const content = cursor + 1;
        const char* scan = content;
        while (*scan != '\0' && *scan != closer) {
            ++scan;
        }
        if (*scan == '\0') {
            // Unterminated. Previously treated as a truncated marker and erased;
            // a transcript cut mid-phrase ("[spoken words") is the likelier
            // reading, and guessing wrong here costs the whole utterance.
            return false;
        }
        if (!span_is_known_marker(content, scan)) {
            return false;
        }
        cursor = scan;  // the loop's ++cursor then steps past the closer
    }
    // Nothing but whitespace and recognised markers. An empty string lands here
    // too, which is the same answer for every caller.
    return true;
}

/**
 * @p text as the caller should publish it: unchanged when it carries speech,
 * empty when it is only engine markers.
 */
inline std::string transcript_for_display(const char* text) {
    if (transcript_is_non_speech(text)) {
        return {};
    }
    return {text};
}

}  // namespace rac::stt

#endif  // RAC_FEATURES_STT_TRANSCRIPT_TEXT_H
