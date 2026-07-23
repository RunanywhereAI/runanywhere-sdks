/**
 * @file voice_agent_tts_chunking.h
 * @brief Pure text -> speakable-chunk policy for the streaming voice agent (header-only).
 *
 * Turns a growing stream of LLM tokens into short, clean, speakable chunks so the
 * voice agent can synthesize and emit audio sentence-by-sentence AS the LLM
 * decodes (instead of waiting for the whole answer, then one-shot TTS). It:
 *   - splits on sentence boundaries (. ! ? followed by whitespace),
 *   - drops <think>...</think> reasoning so it is never spoken,
 *   - strips markdown and collapses whitespace, and
 *   - hard-caps each chunk so an over-long phoneme run never fails an NPU TTS
 *     (MeloTTS on v79 rejects a sequence past its 512-phoneme cap with rc=-130).
 *
 * C++ port of the Kotlin `VoiceTtsChunkPolicy` used by the demo app's per-turn
 * NPU-swap path; promoting it to commons lets EVERY SDK stream spoken replies
 * without re-porting the logic. Header-only (inline): consumed by a single TU
 * (voice_agent_d7_abi.cpp), so no separate .cpp / CMake source entry is needed.
 * std::regex is deliberately NOT used: its ECMAScript grammar has no lookbehind
 * or DOTALL, so the scanning is hand-written.
 */

#ifndef RAC_FEATURES_VOICE_AGENT_VOICE_AGENT_TTS_CHUNKING_H
#define RAC_FEATURES_VOICE_AGENT_VOICE_AGENT_TTS_CHUNKING_H

#include <algorithm>
#include <string>
#include <vector>

