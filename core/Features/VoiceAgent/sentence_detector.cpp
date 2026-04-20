// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "sentence_detector.h"

#include <cctype>
#include <utility>

namespace ra::core {

namespace {
bool is_terminal_punct(char c) {
    return c == '.' || c == '!' || c == '?';
}
}  // namespace

bool SentenceDetector::has_terminal_punctuation() const {
    if (buffer_.empty()) return false;
    // Walk backwards past any trailing whitespace or closing punct.
    for (auto it = buffer_.rbegin(); it != buffer_.rend(); ++it) {
        const char c = *it;
        if (c == ' ' || c == '\t' || c == '\n' ||
            c == '"' || c == '\'' || c == ')' || c == ']' || c == '}') {
            continue;
        }
        return is_terminal_punct(c);
    }
    return false;
}

void SentenceDetector::feed(std::string_view token_text) {
    if (token_text.empty()) return;

    // Maintain whitespace / word count state. Whitespace AND terminal
    // punctuation count as word boundaries — otherwise "Hi. World." would
    // only register a single word (the space after "Hi").
    for (char c : token_text) {
        const bool is_space      = c == ' ' || c == '\n' || c == '\t';
        const bool is_terminal   = c == '.' || c == '!' || c == '?';
        if (is_space || is_terminal) {
            if (!last_was_space_) {
                ++accumulated_words_;
            }
            last_was_space_ = is_space;
        } else {
            last_was_space_ = false;
        }
    }
    buffer_.append(token_text);

    const bool has_period     = has_terminal_punctuation();
    const bool words_enough   = accumulated_words_ >= cfg_.min_words_for_emit;
    const bool space_gate_ok  = !cfg_.require_space_before_emit ||
                                last_was_space_ || has_period;
    const bool force_flush    = accumulated_words_ >=
                                cfg_.max_words_before_force_flush;

    if ((has_period && words_enough && space_gate_ok) || force_flush) {
        emit_buffered();
    }
}

void SentenceDetector::flush() {
    if (!buffer_.empty()) emit_buffered();
}

void SentenceDetector::reset() {
    buffer_.clear();
    accumulated_words_ = 0;
    last_was_space_    = true;
}

void SentenceDetector::emit_buffered() {
    if (buffer_.empty()) return;
    std::string out = std::move(buffer_);
    buffer_.clear();
    // Reset counters; we're starting a new sentence.
    accumulated_words_ = 0;
    last_was_space_    = true;
    if (callback_) callback_(std::move(out));
}

}  // namespace ra::core
