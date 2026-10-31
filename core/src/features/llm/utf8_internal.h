#ifndef RAC_FEATURES_LLM_UTF8_INTERNAL_H
#define RAC_FEATURES_LLM_UTF8_INTERNAL_H

#include <cstddef>
#include <string>

namespace rac::llm {

// Preserve valid Unicode and replace each invalid byte with U+FFFD. Model output
// can end mid-character at max_tokens; repair it before parsing JSON or writing
// proto string fields. Reject overlong encodings, surrogates, and values > U+10FFFF.
inline std::string sanitize_utf8(const std::string& in) {
    std::string out;
    out.reserve(in.size());
    const std::size_t n = in.size();
    std::size_t i = 0;
    auto is_cont = [&](std::size_t k) {
        return k < n && (static_cast<unsigned char>(in[k]) & 0xC0) == 0x80;
    };
    while (i < n) {
        const unsigned char c = static_cast<unsigned char>(in[i]);
        std::size_t len = 0;
        if (c < 0x80) {
            len = 1;
        } else if ((c & 0xE0) == 0xC0 && c >= 0xC2) {
            len = 2;
        } else if ((c & 0xF0) == 0xE0) {
            len = 3;
        } else if ((c & 0xF8) == 0xF0 && c <= 0xF4) {
            len = 4;
        }
        bool ok = len > 0;
        for (std::size_t k = 1; ok && k < len; ++k) {
            ok = is_cont(i + k);
        }
        if (ok && len >= 3) {
            const unsigned char second = static_cast<unsigned char>(in[i + 1]);
            ok = !(c == 0xE0 && second < 0xA0) && !(c == 0xED && second >= 0xA0) &&
                 !(c == 0xF0 && second < 0x90) && !(c == 0xF4 && second >= 0x90);
        }
        if (ok) {
            out.append(in, i, len);
            i += len;
        } else {
            out.append("\xEF\xBF\xBD");
            ++i;
        }
    }
    return out;
}

}  // namespace rac::llm

#endif  // RAC_FEATURES_LLM_UTF8_INTERNAL_H
