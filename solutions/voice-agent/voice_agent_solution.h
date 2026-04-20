// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// L5 VoiceAgent solution — takes a VoiceAgentConfig (proto3) and produces a
// runtime pipeline. This is the ergonomic sugar over the L4 voice_pipeline.

#ifndef RA_SOLUTIONS_VOICE_AGENT_H
#define RA_SOLUTIONS_VOICE_AGENT_H

#include <memory>

#include "voice_pipeline.h"

namespace ra::solutions {

std::unique_ptr<ra::core::VoiceAgentPipeline> build_voice_agent_pipeline(
    const ra::core::VoiceAgentConfig& cfg,
    ra::core::PluginRegistry&         registry,
    ra::core::EngineRouter&           router);

}  // namespace ra::solutions

#endif  // RA_SOLUTIONS_VOICE_AGENT_H
