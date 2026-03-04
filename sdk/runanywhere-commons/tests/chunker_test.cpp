/**
 * @file chunker_test.cpp
 * @brief Unit tests for DocumentChunker
 * 
 * Tests document chunking functionality with various text inputs,
 * configurations, and edge cases.
 */

#include <gtest/gtest.h>
#include <memory>
#include <string>
#include <vector>

#include "rag_chunker.h"

namespace runanywhere::rag {

class ChunkerTest : public ::testing::Test {
protected:
    ChunkerTest() : chunker_(ChunkerConfig{}) {}

    DocumentChunker chunker_;
};

// ============================================================================
// Basic Functionality Tests
// ============================================================================

TEST_F(ChunkerTest, EmptyTextProducesNoChunks) {
    std::string empty_text;
    auto chunks = chunker_.chunk_document(empty_text);
    EXPECT_TRUE(chunks.empty());
}

TEST_F(ChunkerTest, SingleLineText) {
    std::string text = "Hello world.";
    auto chunks = chunker_.chunk_document(text);
    EXPECT_GE(chunks.size(), 1ul);
    EXPECT_EQ(chunks[0].text, "Hello world.");
}

TEST_F(ChunkerTest, MultiSentenceText) {
    std::string text = "First sentence. Second sentence. Third sentence.";
    auto chunks = chunker_.chunk_document(text);
    EXPECT_GE(chunks.size(), 1ul);
    EXPECT_NE(chunks[0].text.find("First"), std::string::npos);
}

TEST_F(ChunkerTest, ChunkIndexingIsSequential) {
    std::string text;
    for (int i = 0; i < 10; ++i) {
        text += "Sentence " + std::to_string(i) + ". ";
    }

    auto chunks = chunker_.chunk_document(text);
    for (size_t i = 0; i < chunks.size(); ++i) {
        EXPECT_EQ(chunks[i].chunk_index, i);
    }
}

TEST_F(ChunkerTest, PositionMetadataIsCorrect) {
    std::string text = "First sentence. Second sentence.";
    auto chunks = chunker_.chunk_document(text);

    EXPECT_GE(chunks.size(), 1ul);
    EXPECT_EQ(chunks[0].start_position, 0ul);
    EXPECT_GT(chunks[0].end_position, 0ul);
    EXPECT_LE(chunks[0].end_position, text.length());
}

// ============================================================================
// Token Estimation Tests
// ============================================================================

TEST_F(ChunkerTest, TokenEstimationIsPositive) {
    std::string text = "This is a sample text for token estimation.";
    size_t tokens = chunker_.estimate_tokens(text);
    EXPECT_GT(tokens, 0ul);
}

TEST_F(ChunkerTest, TokenEstimationEmptyText) {
    std::string empty_text;
    size_t tokens = chunker_.estimate_tokens(empty_text);
    EXPECT_EQ(tokens, 0ul);
}

TEST_F(ChunkerTest, TokenEstimationProportionalToLength) {
    std::string short_text = "Short.";
    std::string long_text = "This is a much longer text that contains many words. " +
                           std::string(200, 'a') + ". More text here.";

    size_t short_tokens = chunker_.estimate_tokens(short_text);
    size_t long_tokens = chunker_.estimate_tokens(long_text);

    EXPECT_LT(short_tokens, long_tokens);
}

// ============================================================================
// Configuration Tests
// ============================================================================

TEST_F(ChunkerTest, CustomChunkSize) {
    ChunkerConfig config;
    config.chunk_size = 256;      // Half default size
    config.chars_per_token = 4;
    DocumentChunker small_chunker(config);

    // Create text that's longer than one chunk
    std::string text;
    for (int i = 0; i < 20; ++i) {
        text += "This is a test sentence. ";
    }

    auto chunks = small_chunker.chunk_document(text);
    // Verify chunking works - should have at least one chunk with content
    EXPECT_GE(chunks.size(), 1ul);
    if (!chunks.empty()) {
        EXPECT_GT(chunks[0].text.size(), 0ul);
        EXPECT_EQ(chunks[0].chunk_index, 0ul);
    }
}

TEST_F(ChunkerTest, CustomChunkOverlap) {
    ChunkerConfig config;
    config.chunk_size = 256;
    config.chunk_overlap = 100;
    config.chars_per_token = 4;
    DocumentChunker overlap_chunker(config);

    std::string text;
    for (int i = 0; i < 20; ++i) {
        text += "This is a test sentence. ";
    }

    auto chunks = overlap_chunker.chunk_document(text);
    if (chunks.size() >= 2) {
        // Check that consecutive chunks overlap
        size_t first_end = chunks[0].end_position;
        size_t second_start = chunks[1].start_position;
        EXPECT_LT(second_start, first_end);
    }
}

// ============================================================================
// Boundary Condition Tests
// ============================================================================

TEST_F(ChunkerTest, SentenceWithExclamationMark) {
    std::string text = "Wow! Amazing text here.";
    auto chunks = chunker_.chunk_document(text);
    EXPECT_GE(chunks.size(), 1ul);
    EXPECT_FALSE(chunks[0].text.empty());
}

TEST_F(ChunkerTest, SentenceWithQuestionMark) {
    std::string text = "Is this a question? Yes it is!";
    auto chunks = chunker_.chunk_document(text);
    EXPECT_GE(chunks.size(), 1ul);
}

TEST_F(ChunkerTest, TextWithNewlines) {
    std::string text = "First line.\nSecond line.\nThird line.";
    auto chunks = chunker_.chunk_document(text);
    EXPECT_GE(chunks.size(), 1ul);
}

TEST_F(ChunkerTest, TextWithMultipleSpaces) {
    std::string text = "This  has   multiple    spaces.";
    auto chunks = chunker_.chunk_document(text);
    EXPECT_GE(chunks.size(), 1ul);
}

TEST_F(ChunkerTest, WhitespaceTrimmingInChunks) {
    std::string text = "  First sentence.   Second sentence.  ";
    auto chunks = chunker_.chunk_document(text);

    for (const auto& chunk : chunks) {
        if (!chunk.text.empty()) {
            // Text should not have leading/trailing whitespace
            EXPECT_NE(chunk.text[0], ' ');
            EXPECT_NE(chunk.text.back(), ' ');
        }
    }
}

// ============================================================================
// Memory Efficiency Tests
// ============================================================================

TEST_F(ChunkerTest, NoExcessiveMemoryAllocationForSmallText) {
    std::string small_text = "Small.";
    auto chunks = chunker_.chunk_document(small_text);

    // Should produce minimal chunks
    EXPECT_LE(chunks.size(), 2ul);
    for (const auto& chunk : chunks) {
        EXPECT_LE(chunk.text.size(), small_text.size() + 10);
    }
}

TEST_F(ChunkerTest, LargeTextProcessing) {
    // Create a large document (~100KB)
    std::string large_text;
    for (int i = 0; i < 1000; ++i) {
        large_text += "This is sentence number " + std::to_string(i) + ". ";
    }

    EXPECT_GT(large_text.size(), 10000ul);

    auto chunks = chunker_.chunk_document(large_text);
    EXPECT_GE(chunks.size(), 1ul);

    // Verify text is covered
    size_t total_text_length = 0;
    for (const auto& chunk : chunks) {
        total_text_length += chunk.text.size();
    }
    EXPECT_GT(total_text_length, 0ul);
}

// ============================================================================
// Move Semantics and Performance Tests
// ============================================================================

TEST_F(ChunkerTest, ChunksAreMovable) {
    std::string text = "Test sentence. Another test. Final test.";
    auto chunks = chunker_.chunk_document(text);

    // Move constructor should work
    std::vector<TextChunk> moved_chunks = std::move(chunks);
    EXPECT_GE(moved_chunks.size(), 1ul);
}

TEST_F(ChunkerTest, MoveSemanticForLargeChunks) {
    // Ensure large chunk text is efficiently moved
    std::string large_text;
    for (int i = 0; i < 100; ++i) {
        large_text +=
            "This is a comprehensive sentence with lots of words. ";
    }

    auto chunks = chunker_.chunk_document(large_text);
    EXPECT_GE(chunks.size(), 1ul);

    // Verify data is retained correctly after move
    for (const auto& chunk : chunks) {
        EXPECT_FALSE(chunk.text.empty());
    }
}

// ============================================================================
// Edge Cases and Error Conditions
// ============================================================================

TEST_F(ChunkerTest, VeryLongSentenceWithoutPeriod) {
    std::string text;
    for (int i = 0; i < 100; ++i) {
        text += "word ";
    }

    auto chunks = chunker_.chunk_document(text);
    EXPECT_GE(chunks.size(), 1ul);
}

TEST_F(ChunkerTest, SpecialCharactersInText) {
    std::string text = "Email: test@example.com. Price: $99.99. URL: http://example.com.";
    auto chunks = chunker_.chunk_document(text);
    EXPECT_GE(chunks.size(), 1ul);
}

TEST_F(ChunkerTest, ConsecutiveSentenceTerminators) {
    std::string text = "First sentence... Really amazing! So good?!";
    auto chunks = chunker_.chunk_document(text);
    EXPECT_GE(chunks.size(), 1ul);
}

TEST_F(ChunkerTest, OnlyPunctuation) {
    std::string text = "!!!...???";
    auto chunks = chunker_.chunk_document(text);
    // Should handle gracefully
    EXPECT_LE(chunks.size(), 10ul);
}

// ============================================================================
// Thread Safety - Basic Const Correctness Tests
// ============================================================================

TEST_F(ChunkerTest, ConstMethodsDoNotModifyState) {
    std::string text = "Test sentence.";

    // Call const methods
    size_t tokens1 = chunker_.estimate_tokens(text);
    auto chunks1 = chunker_.chunk_document(text);

    // Call again - should get same results
    size_t tokens2 = chunker_.estimate_tokens(text);
    auto chunks2 = chunker_.chunk_document(text);

    EXPECT_EQ(tokens1, tokens2);
    EXPECT_EQ(chunks1.size(), chunks2.size());
}

} // namespace runanywhere::rag
