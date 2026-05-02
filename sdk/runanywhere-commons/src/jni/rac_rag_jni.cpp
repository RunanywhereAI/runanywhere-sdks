/**
 * @file rac_rag_jni.cpp
 * @brief RunAnywhere Commons - RAG JNI bridge (RunAnywhereBridge.racRag*).
 *
 * Mirrors Swift's `CppBridge.RAG.shared` actor: a single per-process
 * pipeline handle plus thin C-ABI wrappers around `rac_rag_pipeline_*`.
 *
 * Wire format: hand-rolled proto3 encode/decode for `RAGConfiguration`,
 * `RAGQueryOptions`, `RAGResult`, and `RAGStatistics`. We deliberately do
 * not depend on `libprotobuf` here because Android cross-builds do not
 * discover Protobuf via `find_package`. The wire layout below is locked
 * to `idl/rag.proto` field numbers / types — keep them in sync.
 *
 * Package: com.runanywhere.sdk.native.bridge
 * Class:   RunAnywhereBridge
 *
 * Thunks exported here:
 *   - racRagCreatePipeline(byte[])     -> int
 *   - racRagDestroyPipeline()          -> int
 *   - racRagIngest(String, String?)    -> int
 *   - racRagAddDocumentsBatch(String)  -> int   (JSON array of {id,text,metadata_json})
 *   - racRagQuery(String, byte[]?)     -> byte[]?
 *   - racRagClearDocuments()           -> int
 *   - racRagGetDocumentCount()         -> int
 *   - racRagGetStatistics()            -> byte[]?
 */

#include <jni.h>

#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/features/rag/rac_rag_pipeline.h"

#ifdef __ANDROID__
#include <android/log.h>
static const char* RAG_JNI_LOG_TAG = "JNI.RACRag";
#define LOGi(...) __android_log_print(ANDROID_LOG_INFO, RAG_JNI_LOG_TAG, __VA_ARGS__)
#define LOGe(...) __android_log_print(ANDROID_LOG_ERROR, RAG_JNI_LOG_TAG, __VA_ARGS__)
#define LOGw(...) __android_log_print(ANDROID_LOG_WARN, RAG_JNI_LOG_TAG, __VA_ARGS__)
#else
static const char* RAG_JNI_LOG_TAG = "JNI.RACRag";
#define LOGi(...) RAC_LOG_INFO(RAG_JNI_LOG_TAG, __VA_ARGS__)
#define LOGe(...) RAC_LOG_ERROR(RAG_JNI_LOG_TAG, __VA_ARGS__)
#define LOGw(...) RAC_LOG_WARNING(RAG_JNI_LOG_TAG, __VA_ARGS__)
#endif

extern "C" rac_result_t rac_backend_rag_register(void);
extern "C" rac_result_t rac_backend_rag_unregister(void);

namespace {

// =============================================================================
// Proto3 wire-format helpers (mirrors src/features/llm/rac_llm_stream.cpp)
// =============================================================================

inline void wire_varint(std::vector<uint8_t>& out, uint64_t value) {
    while (value >= 0x80u) {
        out.push_back(static_cast<uint8_t>(value | 0x80u));
        value >>= 7;
    }
    out.push_back(static_cast<uint8_t>(value));
}

inline void wire_tag(std::vector<uint8_t>& out, uint32_t field, uint32_t wire_type) {
    wire_varint(out, (static_cast<uint64_t>(field) << 3) | wire_type);
}

inline void wire_int32_field(std::vector<uint8_t>& out, uint32_t field, int32_t value) {
    if (value == 0) return;
    wire_tag(out, field, 0);
    wire_varint(out, static_cast<uint64_t>(static_cast<int64_t>(value)));
}

inline void wire_int64_field(std::vector<uint8_t>& out, uint32_t field, int64_t value) {
    if (value == 0) return;
    wire_tag(out, field, 0);
    wire_varint(out, static_cast<uint64_t>(value));
}

inline void wire_float_field(std::vector<uint8_t>& out, uint32_t field, float value) {
    if (value == 0.0f) return;
    wire_tag(out, field, 5);
    uint32_t bits;
    std::memcpy(&bits, &value, sizeof(bits));
    out.push_back(static_cast<uint8_t>(bits & 0xff));
    out.push_back(static_cast<uint8_t>((bits >> 8) & 0xff));
    out.push_back(static_cast<uint8_t>((bits >> 16) & 0xff));
    out.push_back(static_cast<uint8_t>((bits >> 24) & 0xff));
}

inline void wire_string_field(std::vector<uint8_t>& out, uint32_t field, const std::string& str) {
    if (str.empty()) return;
    wire_tag(out, field, 2);
    wire_varint(out, str.size());
    out.insert(out.end(), str.begin(), str.end());
}

inline void wire_string_field(std::vector<uint8_t>& out, uint32_t field, const char* str) {
    if (!str || str[0] == '\0') return;
    const size_t len = std::strlen(str);
    wire_tag(out, field, 2);
    wire_varint(out, len);
    out.insert(out.end(), str, str + len);
}

inline void wire_submessage_field(std::vector<uint8_t>& out, uint32_t field,
                                  const std::vector<uint8_t>& bytes) {
    wire_tag(out, field, 2);
    wire_varint(out, bytes.size());
    out.insert(out.end(), bytes.begin(), bytes.end());
}

// =============================================================================
// Proto3 wire-format decoder
// =============================================================================

class WireReader {
public:
    WireReader(const uint8_t* data, size_t len) : end_(data + len), pos_(data) {}

