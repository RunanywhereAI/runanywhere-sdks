#include "model_bridge.h"

#include "proto_bridge.h"

#include <functional>
#include <memory>
#include <string>
#include <vector>

#include "rac/core/rac_core.h"
#include "rac/core/rac_model_lifecycle.h"
#include "rac/infrastructure/model_management/rac_model_compatibility.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

namespace rac_electron {
namespace {

rac_result_t WithRegistry(rac_proto_buffer_t* out,
                          const std::function<rac_result_t(rac_model_registry_handle_t)>& body) {
    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (registry == nullptr) {
        return rac_proto_buffer_set_error(out, RAC_ERROR_NOT_INITIALIZED,
                                          "global model registry is unavailable");
    }
    return body(registry);
}

std::string RequireModelId(const Napi::CallbackInfo& info, const char* signature) {
    if (info.Length() < 1 || !info[0].IsString()) {
        throw Napi::TypeError::New(info.Env(), std::string(signature) + " expects a model id");
    }
    return info[0].As<Napi::String>().Utf8Value();
}

Napi::Value ModelLoad(const Napi::CallbackInfo& info) {
    auto request = std::make_shared<std::vector<uint8_t>>(
        RequireProtoBytes(info, 0, "modelLoad(requestBytes)"));
    return RunProtoCall(info.Env(), "model_lifecycle_load", [request](rac_proto_buffer_t* out) {
        return WithRegistry(out, [&](rac_model_registry_handle_t registry) {
            return rac_model_lifecycle_load_proto(registry, request->data(), request->size(), out);
        });
    });
}

Napi::Value ModelResolvePaths(const Napi::CallbackInfo& info) {
    auto request = std::make_shared<std::vector<uint8_t>>(
        RequireProtoBytes(info, 0, "modelResolvePaths(requestBytes)"));
    return RunProtoCall(info.Env(), "model_lifecycle_resolve_paths",
                        [request](rac_proto_buffer_t* out) {
                            return WithRegistry(out, [&](rac_model_registry_handle_t registry) {
                                return rac_model_lifecycle_resolve_paths_proto(
                                    registry, request->data(), request->size(), out);
                            });
                        });
}

Napi::Value ModelUnload(const Napi::CallbackInfo& info) {
    return RunProtoUnary(info.Env(), "model_lifecycle_unload", rac_model_lifecycle_unload_proto,
                         RequireProtoBytes(info, 0, "modelUnload(requestBytes)"));
}

Napi::Value ModelCurrent(const Napi::CallbackInfo& info) {
    return RunProtoUnary(info.Env(), "model_lifecycle_current_model",
                         rac_model_lifecycle_current_model_proto,
                         RequireProtoBytes(info, 0, "modelCurrent(requestBytes)"));
}

Napi::Value ModelComponentSnapshot(const Napi::CallbackInfo& info) {
    if (info.Length() < 1 || !info[0].IsNumber()) {
        throw Napi::TypeError::New(info.Env(),
                                   "modelComponentSnapshot(component) expects a number");
    }
    const uint32_t component = info[0].As<Napi::Number>().Uint32Value();
    return RunProtoCall(info.Env(), "component_lifecycle_snapshot",
                        [component](rac_proto_buffer_t* out) {
                            return rac_component_lifecycle_snapshot_proto(component, out);
                        });
}

Napi::Value ModelLifecycleReset(const Napi::CallbackInfo& info) {
    rac_model_lifecycle_reset();
    return info.Env().Undefined();
}

Napi::Value RegistryRegister(const Napi::CallbackInfo& info) {
    auto model = std::make_shared<std::vector<uint8_t>>(
        RequireProtoBytes(info, 0, "modelRegistryRegister(modelInfoBytes)"));
    return RunProtoCall(info.Env(), "model_registry_register", [model](rac_proto_buffer_t* out) {
        return WithRegistry(out, [&](rac_model_registry_handle_t registry) {
            return rac_model_registry_register_proto_buffer(registry, model->data(), model->size(),
                                                            out);
        });
    });
}

Napi::Value RegistryUpdate(const Napi::CallbackInfo& info) {
    auto model = std::make_shared<std::vector<uint8_t>>(
        RequireProtoBytes(info, 0, "modelRegistryUpdate(modelInfoBytes)"));
    return RunProtoCall(info.Env(), "model_registry_update", [model](rac_proto_buffer_t* out) {
        return WithRegistry(out, [&](rac_model_registry_handle_t registry) {
            return rac_model_registry_update_proto_buffer(registry, model->data(), model->size(),
                                                          out);
        });
    });
}

Napi::Value RegistryGet(const Napi::CallbackInfo& info) {
    auto request = std::make_shared<std::vector<uint8_t>>(
        RequireProtoBytes(info, 0, "modelRegistryGet(requestBytes)"));
    return RunProtoCall(info.Env(), "model_registry_get", [request](rac_proto_buffer_t* out) {
        return WithRegistry(out, [&](rac_model_registry_handle_t registry) {
            return rac_model_registry_get_model_proto(registry, request->data(), request->size(),
                                                      out);
        });
    });
}

Napi::Value RegistryList(const Napi::CallbackInfo& info) {
    auto request = std::make_shared<std::vector<uint8_t>>(
        RequireProtoBytes(info, 0, "modelRegistryList(requestBytes)"));
    return RunProtoCall(info.Env(), "model_registry_list", [request](rac_proto_buffer_t* out) {
        return WithRegistry(out, [&](rac_model_registry_handle_t registry) {
            return rac_model_registry_list_models_proto(registry, request->data(), request->size(),
                                                        out);
        });
    });
}

Napi::Value RegistryRemove(const Napi::CallbackInfo& info) {
    const std::string model_id = RequireModelId(info, "modelRegistryRemove(modelId)");
    return RunProtoCall(info.Env(), "model_registry_remove", [model_id](rac_proto_buffer_t* out) {
        return WithRegistry(out, [&](rac_model_registry_handle_t registry) {
            return rac_model_registry_remove_proto_buffer(registry, model_id.c_str(), out);
        });
    });
}

Napi::Value RegistryRefresh(const Napi::CallbackInfo& info) {
    auto request = std::make_shared<std::vector<uint8_t>>(
        RequireProtoBytes(info, 0, "modelRegistryRefresh(requestBytes)"));
    return RunProtoCall(info.Env(), "model_registry_refresh", [request](rac_proto_buffer_t* out) {
        return WithRegistry(out, [&](rac_model_registry_handle_t registry) {
            return rac_model_registry_refresh_proto(registry, request->data(), request->size(),
                                                    out);
        });
    });
}

Napi::Value RegistryDiscover(const Napi::CallbackInfo& info) {
    auto request = std::make_shared<std::vector<uint8_t>>(
        RequireProtoBytes(info, 0, "modelRegistryDiscover(requestBytes)"));
    return RunProtoCall(info.Env(), "model_registry_discover", [request](rac_proto_buffer_t* out) {
        return WithRegistry(out, [&](rac_model_registry_handle_t registry) {
            return rac_model_registry_discover_proto(registry, request->data(), request->size(),
                                                     out);
        });
    });
}

Napi::Value RegistryImport(const Napi::CallbackInfo& info) {
    auto request = std::make_shared<std::vector<uint8_t>>(
        RequireProtoBytes(info, 0, "modelRegistryImport(requestBytes)"));
    return RunProtoCall(info.Env(), "model_registry_import", [request](rac_proto_buffer_t* out) {
        return WithRegistry(out, [&](rac_model_registry_handle_t registry) {
            return rac_model_registry_import_proto(registry, request->data(), request->size(), out);
        });
    });
}

// Commons owns the verdict: the caller supplies the device's free RAM and disk,
// commons reads the model's requirements out of the registry and answers
// canRun / canFit. The residency policy in TypeScript asks this before a load.
Napi::Value ModelCompatibility(const Napi::CallbackInfo& info) {
    return RunProtoUnary(info.Env(), "model_compatibility_check",
                         rac_model_compatibility_check_proto,
                         RequireProtoBytes(info, 0, "modelCompatibility(requestBytes)"));
}

Napi::Value RegisterFromUrl(const Napi::CallbackInfo& info) {
    return RunProtoUnary(info.Env(), "register_model_from_url", rac_register_model_from_url_proto,
                         RequireProtoBytes(info, 0, "modelRegisterFromUrl(requestBytes)"));
}

Napi::Value RegisterMultiFile(const Napi::CallbackInfo& info) {
    return RunProtoUnary(info.Env(), "register_multi_file_model",
                         rac_register_multi_file_model_proto,
                         RequireProtoBytes(info, 0, "modelRegisterMultiFile(requestBytes)"));
}

}  // namespace

void RegisterModelBridge(Napi::Env env, Napi::Object exports) {
    exports.Set("modelLoad", Napi::Function::New(env, ModelLoad));
    exports.Set("modelResolvePaths", Napi::Function::New(env, ModelResolvePaths));
    exports.Set("modelUnload", Napi::Function::New(env, ModelUnload));
    exports.Set("modelCurrent", Napi::Function::New(env, ModelCurrent));
    exports.Set("modelComponentSnapshot", Napi::Function::New(env, ModelComponentSnapshot));
    exports.Set("modelLifecycleReset", Napi::Function::New(env, ModelLifecycleReset));
    exports.Set("modelRegistryRegister", Napi::Function::New(env, RegistryRegister));
    exports.Set("modelRegistryUpdate", Napi::Function::New(env, RegistryUpdate));
    exports.Set("modelRegistryGet", Napi::Function::New(env, RegistryGet));
    exports.Set("modelRegistryList", Napi::Function::New(env, RegistryList));
    exports.Set("modelRegistryRemove", Napi::Function::New(env, RegistryRemove));
    exports.Set("modelRegistryRefresh", Napi::Function::New(env, RegistryRefresh));
    exports.Set("modelRegistryDiscover", Napi::Function::New(env, RegistryDiscover));
    exports.Set("modelRegistryImport", Napi::Function::New(env, RegistryImport));
    exports.Set("modelCompatibility", Napi::Function::New(env, ModelCompatibility));
    exports.Set("modelRegisterFromUrl", Napi::Function::New(env, RegisterFromUrl));
    exports.Set("modelRegisterMultiFile", Napi::Function::New(env, RegisterMultiFile));
}

}  // namespace rac_electron
