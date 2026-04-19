// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Ported from FastVoice VoiceAI/src/pipeline/text_sanitizer.h.
//
// Cleans LLM output before it reaches the TTS synthesizer:
//   * strips markdown syntax (**, ##, ``) that TTS would vocalize as "hash"
//   * strips chain-of-thought blocks (<think>...</think>)
//   * normalizes whitespace
//   * expands common abbreviations ("Mr." -> "Mister")
//
// Keep it cheap — this runs on every sentence on the hot path.

#ifndef RA_CORE_TEXT_SANITIZER_H
#define RA_CORE_TEXT_SANITIZER_H

#include <string>
#include <string_view>

namespace ra::core {

class TextSanitizer {
public:
    struct Config {
        bool strip_markdown      = true;
        bool strip_thought_tags  = true;
        bool normalize_whitespace = true;
        bool expand_abbreviations = true;
    };

    TextSanitizer() = default;
    explicit TextSanitizer(Config cfg) : cfg_(cfg) {}

    std::string sanitize(std::string_view input) const;

private:
    Config cfg_;
};

}  // namespace ra::core

#endif  // RA_CORE_TEXT_SANITIZER_H
