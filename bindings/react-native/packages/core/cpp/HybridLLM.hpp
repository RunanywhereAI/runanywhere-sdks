/**
 * HybridLLM.hpp
 *
 * Nitro HybridObject that exposes the proto-byte LLM stream callback ABI
 * to React Native. Mirrors HybridVoiceAgent for the LLM component handle
 * returned by RunAnywhereCore.getLLMHandle().
 */

#pragma once

#if __has_include(<NitroModules/HybridObject.hpp>)
#include "HybridLLMSpec.hpp"
#else
#include "../nitrogen/generated/shared/c++/HybridLLMSpec.hpp"
#endif

#include <functional>
#include <memory>

namespace margelo::nitro::runanywhere {

class HybridLLM : public HybridLLMSpec {
 public:
  HybridLLM();
  ~HybridLLM() override;

  std::function<void()> subscribeProtoEvents(
      double handle,
      const std::function<void(const std::shared_ptr<ArrayBuffer>&)>& onBytes,
      const std::function<void()>& onDone,
      const std::function<void(const std::string&)>& onError) override;
};

}  // namespace margelo::nitro::runanywhere
