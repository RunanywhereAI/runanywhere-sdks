/**
 * HybridVoiceAgent.cpp
 *
 * Implementation for the Nitro
 * VoiceAgent HybridObject defined in VoiceAgent.nitro.ts.
 *
 * Lifecycle of one subscription:
 *
 *   TS: NitroVoiceAgent.subscribeProtoEvents(handle, onBytes, onDone, onError)
 *                                   │
 *                                   ▼
 *   C++: HybridVoiceAgent::subscribeProtoEvents
 *          1. heap-allocates Registration (via shared_ptr) and publishes
 *             it into a process-global registry keyed by the raw
 *             Registration address used as C `user_data`.
 *          2. rac_voice_agent_set_proto_callback(handle, trampoline, ud)
 *          3. returns unsubscribe closure that calls unset, then erases
 *             the registry entry (drops the registry's strong ref).
 *                                   │
 *                                   ▼
 *   C ABI: each event fires trampoline(bytes, size, user_data)
 *          trampoline looks up the strong shared_ptr<Registration> in
 *          the registry under a mutex, copies it locally, then
 *          dispatches with the local strong ref keeping the
 *          Registration alive for the duration of the call.
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
 *
 * --- Lifetime / concurrency protocol --------------------------------
 *
 * Commons voice_event dispatch (`rac_voice_event_abi.cpp`) copies the
 * registered slot {fn, user_data} under its lock, RELEASES the lock,
 * and then calls the trampoline. The trampoline therefore runs WITHOUT
 * the commons lock held: a pipeline-thread dispatcher may still be
 * mid-call with the raw `user_data` pointer it snapshotted before
 * `rac_voice_agent_set_proto_callback(nullptr)` runs from the JS
 * thread. Naively `delete reg` after `unset` therefore opens a UAF
 * window where the trampoline reads `reg->active` from freed memory.
 *
 * Fix: ownership is held by a process-global
 * `shared_ptr<Registration>` registry keyed by the raw Registration
 * address. The trampoline looks the registration up under a short
 * mutex, takes its OWN strong copy of the shared_ptr, drops the mutex,
 * and only then dereferences the Registration. The unsubscribe lambda
 * calls `unset` (so no NEW dispatch will start) and erases the
 * registry entry; any racing dispatcher either acquired its strong ref
 * before the erase (Registration stays alive for the duration of its
 * call) or after (observes null and returns harmlessly).
 *
 * Mirrors the spirit of Swift's HandleStreamAdapter (per-handle
 * fan-out kept alive via `Unmanaged.passRetained` + a static
 * dictionary) and Kotlin's 2-phase install/uninstall.
 */

#include "HybridVoiceAgent.hpp"

#include <atomic>
#include <cstring>
#include <memory>
#include <mutex>
#include <unordered_map>

// Commons C ABI — the only commons include this file needs.
#include "rac_voice_agent.h"
#include "rac_voice_event_abi.h"

namespace margelo::nitro::runanywhere {

namespace {

// Per-subscription state. Owned by a process-global shared_ptr
// registry; the unsubscribe closure holds an additional strong ref so
// the Registration outlives any racing dispatcher.
struct Registration {
  std::function<void(const std::shared_ptr<ArrayBuffer>&)> onBytes;
  std::function<void()>                                     onDone;
  std::function<void(const std::string&)>                   onError;
  rac_voice_agent_handle_t                                  handle;
  std::atomic<bool>                                         active{true};
};

// Process-global registry: maps a Registration's raw address (the value
// passed to the C ABI as `user_data`) to the owning `shared_ptr`. The
// mutex guards both lookups (dispatcher trampoline) and erasures
// (unsubscribe lambda). The raw pointer is used SOLELY as a map key
// and is never dereferenced via this path — a stale key from a freed
// Registration is safe to look up.
std::mutex& va_registry_mu() {
  static std::mutex m;
  return m;
}

std::unordered_map<void*, std::shared_ptr<Registration>>& va_registry() {
  static std::unordered_map<void*, std::shared_ptr<Registration>> reg;
  return reg;
}

// Acquire a strong reference for the duration of one dispatch. Returns
// nullptr if the registration has already been unsubscribed.
std::shared_ptr<Registration> acquire_va_registration(void* user_data) {
  std::lock_guard<std::mutex> lock(va_registry_mu());
  auto it = va_registry().find(user_data);
  if (it == va_registry().end()) return nullptr;
  return it->second;  // copy, bumps refcount
}

void va_trampoline(const uint8_t* event_bytes,
                   size_t         event_size,
                   void*          user_data) {
  if (user_data == nullptr || event_bytes == nullptr) return;

  // Take a strong reference BEFORE dereferencing. If the unsubscribe
  // lambda has already won the race and removed the entry, this
  // returns null and we exit without touching freed memory.
  auto reg = acquire_va_registration(user_data);
  if (!reg) return;
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
  // `reg` strong reference released here; if the unsubscribe lambda
  // erased the registry entry concurrently, the Registration is
  // destroyed when our local strong ref drops.
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

  auto reg = std::make_shared<Registration>();
  reg->onBytes = onBytes;
  reg->onDone  = onDone;
  reg->onError = onError;
  reg->handle  = ra_handle;

  // Identity for the C ABI's `user_data` slot. The raw Registration*
  // is used solely as a map key — never dereferenced via this pointer.
  void* user_data = reg.get();

  // Publish the strong reference into the registry BEFORE installing
  // the C callback so that a synchronously-fired callback during
  // register() observes the registration.
  {
    std::lock_guard<std::mutex> lock(va_registry_mu());
    va_registry()[user_data] = reg;
  }

  rac_result_t rc = rac_voice_agent_set_proto_callback(
      ra_handle, &va_trampoline, user_data);

  if (rc != RAC_SUCCESS) {
    // Roll back the registry entry. Tell JS via the provided onError
    // callback. Return a no-op unsubscribe because there's no C-side
    // state to clear.
    {
      std::lock_guard<std::mutex> lock(va_registry_mu());
      va_registry().erase(user_data);
    }
    std::string msg = "rac_voice_agent_set_proto_callback failed: code=";
    msg += std::to_string(static_cast<int>(rc));
    try {
      if (onError) onError(msg);
    } catch (...) {}
    return []() {};
  }

  // Capture reg (strong ref) + ra_handle + user_data by value in the
  // unsubscribe closure. The closure's own strong ref keeps the
  // Registration alive until the closure is destroyed; the registry
  // strong ref is dropped by the erase below. Double-invoking is safe
  // thanks to the atomic `active` flag (no second `unset`/erase).
  return [reg, ra_handle, user_data]() mutable {
    bool was_active = reg->active.exchange(false, std::memory_order_acq_rel);
    if (!was_active) return;  // already unsubscribed
    rac_voice_agent_set_proto_callback(ra_handle, nullptr, nullptr);
    {
      std::lock_guard<std::mutex> lock(va_registry_mu());
      va_registry().erase(user_data);
    }
    // `reg` drops here when the lambda goes out of scope.
  };
}

}  // namespace margelo::nitro::runanywhere
