// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// JSI ↔ C ABI bridge backing the @runanywhere/core Nitro TurboModule.
// Each method maps 1:1 to a `ra_*` C ABI function. Returns jsi::Value
// for scalars; Promises are dispatched via Nitro's async helper.
//
// This file targets React Native New Architecture (Nitro >= 0.25) and
// compiles under both iOS (Objective-C++) and Android (NDK C++).

#include <NitroModules/HybridObject.hpp>

#include "ra_auth.h"
#include "ra_core_init.h"
#include "ra_model.h"
#include "ra_primitives.h"
#include "ra_rag.h"
#include "ra_state.h"
#include "ra_telemetry.h"

#include <cstdint>
#include <string>

namespace runanywhere::rn {

using namespace margelo::nitro;

class RunAnywhereTurboModule : public HybridObject {
public:
    RunAnywhereTurboModule() : HybridObject("RunAnywhere") {}

    // Lifecycle ----------------------------------------------------------

    void initialize(const std::string& apiKey, const std::string& baseUrl,
                    int32_t environment) {
        ra_state_initialize(
            static_cast<ra_environment_t>(environment),
            apiKey.c_str(),
            baseUrl.empty() ? nullptr : baseUrl.c_str(),
            nullptr);
    }

    void shutdown() { ra_state_shutdown(); }

    bool isInitialized() { return ra_state_is_initialized(); }

    // LLM ----------------------------------------------------------------

    int64_t llmCreate(const std::string& modelId, const std::string& modelPath,
                       int32_t format) {
        ra_model_spec_t spec{};
        spec.model_id   = modelId.c_str();
        spec.model_path = modelPath.c_str();
        spec.format     = static_cast<ra_model_format_t>(format);
        ra_llm_session_t* session = nullptr;
        if (ra_llm_create(&spec, nullptr, &session) != RA_OK) return 0;
        return reinterpret_cast<int64_t>(session);
    }

    void llmDestroy(int64_t handle) {
        ra_llm_destroy(reinterpret_cast<ra_llm_session_t*>(handle));
    }

    void llmCancel(int64_t handle) {
        ra_llm_cancel(reinterpret_cast<ra_llm_session_t*>(handle));
    }

    // Auth ---------------------------------------------------------------

    bool authIsAuthenticated() { return ra_auth_is_authenticated() != 0; }

    std::string authGetAccessToken() {
        const char* s = ra_auth_get_access_token();
        return s ? std::string{s} : std::string{};
    }

    int32_t authHandleAuthenticateResponse(const std::string& body) {
        return ra_auth_handle_authenticate_response(body.c_str());
    }

    // Telemetry ----------------------------------------------------------

    int32_t telemetryTrack(const std::string& name, const std::string& propsJson) {
        return ra_telemetry_track(name.c_str(), propsJson.c_str());
    }

    // RAG ----------------------------------------------------------------

    int64_t ragStoreCreate(int32_t dim) {
        ra_rag_vector_store_t* s = nullptr;
        if (ra_rag_store_create(dim, &s) != RA_OK) return 0;
        return reinterpret_cast<int64_t>(s);
    }

    void ragStoreDestroy(int64_t handle) {
        ra_rag_store_destroy(reinterpret_cast<ra_rag_vector_store_t*>(handle));
    }

    int32_t abiVersion() {
        return ra_abi_version();
    }

    std::string buildInfo() {
        const char* s = ra_build_info();
        return s ? std::string{s} : std::string{};
    }

    void loadHybridMethods() override {
        HybridObject::loadHybridMethods();
        registerHybrids(this, [](Prototype& p) {
            p.registerHybridMethod("initialize",        &RunAnywhereTurboModule::initialize);
            p.registerHybridMethod("shutdown",          &RunAnywhereTurboModule::shutdown);
            p.registerHybridMethod("isInitialized",     &RunAnywhereTurboModule::isInitialized);
            p.registerHybridMethod("llmCreate",         &RunAnywhereTurboModule::llmCreate);
            p.registerHybridMethod("llmDestroy",        &RunAnywhereTurboModule::llmDestroy);
            p.registerHybridMethod("llmCancel",         &RunAnywhereTurboModule::llmCancel);
            p.registerHybridMethod("authIsAuthenticated", &RunAnywhereTurboModule::authIsAuthenticated);
            p.registerHybridMethod("authGetAccessToken",  &RunAnywhereTurboModule::authGetAccessToken);
            p.registerHybridMethod("authHandleAuthenticateResponse",
                                    &RunAnywhereTurboModule::authHandleAuthenticateResponse);
            p.registerHybridMethod("telemetryTrack",    &RunAnywhereTurboModule::telemetryTrack);
            p.registerHybridMethod("ragStoreCreate",    &RunAnywhereTurboModule::ragStoreCreate);
            p.registerHybridMethod("ragStoreDestroy",   &RunAnywhereTurboModule::ragStoreDestroy);
            p.registerHybridMethod("abiVersion",        &RunAnywhereTurboModule::abiVersion);
            p.registerHybridMethod("buildInfo",         &RunAnywhereTurboModule::buildInfo);
        });
    }
};

}  // namespace runanywhere::rn
