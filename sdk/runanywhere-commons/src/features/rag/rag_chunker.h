/**
 * @file rag_chunker.h
 * @brief Document Chunking for RAG
 *
 * Splits documents into overlapping chunks for embedding.
 */

#ifndef RUNANYWHERE_RAG_CHUNKER_H
#define RUNANYWHERE_RAG_CHUNKER_H

#include <string>
#include <vector>

namespace runanywhere {
namespace rag {

/**
 * @brief Document chunk with position information
 */
struct TextChunk {
    std::string text;
    size_t start_position;
    size_t end_position;
    size_t chunk_index;
};

/**
 * @brief Chunking configuration
 */
struct ChunkerConfig {
    size_t chunk_size = 180;      // Approximate tokens per chunk
    size_t chunk_overlap = 30;     // Overlap tokens
    size_t chars_per_token = 4;    // Rough estimate for token counting
};

/**
 * @brief Document chunker
 */
class DocumentChunker {
public:
    explicit DocumentChunker(const ChunkerConfig& config = ChunkerConfig{});

    /**
     * @brief Split document into chunks
     *
     * Uses sentence boundaries to avoid breaking mid-sentence.
     */
    std::vector<TextChunk> chunk_document(const std::string& text) const;

    /**
     * @brief Estimate token count for text
     */
    size_t estimate_tokens(const std::string& text) const;

    /**
     * @brief Split text into individual sentences
     *
     * Uses the same sentence boundary detection as chunk_document().
     * Sentences are trimmed of whitespace. Empty sentences are excluded.
     *
     * @param text Input text to split
     * @return Vector of sentence strings
     */
    std::vector<std::string> split_into_sentences(const std::string& text) const;

private:
    ChunkerConfig config_;

    std::vector<size_t> find_sentence_boundaries(const std::string& text) const;
};

} // namespace rag
} // namespace runanywhere

#endif // RUNANYWHERE_RAG_CHUNKER_H
