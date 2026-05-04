// SPDX-License-Identifier: Apache-2.0
//
// rac/solutions/config_loader.hpp — T4.7 entry points for PipelineSpec /
// SolutionConfig in both binary proto and YAML form.
//
// The executor consumes PipelineSpec messages. Front-ends deliver those
// in three ways:
//
//   1. Binary protobuf bytes — the canonical wire form. Mandatory path.
//   2. YAML text — the ergonomic DSL bundled inside solution packages.
//      We parse a deliberately narrow YAML subset (block mappings, block
//      sequences, quoted / bare scalars) that is sufficient to express
//      every field declared in pipeline.proto and solutions.proto. A
//      full yaml-cpp dependency is deliberately avoided; the required
//      expressiveness is small and purely declarative.
//   3. Protobuf text format — intentionally omitted here. Callers that
//      need it should serialize the bytes and go via (1).
//
// Each loader sets `rac_error_set_details(...)` on failure with a
// one-line diagnostic so the caller can surface the problem to
// developers without a logging dependency.

#pragma once

#include <cstddef>
#include <string>

#include "rac/core/rac_error.h"

// Forward-declare proto types to keep protobuf an implementation
// detail (see CMakeLists.txt: protobuf::libprotobuf is PRIVATE).
namespace runanywhere::v1 {
class PipelineSpec;
class SolutionConfig;
}  // namespace runanywhere::v1

namespace rac::solutions {

/// Parse binary-encoded PipelineSpec. `data`/`len` describe the wire
/// bytes produced by `PipelineSpec::SerializeToArray`. Returns
/// RAC_ERROR_DECODING_ERROR on a malformed payload.
rac_result_t load_pipeline_from_proto_bytes(
    const void*                    data,
    size_t                         len,
    runanywhere::v1::PipelineSpec* out_spec);

/// Parse binary-encoded SolutionConfig. Same semantics as the pipeline
/// loader above.
rac_result_t load_solution_from_proto_bytes(
    const void*                       data,
    size_t                            len,
    runanywhere::v1::SolutionConfig*  out_config);

/// Parse a YAML document describing a PipelineSpec (top-level fields:
/// `name`, `operators`, `edges`, `options`). Returns
/// RAC_ERROR_INVALID_FORMAT on a syntax or structural error.
rac_result_t load_pipeline_from_yaml(
    const std::string&             yaml,
    runanywhere::v1::PipelineSpec* out_spec);

/// Parse a YAML document describing a SolutionConfig. The document is
/// expected to have exactly one of the oneof keys (`voice_agent`,
/// `rag`, `wake_word`, `agent_loop`, `time_series`) as the top-level
/// key, mirroring the proto oneof.
rac_result_t load_solution_from_yaml(
    const std::string&                yaml,
    runanywhere::v1::SolutionConfig*  out_config);

}  // namespace rac::solutions