namespace rac::voice_agent::detail {

/// ~a couple hundred chars maps under MeloTTS's 512-phoneme cap; keep each spoken
/// chunk well under so g2p never overruns.
constexpr int kVoiceTtsMaxChars = 160;

/// Small on-device chat models (e.g. Qwen3-0.6B) tend to comma-JOIN a spoken
/// reply into a single long sentence ("Paris is the capital of France, and Tokyo
/// is the capital of Japan."), so splitting only on . ! ? would stream nothing.
/// We therefore ALSO break at a clause boundary ( , ; : ) — but only once the
/// pending fragment is at least this long, so a SHORT sentence stays whole (no
/// choppy sub-clause TTS) and only a LONG run-on gets streamed clause-by-clause.
constexpr int kVoiceTtsMinClauseChars = 50;

namespace chunk_internal {

inline bool is_ws(char c) {
    // Match Kotlin's \s: space, tab, newline, carriage return, form feed, vtab.
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v';
}

// Remove every COMPLETE <think>...</think> block (non-greedy, spanning newlines).
// An unclosed trailing <think> is left in place for the caller to hold.
inline void strip_complete_think(std::string& s) {
    constexpr char kOpen[] = "<think>";
    constexpr char kClose[] = "</think>";
    constexpr size_t kCloseLen = sizeof(kClose) - 1;
    size_t open = 0;
    while ((open = s.find(kOpen, open)) != std::string::npos) {
        const size_t close = s.find(kClose, open);
        if (close == std::string::npos) {
            break;  // unclosed reasoning block — leave it for the caller
        }
        s.erase(open, (close + kCloseLen) - open);
    }
}

// Split into speakable segments. A `.`/`!`/`?` followed by whitespace ALWAYS
// breaks (true sentence boundary; "3.14"/"U.S." never split mid-token since no
// whitespace follows). A clause mark `,`/`;`/`:` followed by whitespace breaks
// ONLY once the pending segment is >= @p min_clause chars, so short sentences
// stay whole and only long run-ons stream clause-by-clause. The whitespace run is
// consumed. Includes a trailing (possibly empty) part when the text ends on a
// boundary, matching the sentence-split contract drain_sentences relies on.
inline std::vector<std::string> split_speakable(const std::string& s, int min_clause) {
    std::vector<std::string> parts;
    size_t start = 0;
    size_t i = 0;
    while (i < s.size()) {
        const char c = s[i];
        const bool sentence_end = (c == '.' || c == '!' || c == '?');
        const bool clause_end = (c == ',' || c == ';' || c == ':');
        if ((sentence_end || clause_end) && i + 1 < s.size() && is_ws(s[i + 1])) {
            const size_t seg_len = (i + 1) - start;
            if (sentence_end || static_cast<int>(seg_len) >= min_clause) {
                parts.push_back(s.substr(start, (i + 1) - start));
                size_t j = i + 1;
                while (j < s.size() && is_ws(s[j])) {
                    ++j;
                }
                start = j;
                i = j;
                continue;
            }
        }
        ++i;
    }
    parts.push_back(s.substr(start));  // trailing part (may be empty)
    return parts;
}

}  // namespace chunk_internal

/// Strip markdown formatting and collapse whitespace so the TTS g2p front-end
/// sees clean prose.
inline std::string sanitize_for_tts(const std::string& text) {
    std::string collapsed;
    collapsed.reserve(text.size());
    bool pending_space = false;
    bool seen_non_space = false;
    for (char c : text) {
        const bool markdown = (c == '*' || c == '_' || c == '`' || c == '#' || c == '>' ||
                               c == '~' || c == '|');
        if (markdown || chunk_internal::is_ws(c)) {
            pending_space = seen_non_space;  // no leading spaces
            continue;
        }
        if (pending_space) {
            collapsed.push_back(' ');
            pending_space = false;
        }
        collapsed.push_back(c);
        seen_non_space = true;
    }
    return collapsed;  // trailing pending_space intentionally dropped (trim)
}

/**
 * Pull complete, speakable sentences out of @p buf (mutating it), dropping
 * <think> reasoning so it is never read aloud. With @p flush the trailing partial
 * is returned too and the buffer is drained; otherwise the trailing partial (plus
 * any still-open <think>) is kept in @p buf for the next call. Each returned
 * sentence is already sanitized and non-empty.
 */
inline std::vector<std::string> drain_sentences(std::string& buf, bool flush) {
    std::string stripped = buf;
    chunk_internal::strip_complete_think(stripped);

    const size_t open = stripped.find("<think>");  // an unclosed reasoning block, if any
    const std::string held = (open != std::string::npos) ? stripped.substr(open) : std::string();
    const std::string speakable =
        (open != std::string::npos) ? stripped.substr(0, open) : stripped;

    std::vector<std::string> parts =
        chunk_internal::split_speakable(speakable, kVoiceTtsMinClauseChars);
    const size_t complete = flush ? parts.size() : (parts.empty() ? 0 : parts.size() - 1);

    std::vector<std::string> out;
    out.reserve(complete);
    for (size_t i = 0; i < complete; ++i) {
        std::string clean = sanitize_for_tts(parts[i]);
        if (!clean.empty()) {
            out.push_back(std::move(clean));
        }
    }

    buf.clear();
    if (!flush) {
        buf = (parts.empty() ? std::string() : parts.back()) + held;
    }
    return out;
}

/**
 * Hard-cap @p text into <= @p max_chars chunks, splitting on word boundaries. A
 * single word longer than the cap (a URL / run-on token) is force-split so NO
 * chunk ever exceeds the cap.
 */
inline std::vector<std::string> cap_for_tts(const std::string& text,
                                            int max_chars = kVoiceTtsMaxChars) {
    std::vector<std::string> out;
    if (max_chars <= 0 || static_cast<int>(text.size()) <= max_chars) {
        out.push_back(text);
        return out;
    }
    const size_t cap = static_cast<size_t>(max_chars);
    std::string cur;
    auto flush_cur = [&]() {
        if (!cur.empty()) {
            out.push_back(cur);
            cur.clear();
        }
    };

    size_t i = 0;
    while (true) {
        const size_t sp = text.find(' ', i);
        const std::string word = (sp == std::string::npos) ? text.substr(i) : text.substr(i, sp - i);

        if (word.size() > cap) {
            // a single over-long token: force-split so NO chunk exceeds the cap
            flush_cur();
            size_t k = 0;
            while (k < word.size()) {
                const size_t end = std::min(k + cap, word.size());
                out.push_back(word.substr(k, end - k));
                k = end;
            }
        } else {
            if (!cur.empty() && cur.size() + 1 + word.size() > cap) {
                flush_cur();
            }
            if (!cur.empty()) {
                cur.push_back(' ');
            }
            cur += word;
        }

        if (sp == std::string::npos) {
            break;
        }
        i = sp + 1;
    }
    flush_cur();
    return out;
}

}  // namespace rac::voice_agent::detail

#endif  // RAC_FEATURES_VOICE_AGENT_VOICE_AGENT_TTS_CHUNKING_H
