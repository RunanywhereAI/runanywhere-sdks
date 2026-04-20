// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "ra_rag.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <numeric>
#include <sstream>
#include <string>
#include <vector>

namespace {

char* dup_cstr(const std::string& s) {
    char* out = static_cast<char*>(std::malloc(s.size() + 1));
    if (!out) return nullptr;
    std::memcpy(out, s.data(), s.size());
    out[s.size()] = '\0';
    return out;
}

}  // namespace

// ---------------------------------------------------------------------------
// Vector store internal state
// ---------------------------------------------------------------------------

struct ra_rag_vector_store_s {
    std::mutex              mu;
    int32_t                 dim = 0;
    std::vector<std::string> ids;
    std::vector<std::string> metadata;
    std::vector<std::vector<float>> vectors;  // each pre-normalized to unit length
};

namespace {

void normalize_inplace(std::vector<float>& v) {
    double sum = 0;
    for (float x : v) sum += double(x) * x;
    if (sum <= 0) return;
    const double inv = 1.0 / std::sqrt(sum);
    for (auto& x : v) x = static_cast<float>(x * inv);
}

}  // namespace

extern "C" {

// ---------------------------------------------------------------------------
// Chunker
// ---------------------------------------------------------------------------

ra_status_t ra_rag_chunk_text(const char*       text,
                                int32_t           max_chunk_chars,
                                int32_t           overlap_chars,
                                ra_rag_chunk_t**  out_chunks,
                                int32_t*          out_count) {
    if (!text || !out_chunks || !out_count || max_chunk_chars <= 0)
        return RA_ERR_INVALID_ARGUMENT;
    if (overlap_chars < 0 || overlap_chars >= max_chunk_chars)
        return RA_ERR_INVALID_ARGUMENT;

    std::string src = text;
    std::vector<ra_rag_chunk_t> chunks;
    const int32_t stride = max_chunk_chars - overlap_chars;
    int32_t i = 0;
    int32_t idx = 0;
    while (i < static_cast<int32_t>(src.size())) {
        const int32_t end = std::min(static_cast<int32_t>(src.size()),
                                        i + max_chunk_chars);
        ra_rag_chunk_t ch{};
        ch.text         = dup_cstr(src.substr(i, end - i));
        ch.start_offset = i;
        ch.end_offset   = end;
        ch.chunk_index  = idx++;
        if (!ch.text) {
            // Partial cleanup on OOM
            for (auto& c : chunks) std::free(c.text);
            return RA_ERR_OUT_OF_MEMORY;
        }
        chunks.push_back(ch);
        if (end >= static_cast<int32_t>(src.size())) break;
        i += stride;
    }

    *out_count  = static_cast<int32_t>(chunks.size());
    if (chunks.empty()) { *out_chunks = nullptr; return RA_OK; }
    *out_chunks = static_cast<ra_rag_chunk_t*>(
        std::malloc(sizeof(ra_rag_chunk_t) * chunks.size()));
    if (!*out_chunks) {
        for (auto& c : chunks) std::free(c.text);
        return RA_ERR_OUT_OF_MEMORY;
    }
    std::memcpy(*out_chunks, chunks.data(),
                sizeof(ra_rag_chunk_t) * chunks.size());
    return RA_OK;
}

void ra_rag_chunks_free(ra_rag_chunk_t* chunks, int32_t count) {
    if (!chunks) return;
    for (int32_t i = 0; i < count; ++i) std::free(chunks[i].text);
    std::free(chunks);
}

// ---------------------------------------------------------------------------
// Vector store
// ---------------------------------------------------------------------------

ra_status_t ra_rag_store_create(int32_t embedding_dim,
                                 ra_rag_vector_store_t** out_store) {
    if (embedding_dim <= 0 || !out_store) return RA_ERR_INVALID_ARGUMENT;
    auto* s = new (std::nothrow) ra_rag_vector_store_s();
    if (!s) return RA_ERR_OUT_OF_MEMORY;
    s->dim = embedding_dim;
    *out_store = s;
    return RA_OK;
}

void ra_rag_store_destroy(ra_rag_vector_store_t* store) {
    delete store;
}

ra_status_t ra_rag_store_add(ra_rag_vector_store_t* store,
                              const char*           row_id,
                              const char*           metadata_json,
                              const float*          embedding,
                              int32_t               dim) {
    if (!store || !row_id || !embedding || dim != store->dim) {
        return RA_ERR_INVALID_ARGUMENT;
    }
    std::lock_guard lk(store->mu);
    store->ids.push_back(row_id);
    store->metadata.push_back(metadata_json ? metadata_json : "");
    std::vector<float> v(embedding, embedding + dim);
    normalize_inplace(v);
    store->vectors.push_back(std::move(v));
    return RA_OK;
}

ra_status_t ra_rag_store_remove(ra_rag_vector_store_t* store,
                                 const char*           row_id) {
    if (!store || !row_id) return RA_ERR_INVALID_ARGUMENT;
    std::lock_guard lk(store->mu);
    auto it = std::find(store->ids.begin(), store->ids.end(), row_id);
    if (it == store->ids.end()) return RA_ERR_INVALID_ARGUMENT;
    const auto idx = it - store->ids.begin();
    store->ids.erase(store->ids.begin() + idx);
    store->metadata.erase(store->metadata.begin() + idx);
    store->vectors.erase(store->vectors.begin() + idx);
    return RA_OK;
}

ra_status_t ra_rag_store_clear(ra_rag_vector_store_t* store) {
    if (!store) return RA_ERR_INVALID_ARGUMENT;
    std::lock_guard lk(store->mu);
    store->ids.clear();
    store->metadata.clear();
    store->vectors.clear();
    return RA_OK;
}

int32_t ra_rag_store_size(ra_rag_vector_store_t* store) {
    if (!store) return 0;
    std::lock_guard lk(store->mu);
    return static_cast<int32_t>(store->ids.size());
}

ra_status_t ra_rag_store_search(ra_rag_vector_store_t* store,
                                  const float*          query,
                                  int32_t               dim,
                                  int32_t               top_k,
                                  char***               out_ids,
                                  char***               out_metadata_jsons,
                                  float**               out_scores,
                                  int32_t*              out_count) {
    if (!store || !query || top_k <= 0 || !out_ids || !out_metadata_jsons ||
        !out_scores || !out_count || dim != store->dim) {
        return RA_ERR_INVALID_ARGUMENT;
    }
    std::vector<float> q(query, query + dim);
    normalize_inplace(q);

    std::lock_guard lk(store->mu);
    const auto n = store->ids.size();
    std::vector<std::pair<float, std::size_t>> scored;
    scored.reserve(n);
    for (std::size_t i = 0; i < n; ++i) {
        double dot = 0;
        for (int32_t d = 0; d < dim; ++d) dot += double(q[d]) * store->vectors[i][d];
        scored.emplace_back(static_cast<float>(dot), i);
    }
    std::sort(scored.begin(), scored.end(),
                [](const auto& a, const auto& b) { return a.first > b.first; });
    const int32_t k = std::min<int32_t>(top_k, static_cast<int32_t>(n));
    *out_count         = k;
    if (k == 0) {
        *out_ids = nullptr; *out_metadata_jsons = nullptr; *out_scores = nullptr;
        return RA_OK;
    }
    *out_ids              = static_cast<char**>(std::malloc(sizeof(char*) * k));
    *out_metadata_jsons   = static_cast<char**>(std::malloc(sizeof(char*) * k));
    *out_scores           = static_cast<float*>(std::malloc(sizeof(float) * k));
    if (!*out_ids || !*out_metadata_jsons || !*out_scores) {
        std::free(*out_ids); std::free(*out_metadata_jsons); std::free(*out_scores);
        *out_ids = nullptr; *out_metadata_jsons = nullptr; *out_scores = nullptr;
        return RA_ERR_OUT_OF_MEMORY;
    }
    for (int32_t i = 0; i < k; ++i) {
        const auto idx = scored[i].second;
        (*out_ids)[i]            = dup_cstr(store->ids[idx]);
        (*out_metadata_jsons)[i] = dup_cstr(store->metadata[idx]);
        (*out_scores)[i]         = scored[i].first;
    }
    return RA_OK;
}

// ---------------------------------------------------------------------------
// Pipeline helpers
// ---------------------------------------------------------------------------

ra_status_t ra_rag_format_context(const char* const* chunk_texts,
                                    const char* const* chunk_metadata_jsons,
                                    int32_t            chunk_count,
                                    char**             out_context) {
    if (!out_context || chunk_count < 0) return RA_ERR_INVALID_ARGUMENT;
    if (chunk_count > 0 && (!chunk_texts || !chunk_metadata_jsons))
        return RA_ERR_INVALID_ARGUMENT;
    std::ostringstream os;
    for (int32_t i = 0; i < chunk_count; ++i) {
        os << "[#" << (i + 1) << "]";
        if (chunk_metadata_jsons[i] && chunk_metadata_jsons[i][0]) {
            os << " " << chunk_metadata_jsons[i];
        }
        os << "\n" << (chunk_texts[i] ? chunk_texts[i] : "") << "\n\n";
    }
    *out_context = dup_cstr(os.str());
    return *out_context ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}

void ra_rag_string_free(char* str) { if (str) std::free(str); }
void ra_rag_strings_free(char** strs, int32_t count) {
    if (!strs) return;
    for (int32_t i = 0; i < count; ++i) std::free(strs[i]);
    std::free(strs);
}
void ra_rag_floats_free(float* floats) { if (floats) std::free(floats); }

}  // extern "C"
