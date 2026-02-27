/**
 * @file rag_chunker.cpp
 * @brief Document Chunking Implementation
 */

#include "rag_chunker.h"

#include <algorithm>
#include <cctype>

namespace runanywhere {
namespace rag {

DocumentChunker::DocumentChunker(const ChunkerConfig& config) : config_(config) {}

std::vector<TextChunk> DocumentChunker::chunk_document(const std::string& text) const {
    if (text.empty()) {
        return {};
    }

    // Find sentence boundaries
    auto boundaries = find_sentence_boundaries(text);
    
    // Split into chunks respecting boundaries
    return split_by_boundaries(text, boundaries);
}

size_t DocumentChunker::estimate_tokens(const std::string& text) const {
    const size_t chars_per_token = config_.chars_per_token > 0 ? config_.chars_per_token : 1;
    return text.length() / chars_per_token;
}

std::vector<size_t> DocumentChunker::find_sentence_boundaries(const std::string& text) const {
    std::vector<size_t> boundaries;
    boundaries.push_back(0); // Start of document

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

    boundaries.push_back(text.length()); // End of document
    return boundaries;
}

std::vector<TextChunk> DocumentChunker::split_by_boundaries(
    const std::string& text,
    const std::vector<size_t>& boundaries
) const {
    std::vector<TextChunk> chunks;
    
    size_t chunk_size_chars = config_.chunk_size * config_.chars_per_token;
    size_t overlap_chars = config_.chunk_overlap * config_.chars_per_token;
    
    size_t chunk_index = 0;
    size_t start_pos = 0;
    
    while (start_pos < text.length()) {
        // Find end position for this chunk
        size_t target_end = start_pos + chunk_size_chars;
        
        // Find the nearest boundary after target_end
        size_t end_pos = text.length();
        for (size_t boundary : boundaries) {
            if (boundary >= target_end) {
                end_pos = boundary;
                break;
            }
        }
        
        // Don't create tiny chunks at the end
        if (end_pos - start_pos < chunk_size_chars / 2 && chunk_index > 0) {
            // Merge with previous chunk or extend
            if (!chunks.empty()) {
                chunks.back().text += " " + text.substr(start_pos);
                chunks.back().end_position = text.length();
            }
            break;
        }
        
        // Create chunk
        TextChunk chunk;
        chunk.text = text.substr(start_pos, end_pos - start_pos);
        chunk.start_position = start_pos;
        chunk.end_position = end_pos;
        chunk.chunk_index = chunk_index++;
        
        // Trim whitespace
        size_t first = chunk.text.find_first_not_of(" \t\n\r");
        size_t last = chunk.text.find_last_not_of(" \t\n\r");
        if (first != std::string::npos && last != std::string::npos) {
            chunk.text = chunk.text.substr(first, last - first + 1);
        }
        
        if (!chunk.text.empty()) {
            chunks.push_back(std::move(chunk));
        }
        
        // Move to next chunk with overlap
        if (end_pos >= text.length()) {
            break;
        }
        
        start_pos = end_pos > overlap_chars ? end_pos - overlap_chars : end_pos;
    }
    
    return chunks;
}

} // namespace rag
} // namespace runanywhere