    bool eof() const { return pos_ >= end_; }
    const uint8_t* pos() const { return pos_; }

    bool read_varint(uint64_t* out) {
        uint64_t value = 0;
        int shift = 0;
        while (pos_ < end_) {
            uint8_t b = *pos_++;
            value |= static_cast<uint64_t>(b & 0x7f) << shift;
            if ((b & 0x80) == 0) {
                *out = value;
                return true;
            }
            shift += 7;
            if (shift >= 64) return false;
        }
        return false;
    }

    bool read_tag(uint32_t* field, uint32_t* wire_type) {
        uint64_t tag;
        if (!read_varint(&tag)) return false;
        *field = static_cast<uint32_t>(tag >> 3);
        *wire_type = static_cast<uint32_t>(tag & 0x7);
        return true;
    }

    bool read_int32(int32_t* out) {
        uint64_t v;
        if (!read_varint(&v)) return false;
        *out = static_cast<int32_t>(v);
        return true;
    }

    bool read_int64(int64_t* out) {
        uint64_t v;
        if (!read_varint(&v)) return false;
        *out = static_cast<int64_t>(v);
        return true;
    }

    bool read_float(float* out) {
        if (pos_ + 4 > end_) return false;
        uint32_t bits = static_cast<uint32_t>(pos_[0]) |
                        (static_cast<uint32_t>(pos_[1]) << 8) |
                        (static_cast<uint32_t>(pos_[2]) << 16) |
                        (static_cast<uint32_t>(pos_[3]) << 24);
        std::memcpy(out, &bits, sizeof(*out));
        pos_ += 4;
        return true;
    }

    bool read_string(std::string* out) {
        uint64_t len;
        if (!read_varint(&len)) return false;
        if (static_cast<uint64_t>(end_ - pos_) < len) return false;
        out->assign(reinterpret_cast<const char*>(pos_), static_cast<size_t>(len));
        pos_ += len;
        return true;
    }

