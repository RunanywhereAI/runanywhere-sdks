// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "voice_agent_solution.h"

#include <memory>

namespace ra::solutions {

std::unique_ptr<ra::core::VoiceAgentPipeline> build_voice_agent_pipeline(
    const ra::core::VoiceAgentConfig& cfg,
    ra::core::PluginRegistry&         registry,
    ra::core::EngineRouter&           router) {
    return std::make_unique<ra::core::VoiceAgentPipeline>(cfg, registry, router);
}

}  // namespace ra::solutions
