// llm_bridge.cpp — the LLM half of the proto ABI.
//
// Every entry point here reads the model that rac_model_lifecycle_load_proto
// put in commons' own store, which is why none of them takes a handle. Thinking
// splits, token accounting, finish reasons, and structured-JSON extraction
// arrive already normalized in the result, so nothing on the TypeScript side
// re-derives them.

#include "llm_bridge.h"

#include "proto_bridge.h"

#include <memory>
#include <vector>

#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/llm/rac_llm_stream.h"
#include "rac/features/llm/rac_llm_structured_output.h"

namespace rac_electron {
namespace {

Napi::Value LlmGenerate(const Napi::CallbackInfo& info) {
    return RunProtoUnary(info.Env(), "llm_generate", rac_llm_generate_proto,
                         RequireProtoBytes(info, 0, "llmGenerateProto(requestBytes)"));
}

// llmGenerateStreamProto(requestBytes, onEvent) -> Promise<void>. One
// LLMStreamEvent per callback, terminating on the event carrying the result.
Napi::Value LlmGenerateStream(const Napi::CallbackInfo& info) {
    auto request = std::make_shared<std::vector<uint8_t>>(
        RequireProtoBytes(info, 0, "llmGenerateStreamProto(requestBytes, onEvent)"));
    if (info.Length() < 2 || !info[1].IsFunction()) {
        throw Napi::TypeError::New(
            info.Env(), "llmGenerateStreamProto(requestBytes, onEvent) expects a callback");
    }
    return RunProtoStream(
        info.Env(), "llm_generate_stream",
        [request](rac_proto_bytes_callback_fn callback, void* user_data) {
            const rac_result_t rc = rac_llm_generate_stream_proto(
                request->data(), request->size(), callback, user_data);
            // The dispatcher may still be inside a callback when this returns,
            // and the session owning user_data is torn down the moment we do.
            rac_llm_proto_quiesce();
            return rc;
        },
        info[1].As<Napi::Function>(), nullptr);
}

Napi::Value LlmCancel(const Napi::CallbackInfo& info) {
    return RunProtoCall(info.Env(), "llm_cancel",
                        [](rac_proto_buffer_t* out) { return rac_llm_cancel_proto(out); });
}

Napi::Value StructuredGenerate(const Napi::CallbackInfo& info) {
    return RunProtoUnary(info.Env(), "structured_output_generate",
                         rac_structured_output_generate_proto,
                         RequireProtoBytes(info, 0, "structuredGenerate(requestBytes)"));
}

Napi::Value StructuredParse(const Napi::CallbackInfo& info) {
    return RunProtoUnary(info.Env(), "structured_output_parse", rac_structured_output_parse_proto,
                         RequireProtoBytes(info, 0, "structuredParse(requestBytes)"));
}

Napi::Value StructuredValidate(const Napi::CallbackInfo& info) {
    return RunProtoUnary(info.Env(), "structured_output_validate",
                         rac_structured_output_validate_proto,
                         RequireProtoBytes(info, 0, "structuredValidate(requestBytes)"));
}

}  // namespace

void RegisterLlmBridge(Napi::Env env, Napi::Object exports) {
    exports.Set("llmGenerateProto", Napi::Function::New(env, LlmGenerate));
    exports.Set("llmGenerateStreamProto", Napi::Function::New(env, LlmGenerateStream));
    exports.Set("llmCancelProto", Napi::Function::New(env, LlmCancel));
    exports.Set("structuredGenerate", Napi::Function::New(env, StructuredGenerate));
    exports.Set("structuredParse", Napi::Function::New(env, StructuredParse));
    exports.Set("structuredValidate", Napi::Function::New(env, StructuredValidate));
}

}  // namespace rac_electron
