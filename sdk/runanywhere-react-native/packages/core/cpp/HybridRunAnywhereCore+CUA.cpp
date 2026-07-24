/**
 * HybridRunAnywhereCore+CUA.cpp
 *
 * Domain implementation for HybridRunAnywhereCore — Computer-Use Agent (CUA).
 *
 * Thin, stateless sync thunks to the commons CUA scaffold
 * (`rac/features/cua/rac_cua.h`):
 *   - cuaSystemPrompt  → rac_cua_system_prompt
 *   - cuaParseAction   → rac_cua_parse_action_proto
 *
 * No model handle, no I/O — pure CPU string work that pairs with the VLM
 * inference calls. Mirrors the Swift `RunAnywhere.CUA` facade
 * (RunAnywhere+CUA.swift). `cuaParseAction` returns the serialized
 * `runanywhere.v1.CuaAction` proto bytes (the same proto-byte bridging every
 * other modality uses); the TypeScript facade decodes them into the public
 * `CuaAction` (enum `kind` + optional `coordinate`). An unknown profile throws,
 * which the TS facade maps to `null`.
 */
#include "HybridRunAnywhereCore+Common.hpp"
#include "rac/features/cua/rac_cua.h"

#include <cstdint>
#include <memory>
#include <stdexcept>
#include <vector>

namespace margelo::nitro::runanywhere {

std::string HybridRunAnywhereCore::cuaSystemPrompt(const std::string &profileId,
                                                   double displayWidth,
                                                   double displayHeight) {
  const auto width = static_cast<uint32_t>(displayWidth);
  const auto height = static_cast<uint32_t>(displayHeight);

  // First call with a NULL buffer to learn the full length (matches the Swift
  // facade's two-pass query). Negative / zero → unknown profile → empty string.
  int needed =
      rac_cua_system_prompt(profileId.c_str(), width, height, nullptr, 0);
  if (needed <= 0) {
    return std::string();
  }

  std::vector<char> buffer(static_cast<size_t>(needed) + 1, '\0');
  rac_cua_system_prompt(profileId.c_str(), width, height, buffer.data(),
                        buffer.size());
  return std::string(buffer.data());
}

std::shared_ptr<ArrayBuffer> HybridRunAnywhereCore::cuaParseAction(
    const std::string &profileId, const std::string &modelOutput,
    double viewportWidth, double viewportHeight) {
  rac_proto_buffer_t buffer{};
  const rac_result_t rc = rac_cua_parse_action_proto(
      profileId.c_str(), modelOutput.c_str(),
      static_cast<uint32_t>(viewportWidth),
      static_cast<uint32_t>(viewportHeight), &buffer);

  // rc != RAC_SUCCESS → unknown profile / NULL args. Throw; the TS facade
  // catches and returns null (Swift returns nil).
  if (rc != RAC_SUCCESS) {
    rac_proto_buffer_free(&buffer);
    throw std::runtime_error("rac_cua_parse_action_proto: unknown CUA profile");
  }

  // Success — possibly empty bytes for a valid profile with no tool_call, which
  // decodes to a CuaAction with parse_ok = false.
  auto result = (buffer.data != nullptr && buffer.size > 0)
                    ? ArrayBuffer::copy(buffer.data, buffer.size)
                    : ArrayBuffer::allocate(0);
  rac_proto_buffer_free(&buffer);
  return result;
}

} // namespace margelo::nitro::runanywhere
