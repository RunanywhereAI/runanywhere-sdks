#ifndef RAC_FEATURES_COMMON_UTF8_STREAM_BOUNDARY_H
#define RAC_FEATURES_COMMON_UTF8_STREAM_BOUNDARY_H

#include <string>

/**
 * @file utf8_stream_boundary.h
 * @brief Hold back a trailing partial UTF-8 sequence between stream chunks.
 *
 * A tokenizer piece is not guaranteed to be a whole character. Byte-level BPE
 * vocabularies carry single-byte fallback tokens (Qwen2.5 has all 64 bare
 * continuation bytes 0x80-0xBF), so any character without a whole-character
 * token in the vocab is emitted as two or more pieces, none of them valid
 * UTF-8 on its own. Delivering such a piece straight to a caller produces a
 * chunk that strict decoders reject and lenient ones mangle into U+FFFD.
 */
namespace rac {
namespace tokens {

/**
 * Number of bytes at the end of @p text that begin a UTF-8 sequence which is
 * not yet complete. Returns 0 when @p text ends on a character boundary, and
 * 0 for a malformed tail so a bad byte is never held forever.
 */
inline size_t incomplete_utf8_tail(const std::string& text) {
    const size_t n = text.size();
    // A UTF-8 sequence is at most 4 bytes, so only the last 3 can be partial.
    const size_t limit = n < 3 ? n : 3;
    for (size_t back = 1; back <= limit; ++back) {
        const unsigned char c = static_cast<unsigned char>(text[n - back]);
        if ((c & 0xC0) == 0x80)
            continue;  // continuation byte; keep walking back to the lead
        size_t need = 0;
        if ((c & 0xE0) == 0xC0)
            need = 2;
        else if ((c & 0xF0) == 0xE0)
            need = 3;
        else if ((c & 0xF8) == 0xF0)
            need = 4;
        else
            return 0;  // ASCII, or a stray byte we must not stall on
        return back < need ? back : 0;
    }
    return 0;  // three continuations with no lead in reach: already complete
}

}  // namespace tokens
}  // namespace rac

#endif  // RAC_FEATURES_COMMON_UTF8_STREAM_BOUNDARY_H
