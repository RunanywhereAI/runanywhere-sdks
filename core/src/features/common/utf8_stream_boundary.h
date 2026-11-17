#ifndef RAC_FEATURES_COMMON_UTF8_STREAM_BOUNDARY_H
#define RAC_FEATURES_COMMON_UTF8_STREAM_BOUNDARY_H

#include <string>

namespace rac {
namespace tokens {

inline size_t incomplete_utf8_tail(const std::string& text) {
    const size_t n = text.size();
    const size_t limit = n < 3 ? n : 3;
    for (size_t back = 1; back <= limit; ++back) {
        const unsigned char c = static_cast<unsigned char>(text[n - back]);
        if ((c & 0xC0) == 0x80)
            continue;
        size_t need = 0;
        if ((c & 0xE0) == 0xC0)
            need = 2;
        else if ((c & 0xF0) == 0xE0)
            need = 3;
        else if ((c & 0xF8) == 0xF0)
            need = 4;
        else
            return 0;
        return back < need ? back : 0;
    }
    return 0;
}

class Utf8Assembler {
   public:
    const std::string& feed(const std::string& chunk) {
        out_.clear();
        pending_ += chunk;
        const size_t hold = incomplete_utf8_tail(pending_);
        if (pending_.size() > hold) {
            out_.assign(pending_, 0, pending_.size() - hold);
            pending_.erase(0, pending_.size() - hold);
        }
        return out_;
    }

    const std::string& flush() {
        out_.clear();
        const size_t hold = incomplete_utf8_tail(pending_);
        if (pending_.size() > hold) {
            out_.assign(pending_, 0, pending_.size() - hold);
        }
        pending_.clear();
        return out_;
    }

   private:
    std::string pending_;
    std::string out_;
};

}  // namespace tokens
}  // namespace rac

#endif
