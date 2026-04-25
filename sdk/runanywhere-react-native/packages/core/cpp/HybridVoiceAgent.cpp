/**
 * HybridVoiceAgent.cpp
 *
 * v3-readiness Phase A3 / GAP 09 #6. Implementation for the Nitro
 * VoiceAgent HybridObject defined in VoiceAgent.nitro.ts.
 *
 * Lifecycle of one subscription:
 *
 *   TS: NitroVoiceAgent.subscribeProtoEvents(handle, onBytes, onDone, onError)
 *                                   │
 *                                   ▼
 *   C++: HybridVoiceAgent::subscribeProtoEvents
 *          1. heap-allocates Registration { onBytes, onDone, onError, handle }
 *          2. rac_voice_agent_set_proto_callback(handle, trampoline, reg)
 *          3. returns std::function { trampoline=nullptr; delete reg }
 *                                   │
 *                                   ▼
 *   C ABI: each event fires trampoline(bytes, size, user_data=reg)
 *          trampoline copies bytes → ArrayBuffer
 *          trampoline invokes reg->onBytes(buffer)
 *                                   │
 *                                   ▼
 *   Nitro JSI: onBytes callback re-enters the JS runtime with the buffer.
 *
 * ABI limitation: the C ABI keeps ONE proto callback slot per handle.
 * Multiple concurrent subscribeProtoEvents() calls with the same handle
 * will REPLACE each other. Each call's returned unsubscribe function
 * clears the slot unconditionally (the last-registered subscription
 * wins; earlier ones go silent). This matches the Kotlin + Dart
 * adapters' behavior and is documented on the spec interface.
 */

#include "HybridVoiceAgent.hpp"

#include <atomic>
#include <cstring>

// Commons C ABI — the only commons include this file needs.
#include "rac_voice_agent.h"
#include "rac_voice_event_abi.h"

namespace margelo::nitro::runanywhere {

namespace {

// Per-subscription state. Heap-owned by the unsubscribe closure; freed
// when the closure is invoked or when the HybridObject is destroyed.
struct Registration {
  std::function<void(const std::shared_ptr<ArrayBuffer>&)> onBytes;
  std::function<void()>                                     onDone;
  std::function<void(const std::string&)>                   onError;
  rac_voice_agent_handle_t                                  handle;
  std::atomic<bool>                                         active{true};
};

void va_trampoline(const uint8_t* event_bytes,
                   size_t         event_size,
                   void*          user_data) {
  if (user_data == nullptr || event_bytes == nullptr) return;

  auto* reg = static_cast<Registration*>(user_data);
  if (!reg->active.load(std::memory_order_acquire)) return;
  if (!reg->onBytes) return;

  // Copy bytes off the C arena (per ABI contract; the buffer is only
  // valid for the callback's duration). ArrayBuffer::copy performs the
  // memcpy and owns the resulting heap allocation — JS consumers can
  // retain it safely.
  auto buffer = ArrayBuffer::copy(event_bytes, event_size);
  try {
    reg->onBytes(buffer);
  } catch (...) {
    // Swallow exceptions so a JS-side throw doesn't re-enter the C++
    // dispatcher. Real errors propagate via onError from the
    // subscribeProtoEvents path, not from per-event JS callbacks.
  }
}

}  // namespace

HybridVoiceAgent::HybridVoiceAgent() : HybridObject(TAG) {}

HybridVoiceAgent::~HybridVoiceAgent() = default;

std::function<void()> HybridVoiceAgent::subscribeProtoEvents(
    double                                                    handle,
    const std::function<void(const std::shared_ptr<ArrayBuffer>&)>& onBytes,
    const std::function<void()>&                              onDone,
    const std::function<void(const std::string&)>&            onError) {

  // Re-cast the JS number back to a handle. Double can represent any
  // 53-bit integer exactly, which is more than the 48-bit
  // uintptr_t range on all supported platforms (iOS, Android, macOS).
  auto ra_handle = reinterpret_cast<rac_voice_agent_handle_t>(
      static_cast<uintptr_t>(static_cast<int64_t>(handle)));

  auto* reg = new Registration();
  reg->onBytes = onBytes;
  reg->onDone  = onDone;
  reg->onError = onError;
  reg->handle  = ra_handle;

  rac_result_t rc = rac_voice_agent_set_proto_callback(
      ra_handle, &va_trampoline, reg);

  if (rc != RAC_SUCCESS) {
    // Tell JS via the provided onError callback, then free the
    // registration. Return a no-op unsubscribe because there's no
    // C-side state to clear.
    std::string msg = "rac_voice_agent_set_proto_callback failed: code=";
    msg += std::to_string(static_cast<int>(rc));
    try {
      if (onError) onError(msg);
    } catch (...) {}
    delete reg;
    return []() {};
  }

  // Capture reg + ra_handle by value in the unsubscribe closure. The
  // closure owns the registration until it's called; double-invoking
  // is safe thanks to the atomic `active` flag.
  return [reg, ra_handle]() {
    bool was_active = reg->active.exchange(false, std::memory_order_acq_rel);
    if (!was_active) return;  // already unsubscribed
    rac_voice_agent_set_proto_callback(ra_handle, nullptr, nullptr);
    delete reg;
  };
}

}  // namespace margelo::nitro::runanywhere
