/**
 * @file rag_chunker.cpp
 * @brief Document Chunking Implementation using Recursive Chunking
 */

#include "rag_chunker.h"

#include <algorithm>
#include <cctype>
#include <string_view>
#include <vector>

namespace runanywhere::rag {

namespace {

// Append size-budgeted slices of `text` to `out`, never cutting through a
// UTF-8 character. Used by both size-only split paths below: the top-level
// one when no separator matched, and the per-split one when a piece is
// oversized and there is no finer separator left to try.
void append_utf8_bounded_slices(std::string_view text, size_t budget,
                                std::vector<std::string_view>& out) {
    if (budget == 0) {
        out.push_back(text);
        return;
    }
    size_t i = 0;
    while (i < text.length()) {
        size_t end = std::min(i + budget, text.length());
        while (end > i && end < text.length() &&
               (static_cast<unsigned char>(text[end]) & 0xC0) == 0x80) {
            --end;
        }
        if (end == i) {
            // One character is wider than the whole budget: emit it intact
            // rather than spin or hand back a partial character.
            end = i + 1;
            while (end < text.length() && (static_cast<unsigned char>(text[end]) & 0xC0) == 0x80) {
                ++end;
            }
        }
        out.push_back(text.substr(i, end - i));
        i = end;
    }
}

void perform_recursive_chunking(std::string_view text_view, const std::string& original_text,
                                const std::vector<std::string>& separators, size_t chunk_size_chars,
                                size_t chunk_overlap_chars, std::vector<TextChunk>& output_chunks,
                                size_t& chunk_index) {
    if (text_view.empty())
        return;

    if (text_view.length() <= chunk_size_chars) {
        const char* start_ptr = text_view.data();
        size_t start_pos = start_ptr - original_text.data();
        size_t end_pos = start_pos + text_view.length();

        TextChunk chunk;
        chunk.text = original_text.substr(start_pos, end_pos - start_pos);
        chunk.start_position = start_pos;
        chunk.end_position = end_pos;

        size_t first = chunk.text.find_first_not_of(" \t\n\r");
        size_t last = chunk.text.find_last_not_of(" \t\n\r");
        if (first != std::string::npos && last != std::string::npos) {
            chunk.text = chunk.text.substr(first, last - first + 1);
            chunk.start_position += first;
            chunk.end_position = chunk.start_position + chunk.text.length();
        } else {
            chunk.text.clear();
        }

        if (!chunk.text.empty()) {
            chunk.chunk_index = chunk_index++;
            output_chunks.push_back(std::move(chunk));
        }
        return;
    }

    std::string separator = "";
    std::vector<std::string> next_separators;

    for (size_t i = 0; i < separators.size(); ++i) {
        if (separators[i].empty() || text_view.find(separators[i]) != std::string_view::npos) {
            separator = separators[i];
            next_separators =
                std::vector<std::string>(separators.begin() + i + 1, separators.end());
            break;
        }
    }

    std::vector<std::string_view> splits;
    if (separator.empty()) {
        // Last-resort split: no separator matched, so cut on size alone. A
        // script without spaces reaches this routinely (none of "\n\n" / ". "
        // / " " occur in CJK), so the cut must land on a character boundary.
        append_utf8_bounded_slices(text_view, chunk_size_chars, splits);
    } else {
        size_t start = 0;
        size_t pos = text_view.find(separator);
        while (pos != std::string_view::npos) {
            size_t split_end = pos + separator.length();
            splits.push_back(text_view.substr(start, split_end - start));
            start = split_end;
            pos = text_view.find(separator, start);
        }
        if (start < text_view.length()) {
            splits.push_back(text_view.substr(start));
        }
    }

    std::vector<std::string_view> current_batch;
    size_t current_length = 0;

    auto emit_chunk = [&]() {
        if (current_batch.empty())
            return;
        const char* start_ptr = current_batch.front().data();
        const char* end_ptr = current_batch.back().data() + current_batch.back().length();
        size_t start_pos = start_ptr - original_text.data();
        size_t end_pos = end_ptr - original_text.data();

        TextChunk chunk;
        chunk.text = original_text.substr(start_pos, end_pos - start_pos);
        chunk.start_position = start_pos;
        chunk.end_position = end_pos;

        size_t first = chunk.text.find_first_not_of(" \t\n\r");
        size_t last = chunk.text.find_last_not_of(" \t\n\r");
        if (first != std::string::npos && last != std::string::npos) {
            chunk.text = chunk.text.substr(first, last - first + 1);
            chunk.start_position += first;
            chunk.end_position = chunk.start_position + chunk.text.length();
        } else {
            chunk.text.clear();
        }

        if (!chunk.text.empty()) {
            chunk.chunk_index = chunk_index++;
            output_chunks.push_back(std::move(chunk));
        }
    };

    for (size_t i = 0; i < splits.size(); ++i) {
        auto split = splits[i];

        if (split.length() > chunk_size_chars) {
            emit_chunk();
            current_batch.clear();
            current_length = 0;

            if (!next_separators.empty()) {
                perform_recursive_chunking(split, original_text, next_separators, chunk_size_chars,
                                           chunk_overlap_chars, output_chunks, chunk_index);
            } else {
                // Same boundary rule as the size-only path above: this
                // slices an oversized piece by size, so it must not cut
                // through a character either.
                std::vector<std::string_view> sub_splits;
                append_utf8_bounded_slices(split, chunk_size_chars, sub_splits);
                for (const auto& sub_split : sub_splits) {
                    current_batch.push_back(sub_split);
                    emit_chunk();
                    current_batch.clear();
                }
            }
            continue;
        }

        if (current_length + split.length() > chunk_size_chars && !current_batch.empty()) {
            emit_chunk();

            while (current_batch.size() > 1 &&
                   (current_length > chunk_overlap_chars ||
                    current_length + split.length() > chunk_size_chars)) {
                current_length -= current_batch.front().length();
                current_batch.erase(current_batch.begin());
            }
            if (!current_batch.empty() && current_length + split.length() > chunk_size_chars) {
                current_length -= current_batch.front().length();
                current_batch.erase(current_batch.begin());
            }
        }

        current_batch.push_back(split);
        current_length += split.length();
    }

    if (!current_batch.empty()) {
        emit_chunk();
    }
}

}  // anonymous namespace

DocumentChunker::DocumentChunker(const ChunkerConfig& config) : config_(config) {}

std::vector<TextChunk> DocumentChunker::chunk_document(const std::string& text) const {
    if (text.empty()) {
        return {};
    }

    std::vector<TextChunk> chunks;
    size_t chunk_index = 0;

    size_t chunk_size_chars = config_.chunk_size * config_.chars_per_token;
    size_t overlap_chars = config_.chunk_overlap * config_.chars_per_token;

    // Hierarchy of separators for standard English text
    std::vector<std::string> separators = {"\n\n", "\n", ". ", "? ", "! ", "; ", ", ", " ", ""};

    perform_recursive_chunking(text, text, separators, chunk_size_chars, overlap_chars, chunks,
                               chunk_index);

    return chunks;
}

size_t DocumentChunker::estimate_tokens(const std::string& text) const {
    return text.length() / config_.chars_per_token;
}

std::vector<std::string> DocumentChunker::split_into_sentences(const std::string& text) const {
    if (text.empty())
        return {};

    auto boundaries = find_sentence_boundaries(text);
    std::vector<std::string> sentences;
    sentences.reserve(boundaries.size() - 1);

    for (size_t i = 0; i + 1 < boundaries.size(); ++i) {
        std::string sentence = text.substr(boundaries[i], boundaries[i + 1] - boundaries[i]);
        // Trim whitespace
        size_t first = sentence.find_first_not_of(" \t\n\r");
        size_t last = sentence.find_last_not_of(" \t\n\r");
        if (first != std::string::npos && last != std::string::npos) {
            sentence = sentence.substr(first, last - first + 1);
        }
        if (!sentence.empty()) {
            sentences.push_back(std::move(sentence));
        }
    }
    return sentences;
}

std::vector<size_t> DocumentChunker::find_sentence_boundaries(const std::string& text) const {
    std::vector<size_t> boundaries;
    boundaries.push_back(0);  // Start of document

    for (size_t i = 0; i < text.length(); ++i) {
        char c = text[i];

        // Check for sentence endings
        if (c == '.' || c == '!' || c == '?' || c == '\n') {
            // Look ahead for whitespace
            if (i + 1 < text.length() && std::isspace(static_cast<unsigned char>(text[i + 1]))) {
                boundaries.push_back(i + 1);
            }
        }
    }

    boundaries.push_back(text.length());  // End of document
    return boundaries;
}

}  // namespace runanywhere::rag