    bool skip(uint32_t wire_type) {
        switch (wire_type) {
            case 0: {  // varint
                uint64_t dummy;
                return read_varint(&dummy);
            }
            case 1: {  // 64-bit fixed
                if (pos_ + 8 > end_) return false;
                pos_ += 8;
                return true;
            }
            case 2: {  // length-delimited
                uint64_t len;
                if (!read_varint(&len)) return false;
                if (static_cast<uint64_t>(end_ - pos_) < len) return false;
                pos_ += len;
                return true;
            }
            case 5: {  // 32-bit fixed
                if (pos_ + 4 > end_) return false;
                pos_ += 4;
                return true;
            }
            default:
                return false;  // groups (3,4) not supported in proto3
        }
    }

private:
    const uint8_t* end_;
    const uint8_t* pos_;
};

// =============================================================================
// RAGConfiguration decode (idl/rag.proto fields):
//   1: string embedding_model_path
//   2: string llm_model_path
//   3: int32  embedding_dimension
//   4: int32  top_k
//   5: float  similarity_threshold
//   6: int32  chunk_size
//   7: int32  chunk_overlap
// =============================================================================

struct ParsedRAGConfiguration {
    std::string embedding_model_path;
    std::string llm_model_path;
    int32_t embedding_dimension = 0;
    int32_t top_k = 0;
    float similarity_threshold = 0.0f;
    int32_t chunk_size = 0;
    int32_t chunk_overlap = 0;
};

bool decode_rag_configuration(const uint8_t* data, size_t len,
                              ParsedRAGConfiguration* out) {
    WireReader r(data, len);
    while (!r.eof()) {
        uint32_t field, wire_type;
        if (!r.read_tag(&field, &wire_type)) return false;
        switch (field) {
            case 1:
                if (wire_type != 2 || !r.read_string(&out->embedding_model_path)) return false;
                break;
            case 2:
                if (wire_type != 2 || !r.read_string(&out->llm_model_path)) return false;
                break;
            case 3:
                if (wire_type != 0 || !r.read_int32(&out->embedding_dimension)) return false;
                break;
            case 4:
                if (wire_type != 0 || !r.read_int32(&out->top_k)) return false;
                break;
            case 5:
                if (wire_type != 5 || !r.read_float(&out->similarity_threshold)) return false;
                break;
            case 6:
                if (wire_type != 0 || !r.read_int32(&out->chunk_size)) return false;
                break;
            case 7:
                if (wire_type != 0 || !r.read_int32(&out->chunk_overlap)) return false;
                break;
            default:
                if (!r.skip(wire_type)) return false;
                break;
        }
    }
    return true;
}

// =============================================================================
// RAGQueryOptions decode:
//   1: string question
//   2: optional string system_prompt
//   3: int32  max_tokens
//   4: float  temperature
//   5: float  top_p
//   6: int32  top_k
// =============================================================================

struct ParsedRAGQueryOptions {
    std::string question;
    std::string system_prompt;
    bool has_system_prompt = false;
    int32_t max_tokens = 0;
    float temperature = 0.0f;
    float top_p = 0.0f;
    int32_t top_k = 0;
};

bool decode_rag_query_options(const uint8_t* data, size_t len,
                              ParsedRAGQueryOptions* out) {
    WireReader r(data, len);
    while (!r.eof()) {
        uint32_t field, wire_type;
        if (!r.read_tag(&field, &wire_type)) return false;
        switch (field) {
            case 1:
                if (wire_type != 2 || !r.read_string(&out->question)) return false;
                break;
            case 2:
                if (wire_type != 2 || !r.read_string(&out->system_prompt)) return false;
                out->has_system_prompt = true;
                break;
            case 3:
                if (wire_type != 0 || !r.read_int32(&out->max_tokens)) return false;
                break;
            case 4:
                if (wire_type != 5 || !r.read_float(&out->temperature)) return false;
                break;
            case 5:
                if (wire_type != 5 || !r.read_float(&out->top_p)) return false;
                break;
            case 6:
                if (wire_type != 0 || !r.read_int32(&out->top_k)) return false;
                break;
            default:
                if (!r.skip(wire_type)) return false;
                break;
        }
    }
    return true;
}

// =============================================================================
// RAGSearchResult encode (nested in RAGResult.retrieved_chunks):
//   1: string chunk_id
//   2: string text
//   3: float  similarity_score
//   4: optional string source_document
//   5: map<string,string> metadata   (skipped — C ABI carries an opaque JSON blob)
// =============================================================================

void encode_rag_search_result(const rac_search_result_t& chunk,
                              std::vector<uint8_t>& out) {
    out.clear();
    if (chunk.chunk_id) wire_string_field(out, 1, chunk.chunk_id);
    if (chunk.text) wire_string_field(out, 2, chunk.text);
    wire_float_field(out, 3, chunk.similarity_score);
}

// =============================================================================
// RAGResult encode:
//   1: string answer
//   2: repeated RAGSearchResult retrieved_chunks
//   3: string context_used
//   4: int64  retrieval_time_ms
//   5: int64  generation_time_ms
//   6: int64  total_time_ms
// =============================================================================

void encode_rag_result(const rac_rag_result_t& res,
                       std::vector<uint8_t>& out) {
    if (res.answer) wire_string_field(out, 1, res.answer);

    for (size_t i = 0; i < res.num_chunks; ++i) {
        std::vector<uint8_t> chunk_bytes;
        encode_rag_search_result(res.retrieved_chunks[i], chunk_bytes);
        wire_submessage_field(out, 2, chunk_bytes);
    }

    if (res.context_used) wire_string_field(out, 3, res.context_used);

    wire_int64_field(out, 4, static_cast<int64_t>(res.retrieval_time_ms));
    wire_int64_field(out, 5, static_cast<int64_t>(res.generation_time_ms));
    wire_int64_field(out, 6, static_cast<int64_t>(res.total_time_ms));
}

// =============================================================================
// RAGStatistics encode:
//   1: int64  indexed_documents
//   2: int64  indexed_chunks
//   3: int64  total_tokens_indexed
//   4: int64  last_updated_ms
//   5: optional string index_path
// =============================================================================

void encode_rag_statistics(int64_t indexed_documents, int64_t indexed_chunks,
                           int64_t total_tokens_indexed, int64_t last_updated_ms,
                           const std::string& index_path,
                           std::vector<uint8_t>& out) {
    wire_int64_field(out, 1, indexed_documents);
    wire_int64_field(out, 2, indexed_chunks);
    wire_int64_field(out, 3, total_tokens_indexed);
    wire_int64_field(out, 4, last_updated_ms);
    if (!index_path.empty()) wire_string_field(out, 5, index_path);
}

// =============================================================================
// Pipeline state
// =============================================================================

std::mutex g_rag_mutex;
rac_rag_pipeline_t* g_rag_pipeline = nullptr;

jbyteArray make_jbytearray(JNIEnv* env, const std::vector<uint8_t>& bytes) {
    jbyteArray arr = env->NewByteArray(static_cast<jsize>(bytes.size()));
    if (!arr) return nullptr;
    if (!bytes.empty()) {
        env->SetByteArrayRegion(arr, 0, static_cast<jsize>(bytes.size()),
                                reinterpret_cast<const jbyte*>(bytes.data()));
    }
    return arr;
}

}  // namespace

