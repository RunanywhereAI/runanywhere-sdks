// lora_bridge.cpp — LoRA adapters over the lifecycle proto ABI.
//
// The component-handle entry points (rac_llm_component_load_lora and friends)
// became unreachable when language models moved into commons' lifecycle store
// in F4, because there is no component handle any more. These are the
// replacement: they act on whatever model the lifecycle load made resident.

#include "lora_bridge.h"

#include "proto_bridge.h"

#include "rac/features/lora/rac_lora_service.h"

namespace rac_electron {
namespace {

Napi::Value LoraApply(const Napi::CallbackInfo& info) {
    return RunProtoUnary(info.Env(), "lora_apply", rac_lora_apply_proto,
                         RequireProtoBytes(info, 0, "loraApplyProto(requestBytes)"));
}

Napi::Value LoraRemove(const Napi::CallbackInfo& info) {
    return RunProtoUnary(info.Env(), "lora_remove", rac_lora_remove_proto,
                         RequireProtoBytes(info, 0, "loraRemoveProto(requestBytes)"));
}

// list and state both take a LoraState request and answer with one; commons
// reads the base model from the lifecycle store rather than from the argument.
Napi::Value LoraList(const Napi::CallbackInfo& info) {
    return RunProtoUnary(info.Env(), "lora_list", rac_lora_list_proto,
                         RequireProtoBytes(info, 0, "loraListProto(stateBytes)"));
}

Napi::Value LoraState(const Napi::CallbackInfo& info) {
    return RunProtoUnary(info.Env(), "lora_state", rac_lora_state_proto,
                         RequireProtoBytes(info, 0, "loraStateProto(stateBytes)"));
}

}  // namespace

void RegisterLoraBridge(Napi::Env env, Napi::Object exports) {
    exports.Set("loraApplyProto", Napi::Function::New(env, LoraApply));
    exports.Set("loraRemoveProto", Napi::Function::New(env, LoraRemove));
    exports.Set("loraListProto", Napi::Function::New(env, LoraList));
    exports.Set("loraStateProto", Napi::Function::New(env, LoraState));
}

}  // namespace rac_electron
