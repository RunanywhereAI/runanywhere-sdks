// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Stateful detector that buffers streaming tokens and emits complete
// sentences ready for TTS.
//
// Ported from FastVoice VoiceAI/src/pipeline/sentence_detector.h.
// Algorithm:
//   * Accumulate token text character by character.
//   * On terminal punctuation (.!?)— and only after a word-count gate —
//     emit the buffered sentence.
//   * On no punctuation but a word-count threshold hit (default 30), force
//     an emit anyway (long run-on sentences).

#ifndef RA_CORE_SENTENCE_DETECTOR_H
#define RA_CORE_SENTENCE_DETECTOR_H

#include <functional>
#include <string>
#include <string_view>

namespace ra::core {

class SentenceDetector {
public:
    using SentenceCallback = std::function<void(std::string)>;

    struct Config {
        // Minimum word count before a sentence can be emitted, even on
        // terminal punctuation. Avoids firing on fragments like "Hi.".
        int min_words_for_emit = 2;

        // Maximum word count before forcing an emit without punctuation.
        int max_words_before_force_flush = 30;

        // If the buffer ends on a space, wait for more input. Otherwise
        // the detector may split words across sentences.
        bool require_space_before_emit = true;
    };

    SentenceDetector() = default;
    explicit SentenceDetector(Config cfg) : cfg_(cfg) {}

    void set_callback(SentenceCallback cb) { callback_ = std::move(cb); }

    // Feed one token's text. May or may not trigger callback.
    void feed(std::string_view token_text);

    // Force emission of whatever is buffered (called on LLM is_final).
    void flush();

    // Reset state. Used when barge-in clears in-flight generation.
    void reset();

    int words_accumulated() const noexcept { return accumulated_words_; }

private:
    bool has_terminal_punctuation() const;
    void emit_buffered();

    Config               cfg_;
    std::string          buffer_;
    int                  accumulated_words_ = 0;
    bool                 last_was_space_   = true;
    SentenceCallback     callback_;
};

}  // namespace ra::core

#endif  // RA_CORE_SENTENCE_DETECTOR_H