extern "C" {

// =============================================================================
// racRagCreatePipeline(byte[] configBytes) -> int
// =============================================================================

JNIEXPORT jint JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRagCreatePipeline(
    JNIEnv* env, jclass clazz, jbyteArray configBytes) {
    (void)clazz;

    if (configBytes == nullptr) {
        LOGe("racRagCreatePipeline: null configBytes");
        return static_cast<jint>(RAC_ERROR_NULL_POINTER);
    }

    const jsize len = env->GetArrayLength(configBytes);
    jbyte* bytes = env->GetByteArrayElements(configBytes, nullptr);
    if (!bytes) {
        LOGe("racRagCreatePipeline: GetByteArrayElements failed");
        return static_cast<jint>(RAC_ERROR_OUT_OF_MEMORY);
    }

    ParsedRAGConfiguration parsed;
    const bool ok = decode_rag_configuration(reinterpret_cast<const uint8_t*>(bytes),
                                             static_cast<size_t>(len), &parsed);
    env->ReleaseByteArrayElements(configBytes, bytes, JNI_ABORT);

    if (!ok) {
        LOGe("racRagCreatePipeline: failed to decode RAGConfiguration (len=%d)",
             static_cast<int>(len));
        return static_cast<jint>(RAC_ERROR_DECODING_ERROR);
    }

    rac_rag_config_t c_cfg = rac_rag_config_default();
    c_cfg.embedding_model_path = parsed.embedding_model_path.c_str();
    c_cfg.llm_model_path =
        parsed.llm_model_path.empty() ? nullptr : parsed.llm_model_path.c_str();
    if (parsed.embedding_dimension > 0)
        c_cfg.embedding_dimension = static_cast<size_t>(parsed.embedding_dimension);
    if (parsed.top_k > 0) c_cfg.top_k = static_cast<size_t>(parsed.top_k);
    if (parsed.similarity_threshold > 0.0f)
        c_cfg.similarity_threshold = parsed.similarity_threshold;
    if (parsed.chunk_size > 0) c_cfg.chunk_size = static_cast<size_t>(parsed.chunk_size);
    if (parsed.chunk_overlap >= 0)
        c_cfg.chunk_overlap = static_cast<size_t>(parsed.chunk_overlap);

    LOGi("racRagCreatePipeline: emb=%s, llm=%s, dim=%zu, top_k=%zu, chunk=%zu/%zu, sim=%.3f",
         c_cfg.embedding_model_path ? c_cfg.embedding_model_path : "(null)",
         c_cfg.llm_model_path ? c_cfg.llm_model_path : "(null)",
         c_cfg.embedding_dimension, c_cfg.top_k, c_cfg.chunk_size, c_cfg.chunk_overlap,
         c_cfg.similarity_threshold);

    {
        const rac_result_t reg = rac_backend_rag_register();
        if (reg != RAC_SUCCESS && reg != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
            LOGw("racRagCreatePipeline: rac_backend_rag_register returned %d", reg);
        }
    }

    rac_rag_pipeline_t* pipeline = nullptr;
    const rac_result_t result = rac_rag_pipeline_create_standalone(&c_cfg, &pipeline);

    if (result != RAC_SUCCESS || !pipeline) {
        LOGe("racRagCreatePipeline: rac_rag_pipeline_create_standalone failed (rc=%d)", result);
        return static_cast<jint>(result != RAC_SUCCESS ? result : RAC_ERROR_PROCESSING_FAILED);
    }

    {
        std::lock_guard<std::mutex> lock(g_rag_mutex);
        if (g_rag_pipeline) {
            LOGw("racRagCreatePipeline: replacing existing pipeline (destroying old)");
            rac_rag_pipeline_destroy(g_rag_pipeline);
        }
        g_rag_pipeline = pipeline;
    }

    LOGi("racRagCreatePipeline: success, handle=%p", static_cast<void*>(pipeline));
    return static_cast<jint>(RAC_SUCCESS);
}

// =============================================================================
// racRagDestroyPipeline() -> int
// =============================================================================

JNIEXPORT jint JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRagDestroyPipeline(
    JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;

    rac_rag_pipeline_t* pipeline = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_rag_mutex);
        pipeline = g_rag_pipeline;
        g_rag_pipeline = nullptr;
    }

    if (pipeline) {
        LOGi("racRagDestroyPipeline: destroying handle=%p", static_cast<void*>(pipeline));
        rac_rag_pipeline_destroy(pipeline);
    }
    return static_cast<jint>(RAC_SUCCESS);
}

