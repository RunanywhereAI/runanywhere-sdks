// vlm_bridge.cpp — the vision half of the proto ABI.
//
// Same shape as llm_bridge.cpp: handle-free entry points reading the model
// rac_model_lifecycle_load_proto put in commons' own store, with the image
// travelling inside the request as a VLMImage rather than through a bespoke
// N-API object.

#include "vlm_bridge.h"

#include "proto_bridge.h"

#include <memory>
#include <vector>

#include "rac/features/vlm/rac_vlm_service.h"

namespace rac_electron {
namespace {

// rac_vlm_stream_event_proto_callback_fn returns rac_bool_t ("keep going"),
// while the shared streaming helper speaks the void-returning proto callback.
// This pairing adapts one to the other for the duration of a single stream.
struct StreamAdapter {
    rac_proto_bytes_callback_fn forward;
    void* user_data;
};

rac_bool_t ForwardVlmEvent(const uint8_t* bytes, size_t size, void* user_data) {
    auto* adapter = static_cast<StreamAdapter*>(user_data);
    if (adapter != nullptr && adapter->forward != nullptr)
        adapter->forward(bytes, size, adapter->user_data);
    return RAC_TRUE;
}

Napi::Value VlmGenerate(const Napi::CallbackInfo& info) {
    return RunProtoUnary(info.Env(), "vlm_generate", rac_vlm_generate_proto,
                         RequireProtoBytes(info, 0, "vlmGenerateProto(requestBytes)"));
}

// vlmStreamProto(requestBytes, onEvent) -> Promise<void>. One VLMStreamEvent
// per callback, terminating on COMPLETED or ERROR.
Napi::Value VlmStream(const Napi::CallbackInfo& info) {
    auto request = std::make_shared<std::vector<uint8_t>>(
        RequireProtoBytes(info, 0, "vlmStreamProto(requestBytes, onEvent)"));
    if (info.Length() < 2 || !info[1].IsFunction()) {
        throw Napi::TypeError::New(info.Env(),
                                   "vlmStreamProto(requestBytes, onEvent) expects a callback");
    }
    return RunProtoStream(
        info.Env(), "vlm_stream",
        [request](rac_proto_bytes_callback_fn callback, void* user_data) {
            StreamAdapter adapter{callback, user_data};
            const rac_result_t rc = rac_vlm_stream_proto(request->data(), request->size(),
                                                         ForwardVlmEvent, &adapter);
            // The adapter lives on this frame and the dispatcher may still be
            // inside a callback when the call returns, so wait it out here.
            rac_vlm_proto_quiesce();
            return rc;
        },
        info[1].As<Napi::Function>(), nullptr);
}

Napi::Value VlmCancel(const Napi::CallbackInfo& info) {
    return RunProtoCall(info.Env(), "vlm_cancel", [](rac_proto_buffer_t* out) {
        return rac_vlm_cancel_lifecycle_proto(out);
    });
}

}  // namespace

void RegisterVlmBridge(Napi::Env env, Napi::Object exports) {
    exports.Set("vlmGenerateProto", Napi::Function::New(env, VlmGenerate));
    exports.Set("vlmStreamProto", Napi::Function::New(env, VlmStream));
    exports.Set("vlmCancelProto", Napi::Function::New(env, VlmCancel));
}

}  // namespace rac_electron
