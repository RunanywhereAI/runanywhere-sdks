// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "server_session_registry.h"

namespace ra::solutions::openai {

ServerSessionRegistry& ServerSessionRegistry::instance() {
    static ServerSessionRegistry inst;
    return inst;
}

void ServerSessionRegistry::set(const std::string& model_id, ra_llm_session_t* session) {
    std::lock_guard lk(mu_);
    if (session) {
        sessions_[model_id] = session;
        if (default_.empty()) default_ = model_id;
    } else {
        sessions_.erase(model_id);
        if (default_ == model_id) default_.clear();
    }
}

ra_llm_session_t* ServerSessionRegistry::get(const std::string& model_id) const {
    std::lock_guard lk(mu_);
    if (!model_id.empty()) {
        auto it = sessions_.find(model_id);
        if (it != sessions_.end()) return it->second;
    }
    if (!default_.empty()) {
        auto it = sessions_.find(default_);
        if (it != sessions_.end()) return it->second;
    }
    return nullptr;
}

std::vector<std::string> ServerSessionRegistry::list() const {
    std::lock_guard lk(mu_);
    std::vector<std::string> out;
    out.reserve(sessions_.size());
    for (const auto& [k, _] : sessions_) out.push_back(k);
    return out;
}

void ServerSessionRegistry::set_default(const std::string& model_id) {
    std::lock_guard lk(mu_);
    default_ = model_id;
}

std::string ServerSessionRegistry::default_model() const {
    std::lock_guard lk(mu_);
    return default_;
}

void ServerSessionRegistry::clear() {
    std::lock_guard lk(mu_);
    sessions_.clear();
    default_.clear();
}

}  // namespace ra::solutions::openai