// =============================================================================
// racRagIngest(String text, String? metadataJson) -> int
// =============================================================================

JNIEXPORT jint JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRagIngest(
    JNIEnv* env, jclass clazz, jstring text, jstring metadataJson) {
    (void)clazz;

    rac_rag_pipeline_t* pipeline;
    {
        std::lock_guard<std::mutex> lock(g_rag_mutex);
        pipeline = g_rag_pipeline;
    }
    if (!pipeline) {
        LOGe("racRagIngest: pipeline not created");
        return static_cast<jint>(RAC_ERROR_INVALID_STATE);
    }
    if (!text) {
        LOGe("racRagIngest: text is required");
        return static_cast<jint>(RAC_ERROR_NULL_POINTER);
    }

    const char* text_utf = env->GetStringUTFChars(text, nullptr);
    const char* meta_utf = metadataJson ? env->GetStringUTFChars(metadataJson, nullptr) : nullptr;

    LOGi("racRagIngest: text_len=%zu, has_metadata=%d",
         text_utf ? std::strlen(text_utf) : 0, meta_utf ? 1 : 0);

    const rac_result_t result = rac_rag_add_document(pipeline, text_utf, meta_utf);

    if (text_utf) env->ReleaseStringUTFChars(text, text_utf);
    if (meta_utf) env->ReleaseStringUTFChars(metadataJson, meta_utf);

    if (result != RAC_SUCCESS) {
        LOGe("racRagIngest: rac_rag_add_document failed (rc=%d)", result);
    }
    return static_cast<jint>(result);
}

// =============================================================================
// racRagAddDocumentsBatch(String documentsJson) -> int
// =============================================================================

