// data_bridge.cpp — embeddings, rerank, diarization, and segmentation over the
// proto ABI.
//
// Three of the four are lifecycle-owned and handle-free like the rest of the
// migrated surface. Rerank is the exception: commons exposes only
// rac_rerank_component_rerank_proto, which takes the component handle, so the
// handle is threaded in from the TypeScript side that owns the slot.

#include "data_bridge.h"

#include "proto_bridge.h"

#include <cstdint>

#include "rac/features/diarization/rac_diarization_service.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/rerank/rac_rerank_component.h"
#include "rac/features/segmentation/rac_segmentation_service.h"

namespace rac_electron {
namespace {

Napi::Value EmbedBatch(const Napi::CallbackInfo& info) {
    return RunProtoUnary(info.Env(), "embeddings_embed_batch",
                         rac_embeddings_embed_batch_lifecycle_proto,
                         RequireProtoBytes(info, 0, "embedBatchProto(requestBytes)"));
}

Napi::Value Rerank(const Napi::CallbackInfo& info) {
    if (info.Length() < 1 || !info[0].IsNumber()) {
        throw Napi::TypeError::New(info.Env(),
                                   "rerankProto(handle, requestBytes) expects a handle");
    }
    const auto handle = reinterpret_cast<rac_handle_t>(
        static_cast<intptr_t>(info[0].As<Napi::Number>().Int64Value()));
    return RunProtoOnHandle(info.Env(), "rerank", rac_rerank_component_rerank_proto, handle,
                            RequireProtoBytes(info, 1, "rerankProto(handle, requestBytes)"),
                            nullptr);
}

Napi::Value Diarize(const Napi::CallbackInfo& info) {
    return RunProtoUnary(info.Env(), "diarization_diarize",
                         rac_diarization_diarize_lifecycle_proto,
                         RequireProtoBytes(info, 0, "diarizeProto(requestBytes)"));
}

Napi::Value Segment(const Napi::CallbackInfo& info) {
    return RunProtoUnary(info.Env(), "segmentation_segment",
                         rac_segmentation_segment_lifecycle_proto,
                         RequireProtoBytes(info, 0, "segmentProto(requestBytes)"));
}

}  // namespace

void RegisterDataBridge(Napi::Env env, Napi::Object exports) {
    exports.Set("embedBatchProto", Napi::Function::New(env, EmbedBatch));
    exports.Set("rerankProto", Napi::Function::New(env, Rerank));
    exports.Set("diarizeProto", Napi::Function::New(env, Diarize));
    exports.Set("segmentProto", Napi::Function::New(env, Segment));
}

}  // namespace rac_electron
