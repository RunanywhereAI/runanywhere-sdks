/**
 * HybridLLM.cpp
 *
 * Bridges rac_llm_set_stream_proto_callback through Nitro so the
 * TypeScript LLMStreamAdapter can consume canonical LLMStreamEvent proto
 * bytes instead of relying on a stale, unregistered HybridObject.
 */

#include "HybridLLM.hpp"

#include <atomic>
#include <cstdint>
#include <string>

#include "rac_llm_stream.h"
#include "rac_types.h"

namespace margelo::nitro::runanywhere {

namespace {

struct Registration {
  std::function<void(const std::shared_ptr<ArrayBuffer>&)> onBytes;
  std::function<void()> onDone;
  std::function<void(const std::string&)> onError;
  rac_handle_t handle = nullptr;
  std::atomic<bool> active{true};
};

void llm_trampoline(const uint8_t* event_bytes,
                    size_t event_size,
                    void* user_data) {
  if (user_data == nullptr || event_bytes == nullptr) return;

  auto* reg = static_cast<Registration*>(user_data);
  if (!reg->active.load(std::memory_order_acquire) || !reg->onBytes) return;

  auto buffer = ArrayBuffer::copy(event_bytes, event_size);
  try {
    reg->onBytes(buffer);
  } catch (...) {
    // Keep native dispatch isolated from JS exceptions.
  }
}

}  // namespace

HybridLLM::HybridLLM() : HybridObject(TAG) {}

HybridLLM::~HybridLLM() = default;

std::function<void()> HybridLLM::subscribeProtoEvents(
    double handle,
    const std::function<void(const std::shared_ptr<ArrayBuffer>&)>& onBytes,
    const std::function<void()>& onDone,
    const std::function<void(const std::string&)>& onError) {
  auto llm_handle = reinterpret_cast<rac_handle_t>(
      static_cast<uintptr_t>(static_cast<int64_t>(handle)));

  auto* reg = new Registration();
  reg->onBytes = onBytes;
  reg->onDone = onDone;
  reg->onError = onError;
  reg->handle = llm_handle;

  rac_result_t rc = rac_llm_set_stream_proto_callback(
      llm_handle, &llm_trampoline, reg);

  if (rc != RAC_SUCCESS) {
    std::string msg = "rac_llm_set_stream_proto_callback failed: code=";
    msg += std::to_string(static_cast<int>(rc));
    try {
      if (onError) onError(msg);
    } catch (...) {}
    delete reg;
    return []() {};
  }

  return [reg, llm_handle]() {
    bool was_active = reg->active.exchange(false, std::memory_order_acq_rel);
    if (!was_active) return;
    rac_llm_unset_stream_proto_callback(llm_handle);
    delete reg;
  };
}

}  // namespace margelo::nitro::runanywhere