JNIEXPORT jint JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRagAddDocumentsBatch(
    JNIEnv* env, jclass clazz, jstring documentsJson) {
    (void)clazz;

    rac_rag_pipeline_t* pipeline;
    {
        std::lock_guard<std::mutex> lock(g_rag_mutex);
        pipeline = g_rag_pipeline;
    }
    if (!pipeline) {
        LOGe("racRagAddDocumentsBatch: pipeline not created");
        return static_cast<jint>(RAC_ERROR_INVALID_STATE);
    }
    if (!documentsJson) {
        LOGe("racRagAddDocumentsBatch: documentsJson is required");
        return static_cast<jint>(RAC_ERROR_NULL_POINTER);
    }

    const char* json_utf = env->GetStringUTFChars(documentsJson, nullptr);
    if (!json_utf) return static_cast<jint>(RAC_ERROR_OUT_OF_MEMORY);

    nlohmann::json arr;
    try {
        arr = nlohmann::json::parse(json_utf);
    } catch (const std::exception& e) {
        LOGe("racRagAddDocumentsBatch: JSON parse failed: %s", e.what());
        env->ReleaseStringUTFChars(documentsJson, json_utf);
        return static_cast<jint>(RAC_ERROR_DECODING_ERROR);
    }
    env->ReleaseStringUTFChars(documentsJson, json_utf);

    if (!arr.is_array()) {
        LOGe("racRagAddDocumentsBatch: JSON root is not an array");
        return static_cast<jint>(RAC_ERROR_INVALID_ARGUMENT);
    }

    const size_t count = arr.size();
    if (count == 0) return static_cast<jint>(RAC_SUCCESS);

    std::vector<std::string> texts;
    std::vector<std::string> metas;
    std::vector<bool> meta_present;
    texts.reserve(count);
    metas.reserve(count);
    meta_present.reserve(count);

    for (const auto& item : arr) {
        texts.push_back(item.value("text", std::string()));
        if (item.contains("metadata_json") && !item["metadata_json"].is_null()) {
            metas.push_back(item.value("metadata_json", std::string()));
            meta_present.push_back(true);
        } else {
            metas.emplace_back();
            meta_present.push_back(false);
        }
    }

    std::vector<const char*> doc_ptrs(count);
    std::vector<const char*> meta_ptrs(count);
    for (size_t i = 0; i < count; ++i) {
        doc_ptrs[i] = texts[i].c_str();
        meta_ptrs[i] = meta_present[i] ? metas[i].c_str() : nullptr;
    }

    LOGi("racRagAddDocumentsBatch: ingesting %zu document(s)", count);

    const rac_result_t result = rac_rag_add_documents_batch(
        pipeline, doc_ptrs.data(), meta_ptrs.data(), count);

    if (result != RAC_SUCCESS) {
        LOGe("racRagAddDocumentsBatch: rac_rag_add_documents_batch failed (rc=%d)", result);
    }
    return static_cast<jint>(result);
}

// =============================================================================
// racRagQuery(String question, byte[]? optionsBytes) -> byte[]?
// =============================================================================

JNIEXPORT jbyteArray JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRagQuery(
    JNIEnv* env, jclass clazz, jstring question, jbyteArray optionsBytes) {
    (void)clazz;

    rac_rag_pipeline_t* pipeline;
    {
        std::lock_guard<std::mutex> lock(g_rag_mutex);
        pipeline = g_rag_pipeline;
    }
    if (!pipeline) {
        LOGe("racRagQuery: pipeline not created");
        return nullptr;
    }
    if (!question) {
        LOGe("racRagQuery: question is required");
        return nullptr;
    }

    rac_rag_query_t query{};
    query.max_tokens = 512;
    query.temperature = 0.7f;
    query.top_p = 0.9f;
    query.top_k = 40;

    std::string question_storage;
    std::string sys_prompt_storage;
    bool has_sys_prompt = false;

    if (const char* q = env->GetStringUTFChars(question, nullptr)) {
        question_storage.assign(q);
        env->ReleaseStringUTFChars(question, q);
    }

    if (optionsBytes != nullptr) {
        const jsize olen = env->GetArrayLength(optionsBytes);
        jbyte* obytes = env->GetByteArrayElements(optionsBytes, nullptr);
        if (obytes) {
            ParsedRAGQueryOptions opts;
            const bool parsed = decode_rag_query_options(
                reinterpret_cast<const uint8_t*>(obytes),
                static_cast<size_t>(olen), &opts);
            env->ReleaseByteArrayElements(optionsBytes, obytes, JNI_ABORT);
            if (parsed) {
                if (!opts.question.empty()) question_storage = std::move(opts.question);
                if (opts.has_system_prompt) {
                    sys_prompt_storage = std::move(opts.system_prompt);
                    has_sys_prompt = true;
                }
                if (opts.max_tokens > 0) query.max_tokens = opts.max_tokens;
                if (opts.temperature > 0.0f) query.temperature = opts.temperature;
                if (opts.top_p > 0.0f) query.top_p = opts.top_p;
                if (opts.top_k > 0) query.top_k = opts.top_k;
            } else {
                LOGw("racRagQuery: failed to decode RAGQueryOptions, using defaults");
            }
        }
    }
    query.question = question_storage.c_str();
    query.system_prompt = has_sys_prompt ? sys_prompt_storage.c_str() : nullptr;

    LOGi("racRagQuery: question_len=%zu, max_tokens=%d, temp=%.2f",
         question_storage.size(), query.max_tokens, query.temperature);

    rac_rag_result_t c_result{};
    const rac_result_t status = rac_rag_query(pipeline, &query, &c_result);
    if (status != RAC_SUCCESS) {
        LOGe("racRagQuery: rac_rag_query failed (rc=%d)", status);
        rac_rag_result_free(&c_result);
        return nullptr;
    }

    std::vector<uint8_t> out_bytes;
    out_bytes.reserve(1024);
    encode_rag_result(c_result, out_bytes);

    LOGi("racRagQuery: success, answer_len=%zu, chunks=%zu, total_ms=%.0f",
         c_result.answer ? std::strlen(c_result.answer) : 0,
         c_result.num_chunks, c_result.total_time_ms);

    rac_rag_result_free(&c_result);

    return make_jbytearray(env, out_bytes);
}

