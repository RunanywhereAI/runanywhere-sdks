// SPDX-License-Identifier: Apache-2.0
//
// rac/solutions/solution_converter.hpp — T4.7 SolutionConfig → PipelineSpec
//
// `solutions.proto` declares ergonomic sugar (VoiceAgentConfig, RAGConfig,
// …) on top of PipelineSpec. This translation layer is the single place
// that knows how to expand each oneof arm into its canonical DAG. Every
// SDK front-end funnels through this mapping, guaranteeing the same
// pipeline topology regardless of which language's helper API was used.
//
// Keeping the converter header-free from solution-internal details means:
//   * Tests can round-trip any SolutionConfig into a PipelineSpec and
//     inspect the operators/edges list without spinning up an executor.
//   * Future solutions (e.g. a CustomSolution oneof arm) can add a
//     mapping without touching the runner/executor code paths.

#pragma once

#include "rac/core/rac_error.h"

// Forward-declare proto types to keep protobuf an implementation
// detail (see CMakeLists.txt: protobuf::libprotobuf is PRIVATE).
namespace runanywhere::v1 {
class PipelineSpec;
class SolutionConfig;
}  // namespace runanywhere::v1

namespace rac::solutions {

/// Expand `config` into an equivalent PipelineSpec. Returns a commons
/// error code (RAC_ERROR_INVALID_CONFIGURATION) when the config oneof
/// is unset or unsupported; otherwise populates `*out_spec` and
/// returns RAC_SUCCESS.
rac_result_t convert_solution_to_pipeline(
    const runanywhere::v1::SolutionConfig& config,
    runanywhere::v1::PipelineSpec*         out_spec);

}  // namespace rac::solutions
