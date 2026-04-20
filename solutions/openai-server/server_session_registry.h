// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Tiny in-process registry that maps a model id to a live
// `ra_llm_session_t*`. Used by the OpenAI handler to route requests to
// the right LLM session without forcing the host to pre-load sessions
// through the SDK-layer SessionRegistry (which is Swift/Kotlin-specific).
//
// The registry does NOT own the sessions — the caller (a standalone
// host binary like `runanywhere-server` or the Swift/Kotlin bridge)
// creates + destroys sessions. The registry is purely a name lookup so
// OpenAI's `"model": "..."` field resolves to a session handle.

#ifndef RA_SERVER_SESSION_REGISTRY_H
#define RA_SERVER_SESSION_REGISTRY_H

#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "ra_primitives.h"

namespace ra::solutions::openai {

class ServerSessionRegistry {
public:
    static ServerSessionRegistry& instance();

    // Registers (or replaces) a session under `model_id`. Non-owning.
    void set(const std::string& model_id, ra_llm_session_t* session);

    // Looks up `model_id`. Falls back to the `default_model` when the
    // explicit id is empty or unknown and a default is set.
    ra_llm_session_t* get(const std::string& model_id) const;

    // Lists registered model ids for the `/v1/models` response.
    std::vector<std::string> list() const;

    // Designates the default model for requests that omit `"model"`.
    void set_default(const std::string& model_id);
    std::string default_model() const;

    void clear();

private:
    ServerSessionRegistry() = default;
    mutable std::mutex mu_;
    std::unordered_map<std::string, ra_llm_session_t*> sessions_;
    std::string default_;
};

}  // namespace ra::solutions::openai

#endif  // RA_SERVER_SESSION_REGISTRY_H
