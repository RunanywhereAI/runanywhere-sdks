// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include <gtest/gtest.h>

#include "../abi/ra_rag.h"
#include "../abi/ra_primitives.h"

#include <cstdlib>
#include <string>

TEST(RaRagChunker, SimpleSplit) {
    const char* text = "aaaaaaaaaaaaaaaaaaaa";  // 20 chars
    ra_rag_chunk_t* chunks = nullptr;
    int32_t count = 0;
    ASSERT_EQ(ra_rag_chunk_text(text, 10, 2, &chunks, &count), RA_OK);
    // stride = 8 -> positions 0, 8, 16. Last covers to end.
    ASSERT_EQ(count, 3);
    EXPECT_EQ(chunks[0].start_offset, 0);
    EXPECT_EQ(chunks[0].end_offset,   10);
    EXPECT_EQ(chunks[1].start_offset, 8);
    EXPECT_EQ(chunks[2].chunk_index,  2);
    ra_rag_chunks_free(chunks, count);
}

TEST(RaRagChunker, EmptyInputYieldsNoChunks) {
    ra_rag_chunk_t* chunks = nullptr;
    int32_t count = -1;
    ASSERT_EQ(ra_rag_chunk_text("", 100, 10, &chunks, &count), RA_OK);
    EXPECT_EQ(count, 0);
    ra_rag_chunks_free(chunks, count);
}

TEST(RaRagStore, AddSearchRecall) {
    ra_rag_vector_store_t* store = nullptr;
    ASSERT_EQ(ra_rag_store_create(3, &store), RA_OK);
    const float a[] = {1.0f, 0.0f, 0.0f};
    const float b[] = {0.0f, 1.0f, 0.0f};
    const float c[] = {0.0f, 0.0f, 1.0f};
    ra_rag_store_add(store, "A", "{}", a, 3);
    ra_rag_store_add(store, "B", "{}", b, 3);
    ra_rag_store_add(store, "C", "{}", c, 3);
    EXPECT_EQ(ra_rag_store_size(store), 3);

    const float query[] = {0.9f, 0.1f, 0.0f};
    char** ids = nullptr;
    char** meta = nullptr;
    float* scores = nullptr;
    int32_t count = 0;
    ASSERT_EQ(ra_rag_store_search(store, query, 3, 2,
                                      &ids, &meta, &scores, &count), RA_OK);
    ASSERT_EQ(count, 2);
    EXPECT_STREQ(ids[0], "A");
    EXPECT_GT(scores[0], scores[1]);
    ra_rag_strings_free(ids,  count);
    ra_rag_strings_free(meta, count);
    ra_rag_floats_free(scores);

    ra_rag_store_destroy(store);
}

TEST(RaRagStore, RemoveReducesSize) {
    ra_rag_vector_store_t* store = nullptr;
    ra_rag_store_create(2, &store);
    const float v[] = {1.0f, 0.0f};
    ra_rag_store_add(store, "A", "", v, 2);
    ra_rag_store_add(store, "B", "", v, 2);
    EXPECT_EQ(ra_rag_store_size(store), 2);
    EXPECT_EQ(ra_rag_store_remove(store, "A"), RA_OK);
    EXPECT_EQ(ra_rag_store_size(store), 1);
    ra_rag_store_destroy(store);
}

TEST(RaRagFormatContext, ProducesReadableBlock) {
    const char* texts[] = {"hello", "world"};
    const char* meta[]  = {"{\"src\":\"doc1\"}", ""};
    char* out = nullptr;
    ASSERT_EQ(ra_rag_format_context(texts, meta, 2, &out), RA_OK);
    ASSERT_TRUE(out);
    const std::string body = out;
    EXPECT_NE(body.find("[#1] {\"src\":\"doc1\"}"), std::string::npos);
    EXPECT_NE(body.find("hello"), std::string::npos);
    EXPECT_NE(body.find("[#2]"), std::string::npos);
    EXPECT_NE(body.find("world"), std::string::npos);
    ra_rag_string_free(out);
}
