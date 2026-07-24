/**
 * HybridRunAnywhereCore+CUA.cpp
 *
 * Domain implementation for HybridRunAnywhereCore — Computer-Use Agent (CUA).
 *
 * Thin, stateless sync thunks to the commons CUA scaffold
 * (`rac/features/cua/rac_cua.h`):
 *   - cuaSystemPrompt  → rac_cua_system_prompt
 *   - cuaParseAction   → rac_cua_parse_action
 *
 * No model handle, no I/O, no proto — pure CPU string work that pairs with the
 * VLM inference calls. Mirrors the Swift `RunAnywhere.CUA` facade
 * (RunAnywhere+CUA.swift), which marshals the same `rac_cua_action_t` struct.
 * The `rac_cua_action_t` fields are projected onto the Nitro `CuaActionNative`
 * struct; the TypeScript facade re-shapes them into the public `CuaAction`
 * (enum `kind` + optional `coordinate`).
 */
#include "HybridRunAnywhereCore+Common.hpp"
#include "rac/features/cua/rac_cua.h"

#include <cstdint>
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

CuaActionNative HybridRunAnywhereCore::cuaParseAction(
    const std::string &profileId, const std::string &modelOutput,
    double viewportWidth, double viewportHeight) {
  rac_cua_action_t action{};
  const int rc = rac_cua_parse_action(
      profileId.c_str(), modelOutput.c_str(),
      static_cast<uint32_t>(viewportWidth),
      static_cast<uint32_t>(viewportHeight), &action);

  // rc != 0 → unknown profile / NULL args. Return a struct flagged as such;
  // the TS facade maps `profileKnown == false` to `null` (Swift returns nil).
  if (rc != 0) {
    return CuaActionNative(/*profileKnown*/ false, /*kind*/ 0.0,
                           /*hasCoordinate*/ false, /*x*/ 0.0, /*y*/ 0.0,
                           /*scrollPixels*/ 0.0, /*waitSeconds*/ 0.0,
                           /*text*/ std::string(), /*reasoning*/ std::string(),
                           /*isValid*/ false);
  }

  return CuaActionNative(
      /*profileKnown*/ true,
      /*kind*/ static_cast<double>(action.type),
      /*hasCoordinate*/ action.has_coordinate != 0,
      /*x*/ static_cast<double>(action.x),
      /*y*/ static_cast<double>(action.y),
      /*scrollPixels*/ static_cast<double>(action.scroll_pixels),
      /*waitSeconds*/ action.wait_seconds,
      /*text*/ std::string(action.text),
      /*reasoning*/ std::string(action.reasoning),
      /*isValid*/ action.parse_ok != 0);
}

} // namespace margelo::nitro::runanywhere
