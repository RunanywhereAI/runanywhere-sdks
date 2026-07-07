/**
 * @file test_rag_e2e.cpp
 * @brief End-to-end RAG integration test with real models.
 *
 * Drives the public proto-byte RAG ABI (rac_rag_session_create_proto /
 * rac_rag_ingest_proto / rac_rag_query_proto) with a real ONNX embedding model
 * (all-MiniLM-L6-v2) and a real GGUF LLM. Ingests a sample document and asserts
 * a grounded, non-empty answer with retrieved chunks.
 *
 * Model paths are env-overridable and the test SKIPs (exit 0) when the models
 * are not present, so it is safe to register unconditionally in CMake.
 *
 *   RAG_TEST_EMBED_MODEL  path to all-MiniLM-L6-v2 model.onnx
 *   RAG_TEST_EMBED_VOCAB  path to vocab.txt
 *   RAG_TEST_LLM_MODEL    path to the GGUF LLM
 *
 * This is the harness all subsequent RAG feature work (rerank, multi-query,
 * scoping) extends.
 */

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

#include "rac/core/rac_core.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/features/rag/rac_rag.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

#include "rac/backends/rac_llm_llamacpp.h"
#include "rac/backends/rac_vad_onnx.h"

#include "rag.pb.h"

namespace {

int g_checks = 0;
int g_failures = 0;

#define CHECK(cond, label)                                                              \
    do {                                                                                \
        ++g_checks;                                                                     \
        if (cond) {                                                                     \
            std::fprintf(stdout, "  ok:   %s\n", label);                                \
        } else {                                                                        \
            ++g_failures;                                                               \
            std::fprintf(stderr, "  FAIL: %s (%s:%d)\n", label, __FILE__, __LINE__);    \
        }                                                                               \
    } while (0)

// --------------------------------------------------------------------------
// Real file-backed platform adapter (model files need genuine file I/O).
// --------------------------------------------------------------------------

void adapter_log(rac_log_level_t level, const char* category, const char* message, void*) {
    if (level >= RAC_LOG_WARNING) {
        std::fprintf(stderr, "[rac:%s] %s\n", category ? category : "", message ? message : "");
    }
}

int64_t adapter_now_ms(void*) {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

rac_bool_t adapter_file_exists(const char* path, void*) {
    std::error_code ec;
    return std::filesystem::exists(path, ec) ? RAC_TRUE : RAC_FALSE;
}

rac_result_t adapter_file_read(const char* path, void** out_data, size_t* out_size, void*) {
    std::ifstream f(path, std::ios::binary | std::ios::ate);
    if (!f)
        return RAC_ERROR_FILE_NOT_FOUND;
    const std::streamsize n = f.tellg();
    if (n < 0)
        return RAC_ERROR_FILE_NOT_FOUND;
    f.seekg(0);
    auto* buf = static_cast<uint8_t*>(std::malloc(n > 0 ? static_cast<size_t>(n) : 1));
    if (!buf)
        return RAC_ERROR_OUT_OF_MEMORY;
    if (n > 0)
        f.read(reinterpret_cast<char*>(buf), n);
    *out_data = buf;
    *out_size = static_cast<size_t>(n);
    return RAC_SUCCESS;
}

rac_result_t adapter_file_write(const char* path, const void* data, size_t size, void*) {
    std::error_code ec;
    std::filesystem::create_directories(std::filesystem::path(path).parent_path(), ec);
    std::ofstream f(path, std::ios::binary | std::ios::trunc);
    if (!f)
        return RAC_ERROR_FILE_WRITE_FAILED;
    if (size > 0)
        f.write(static_cast<const char*>(data), static_cast<std::streamsize>(size));
    return f ? RAC_SUCCESS : RAC_ERROR_FILE_WRITE_FAILED;
}

rac_result_t adapter_file_delete(const char* path, void*) {
    std::error_code ec;
    std::filesystem::remove(path, ec);
    return RAC_SUCCESS;
}

rac_result_t adapter_secure_get(const char*, char**, void*) {
    return RAC_ERROR_FILE_NOT_FOUND;
}
rac_result_t adapter_secure_set(const char*, const char*, void*) {
    return RAC_SUCCESS;
}
rac_result_t adapter_secure_delete(const char*, void*) {
    return RAC_SUCCESS;
}

rac_platform_adapter_t make_adapter() {
    rac_platform_adapter_t a = {};
    a.abi_version = RAC_PLATFORM_ADAPTER_ABI_VERSION;
    a.struct_size = static_cast<uint32_t>(sizeof(rac_platform_adapter_t));
    a.file_exists = adapter_file_exists;
    a.file_read = adapter_file_read;
    a.file_write = adapter_file_write;
    a.file_delete = adapter_file_delete;
    a.secure_get = adapter_secure_get;
    a.secure_set = adapter_secure_set;
    a.secure_delete = adapter_secure_delete;
    a.log = adapter_log;
    a.now_ms = adapter_now_ms;
    return a;
}

// --------------------------------------------------------------------------
// Helpers
// --------------------------------------------------------------------------

std::string env_or(const char* key, const char* fallback) {
    const char* v = std::getenv(key);
    return (v && v[0]) ? std::string(v) : std::string(fallback);
}

bool file_present(const std::string& p) {
    std::error_code ec;
    return std::filesystem::exists(p, ec);
}

std::string read_file(const std::string& p) {
    std::ifstream f(p, std::ios::binary);
    if (!f)
        return {};
    return std::string((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
}

// Register a model id -> local path in the global registry so the RAG ABI can
// resolve it. Only id, local_path, category, format and framework matter here.
void register_model(const std::string& id, const std::string& path, rac_model_category_t category,
                    rac_model_format_t format, rac_inference_framework_t framework) {
    rac_model_info_t info = {};
    info.id = const_cast<char*>(id.c_str());
    info.name = const_cast<char*>(id.c_str());
    info.category = category;
    info.format = format;
    info.framework = framework;
    info.local_path = const_cast<char*>(path.c_str());
    rac_register_model(&info);
}

// Run one full session lifecycle: create → ingest → query → checks → destroy.
// `rerank` toggles RAGConfiguration.rerank_results (Item 2). Returns the answer.
std::string run_rag_case(const std::string& embed_id, const std::string& llm_id,
                         const std::string& embed_vocab, const std::string& doc_text,
                         const std::string& question, bool rerank, bool multi_query,
                         const char* label) {
    std::fprintf(stdout, "\n--- case: %s ---\n", label);

    runanywhere::v1::RAGConfiguration cfg;
    cfg.set_embedding_model_id(embed_id);
    cfg.set_llm_model_id(llm_id);
    cfg.set_embedding_config_json(std::string("{\"vocab_path\":\"") + embed_vocab + "\"}");
    cfg.set_top_k(6);
    cfg.set_chunk_size(64);
    cfg.set_chunk_overlap(8);
    cfg.set_max_context_tokens(1024);
    cfg.set_rerank_results(rerank);
    const std::string cfg_bytes = cfg.SerializeAsString();

    rac_handle_t session = nullptr;
    rac_result_t rc = rac_rag_session_create_proto(
        reinterpret_cast<const uint8_t*>(cfg_bytes.data()), cfg_bytes.size(), &session);
    CHECK(rc == RAC_SUCCESS && session != nullptr, "session created");
    if (!session)
        return {};

    runanywhere::v1::RAGDocument doc;
    doc.set_id("zephyr-protocol");
    doc.set_text(doc_text);
    const std::string doc_bytes = doc.SerializeAsString();

    rac_proto_buffer_t stats_buf;
    rac_proto_buffer_init(&stats_buf);
    rc = rac_rag_ingest_proto(session, reinterpret_cast<const uint8_t*>(doc_bytes.data()),
                              doc_bytes.size(), &stats_buf);
    CHECK(rc == RAC_SUCCESS, "ingest returned success");
    runanywhere::v1::RAGStatistics stats;
    if (stats_buf.data && stats_buf.size > 0)
        stats.ParseFromArray(stats_buf.data, static_cast<int>(stats_buf.size));
    CHECK(stats.indexed_chunks() > 0, "ingest produced chunks");
    rac_proto_buffer_free(&stats_buf);

    runanywhere::v1::RAGQueryOptions q;
    q.set_question(question);
    q.set_max_tokens(160);
    q.set_temperature(0.0f);
    if (multi_query)
        q.set_enable_multi_query(true);
    const std::string q_bytes = q.SerializeAsString();

    rac_proto_buffer_t res_buf;
    rac_proto_buffer_init(&res_buf);
    rc = rac_rag_query_proto(session, reinterpret_cast<const uint8_t*>(q_bytes.data()),
                             q_bytes.size(), &res_buf);
    CHECK(rc == RAC_SUCCESS, "query returned success");
    runanywhere::v1::RAGResult result;
    if (res_buf.data && res_buf.size > 0)
        result.ParseFromArray(res_buf.data, static_cast<int>(res_buf.size));
    rac_proto_buffer_free(&res_buf);

    CHECK(!result.answer().empty(), "answer is non-empty");
    CHECK(result.retrieved_chunks_size() > 0, "at least one chunk retrieved");
    std::fprintf(stdout, "  info: retrieved_chunks=%d generation_ms=%lld\n",
                 result.retrieved_chunks_size(),
                 static_cast<long long>(result.generation_time_ms()));
    std::fprintf(stdout, "  answer: %s\n", result.answer().c_str());

    rac_rag_session_destroy_proto(session);
    return result.answer();
}

// Item 3b: ingesting the same document twice must not re-chunk / re-embed —
// the second ingest is a content-hash hit, so the chunk count stays flat.
void run_dedup_case(const std::string& embed_id, const std::string& llm_id,
                    const std::string& embed_vocab, const std::string& doc_text) {
    std::fprintf(stdout, "\n--- case: content-addressed dedup (no re-embed) ---\n");

    runanywhere::v1::RAGConfiguration cfg;
    cfg.set_embedding_model_id(embed_id);
    cfg.set_llm_model_id(llm_id);
    cfg.set_embedding_config_json(std::string("{\"vocab_path\":\"") + embed_vocab + "\"}");
    cfg.set_top_k(4);
    const std::string cb = cfg.SerializeAsString();

    rac_handle_t s = nullptr;
    rac_rag_session_create_proto(reinterpret_cast<const uint8_t*>(cb.data()), cb.size(), &s);
    CHECK(s != nullptr, "dedup: session created");
    if (!s)
        return;

    auto ingest = [&](const char* id) -> int64_t {
        runanywhere::v1::RAGDocument doc;
        doc.set_id(id);
        doc.set_text(doc_text);
        const std::string db = doc.SerializeAsString();
        rac_proto_buffer_t sb;
        rac_proto_buffer_init(&sb);
        rac_rag_ingest_proto(s, reinterpret_cast<const uint8_t*>(db.data()), db.size(), &sb);
        runanywhere::v1::RAGStatistics st;
        if (sb.data && sb.size > 0)
            st.ParseFromArray(sb.data, static_cast<int>(sb.size));
        rac_proto_buffer_free(&sb);
        return st.indexed_chunks();
    };

    const int64_t after_first = ingest("doc-1");
    const int64_t after_second = ingest("doc-1-again");
    CHECK(after_first > 0, "dedup: first ingest produced chunks");
    CHECK(after_second == after_first, "dedup: re-ingest added no chunks (no re-embed)");
    std::fprintf(stdout, "  info: chunks after 1st=%lld, after 2nd=%lld\n",
                 static_cast<long long>(after_first), static_cast<long long>(after_second));

    rac_rag_session_destroy_proto(s);
}

// Item 8: a positive session-level similarity floor filters out MiniLM-class
// matches (cosine rarely exceeds ~0.5); an explicit per-query 0.0 override must
// restore results, while omitting the override keeps the session floor.
void run_threshold_override_case(const std::string& embed_id, const std::string& llm_id,
                                 const std::string& embed_vocab, const std::string& doc_text) {
    std::fprintf(stdout, "\n--- case: explicit 0.0 threshold override ---\n");

    runanywhere::v1::RAGConfiguration cfg;
    cfg.set_embedding_model_id(embed_id);
    cfg.set_llm_model_id(llm_id);
    cfg.set_embedding_config_json(std::string("{\"vocab_path\":\"") + embed_vocab + "\"}");
    cfg.set_top_k(4);
    cfg.set_similarity_threshold(0.95f);  // effectively filters everything
    const std::string cb = cfg.SerializeAsString();

    rac_handle_t s = nullptr;
    rac_rag_session_create_proto(reinterpret_cast<const uint8_t*>(cb.data()), cb.size(), &s);
    CHECK(s != nullptr, "threshold: session created");
    if (!s)
        return;

    runanywhere::v1::RAGDocument doc;
    doc.set_id("zephyr");
    doc.set_text(doc_text);
    const std::string db = doc.SerializeAsString();
    rac_proto_buffer_t sb;
    rac_proto_buffer_init(&sb);
    rac_rag_ingest_proto(s, reinterpret_cast<const uint8_t*>(db.data()), db.size(), &sb);
    rac_proto_buffer_free(&sb);

    // A probe word absent from the document: BM25 (lexical, no similarity floor)
    // returns nothing, so the dense similarity threshold alone decides the
    // outcome — which is exactly what the override controls.
    const std::string probe = "xylophone";
    auto query_chunks = [&](bool set_override) -> int {
        runanywhere::v1::RAGQueryOptions q;
        q.set_question(probe);
        q.set_max_tokens(64);
        q.set_temperature(0.0f);
        if (set_override)
            q.set_similarity_threshold(0.0f);  // explicit accept-all
        const std::string qb = q.SerializeAsString();
        rac_proto_buffer_t rb;
        rac_proto_buffer_init(&rb);
        rac_rag_query_proto(s, reinterpret_cast<const uint8_t*>(qb.data()), qb.size(), &rb);
        runanywhere::v1::RAGResult result;
        if (rb.data && rb.size > 0)
            result.ParseFromArray(rb.data, static_cast<int>(rb.size));
        rac_proto_buffer_free(&rb);
        return result.retrieved_chunks_size();
    };

    const int without_override = query_chunks(false);
    const int with_override = query_chunks(true);
    CHECK(without_override == 0, "threshold: session floor 0.95 filters all (no override)");
    CHECK(with_override > 0, "threshold: explicit 0.0 override restores results");
    std::fprintf(stdout, "  info: chunks without_override=%d with_override=%d\n", without_override,
                 with_override);

    rac_rag_session_destroy_proto(s);
}

// Item 7: ingest two documents under distinct id namespaces, then query with a
// scope_prefix — only chunks from the scoped document must come back.
void run_scoping_case(const std::string& embed_id, const std::string& llm_id,
                      const std::string& embed_vocab, const std::string& zephyr_text) {
    std::fprintf(stdout, "\n--- case: scoped retrieval (docId prefix) ---\n");

    // A second, unrelated document with a unique marker word ("Kelp").
    const std::string other_text =
        "The Kelp Ledger is a distributed accounting format for tidal energy cooperatives. "
        "It records membership shares and settlement batches in an append-only log. "
        "Kelp Ledger settlements are reconciled every lunar quarter by elected auditors.";

    runanywhere::v1::RAGConfiguration cfg;
    cfg.set_embedding_model_id(embed_id);
    cfg.set_llm_model_id(llm_id);
    cfg.set_embedding_config_json(std::string("{\"vocab_path\":\"") + embed_vocab + "\"}");
    cfg.set_top_k(4);
    const std::string cb = cfg.SerializeAsString();

    rac_handle_t s = nullptr;
    rac_rag_session_create_proto(reinterpret_cast<const uint8_t*>(cb.data()), cb.size(), &s);
    CHECK(s != nullptr, "scope: session created");
    if (!s)
        return;

    auto ingest = [&](const char* id, const std::string& text) {
        runanywhere::v1::RAGDocument doc;
        doc.set_id(id);
        doc.set_text(text);
        const std::string db = doc.SerializeAsString();
        rac_proto_buffer_t sb;
        rac_proto_buffer_init(&sb);
        rac_rag_ingest_proto(s, reinterpret_cast<const uint8_t*>(db.data()), db.size(), &sb);
        rac_proto_buffer_free(&sb);
    };
    ingest("zephyr:doc", zephyr_text);
    ingest("kelp:doc", other_text);

    runanywhere::v1::RAGQueryOptions q;
    q.set_question("Summarize the document.");
    q.set_max_tokens(96);
    q.set_temperature(0.0f);
    q.set_scope_prefix("kelp:");
    const std::string qb = q.SerializeAsString();

    rac_proto_buffer_t rb;
    rac_proto_buffer_init(&rb);
    rac_rag_query_proto(s, reinterpret_cast<const uint8_t*>(qb.data()), qb.size(), &rb);
    runanywhere::v1::RAGResult result;
    if (rb.data && rb.size > 0)
        result.ParseFromArray(rb.data, static_cast<int>(rb.size));
    rac_proto_buffer_free(&rb);

    CHECK(result.retrieved_chunks_size() > 0, "scope: chunks retrieved under scope");
    bool any_zephyr = false;
    bool any_kelp = false;
    for (int i = 0; i < result.retrieved_chunks_size(); ++i) {
        const std::string& t = result.retrieved_chunks(i).text();
        if (t.find("Zephyr") != std::string::npos)
            any_zephyr = true;
        if (t.find("Kelp") != std::string::npos)
            any_kelp = true;
    }
    CHECK(!any_zephyr, "scope: no out-of-scope (zephyr) chunks leaked");
    CHECK(any_kelp, "scope: in-scope (kelp) chunks returned");
    std::fprintf(stdout, "  info: chunks=%d zephyr_leak=%s kelp_present=%s\n",
                 result.retrieved_chunks_size(), any_zephyr ? "yes" : "no",
                 any_kelp ? "yes" : "no");

    rac_rag_session_destroy_proto(s);
}

}  // namespace

int main() {
    std::fprintf(stdout, "=== RAG end-to-end test ===\n");

    const std::string embed_model =
        env_or("RAG_TEST_EMBED_MODEL",
               "/home/home/Downloads/rag-test-models/all-MiniLM-L6-v2/model.onnx");
    const std::string embed_vocab =
        env_or("RAG_TEST_EMBED_VOCAB",
               "/home/home/Downloads/rag-test-models/all-MiniLM-L6-v2/vocab.txt");
    const std::string llm_model =
        env_or("RAG_TEST_LLM_MODEL", "/home/home/Downloads/LFM2.5-1.2B-Instruct-Q4_K_M.gguf");
    const std::string sample_doc = env_or("RAG_TEST_SAMPLE_DOC", RAG_SAMPLE_DOC_PATH);

    if (!file_present(embed_model) || !file_present(embed_vocab) || !file_present(llm_model)) {
        std::fprintf(stdout, "SKIP: models not found\n  embed=%s\n  vocab=%s\n  llm=%s\n",
                     embed_model.c_str(), embed_vocab.c_str(), llm_model.c_str());
        return 0;
    }

    const rac_platform_adapter_t adapter = make_adapter();
    rac_config_t config = {};
    config.platform_adapter = &adapter;
    config.log_level = RAC_LOG_WARNING;
    config.log_tag = "TEST_RAG_E2E";
    if (rac_init(&config) != RAC_SUCCESS) {
        std::fprintf(stderr, "FATAL: rac_init failed\n");
        return 1;
    }
    rac_backend_llamacpp_register();
    rac_backend_onnx_register();

    const std::string embed_id = "test-embed-minilm";
    const std::string llm_id = "test-llm-lfm2";
    register_model(embed_id, embed_model, RAC_MODEL_CATEGORY_EMBEDDING, RAC_MODEL_FORMAT_ONNX,
                   RAC_FRAMEWORK_ONNX);
    register_model(llm_id, llm_model, RAC_MODEL_CATEGORY_LANGUAGE, RAC_MODEL_FORMAT_GGUF,
                   RAC_FRAMEWORK_LLAMACPP);

    const std::string doc_text = read_file(sample_doc);
    CHECK(!doc_text.empty(), "sample document loaded");

    const std::string question =
        "How does the Zephyr Protocol avoid transmitting the same data twice?";

    // Baseline pipeline (rerank off) and the Item 2 rerank path (rerank on).
    // Both must produce a grounded, non-empty answer with retrieved chunks.
    run_rag_case(embed_id, llm_id, embed_vocab, doc_text, question, /*rerank=*/false,
                 /*multi_query=*/false, "baseline");
    run_rag_case(embed_id, llm_id, embed_vocab, doc_text, question, /*rerank=*/true,
                 /*multi_query=*/false, "llm-pointwise rerank");
    run_rag_case(embed_id, llm_id, embed_vocab, doc_text, question, /*rerank=*/false,
                 /*multi_query=*/true, "multi-query expansion");
    run_dedup_case(embed_id, llm_id, embed_vocab, doc_text);
    run_scoping_case(embed_id, llm_id, embed_vocab, doc_text);
    run_threshold_override_case(embed_id, llm_id, embed_vocab, doc_text);

    rac_shutdown();

    std::fprintf(stdout, "=== %d checks, %d failures ===\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