// =============================================================================
// racRagClearDocuments() -> int
// =============================================================================

JNIEXPORT jint JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRagClearDocuments(
    JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;

    rac_rag_pipeline_t* pipeline;
    {
        std::lock_guard<std::mutex> lock(g_rag_mutex);
        pipeline = g_rag_pipeline;
    }
    if (!pipeline) {
        LOGe("racRagClearDocuments: pipeline not created");
        return static_cast<jint>(RAC_ERROR_INVALID_STATE);
    }

    const rac_result_t result = rac_rag_clear_documents(pipeline);
    if (result != RAC_SUCCESS) {
        LOGe("racRagClearDocuments: rac_rag_clear_documents failed (rc=%d)", result);
    }
    return static_cast<jint>(result);
}

// =============================================================================
// racRagGetDocumentCount() -> int
// =============================================================================

JNIEXPORT jint JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRagGetDocumentCount(
    JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;

    rac_rag_pipeline_t* pipeline;
    {
        std::lock_guard<std::mutex> lock(g_rag_mutex);
        pipeline = g_rag_pipeline;
    }
    if (!pipeline) return 0;
    return static_cast<jint>(rac_rag_get_document_count(pipeline));
}

// =============================================================================
// racRagGetStatistics() -> byte[]?
// =============================================================================

JNIEXPORT jbyteArray JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRagGetStatistics(
    JNIEnv* env, jclass clazz) {
    (void)clazz;

    rac_rag_pipeline_t* pipeline;
    {
        std::lock_guard<std::mutex> lock(g_rag_mutex);
        pipeline = g_rag_pipeline;
    }
    if (!pipeline) {
        LOGe("racRagGetStatistics: pipeline not created");
        return nullptr;
    }

    char* stats_json = nullptr;
    const rac_result_t status = rac_rag_get_statistics(pipeline, &stats_json);
    if (status != RAC_SUCCESS || !stats_json) {
        LOGe("racRagGetStatistics: rac_rag_get_statistics failed (rc=%d)", status);
        if (stats_json) rac_free(stats_json);
        return nullptr;
    }

    int64_t indexed_documents = 0;
    int64_t indexed_chunks = 0;
    int64_t total_tokens_indexed = 0;
    int64_t last_updated_ms = 0;
    std::string index_path;

    try {
        nlohmann::json j = nlohmann::json::parse(stats_json);
        if (j.contains("indexed_documents") && j["indexed_documents"].is_number())
            indexed_documents = j["indexed_documents"].get<int64_t>();
        if (j.contains("indexed_chunks") && j["indexed_chunks"].is_number())
            indexed_chunks = j["indexed_chunks"].get<int64_t>();
        if (j.contains("total_tokens_indexed") && j["total_tokens_indexed"].is_number())
            total_tokens_indexed = j["total_tokens_indexed"].get<int64_t>();
        if (j.contains("last_updated_ms") && j["last_updated_ms"].is_number())
            last_updated_ms = j["last_updated_ms"].get<int64_t>();
        if (j.contains("index_path") && j["index_path"].is_string())
            index_path = j["index_path"].get<std::string>();
    } catch (const std::exception& e) {
        LOGw("racRagGetStatistics: JSON parse failed: %s (returning empty stats)", e.what());
    }
    rac_free(stats_json);

    std::vector<uint8_t> out_bytes;
    encode_rag_statistics(indexed_documents, indexed_chunks, total_tokens_indexed,
                          last_updated_ms, index_path, out_bytes);
    return make_jbytearray(env, out_bytes);
}

}  // extern "C"
