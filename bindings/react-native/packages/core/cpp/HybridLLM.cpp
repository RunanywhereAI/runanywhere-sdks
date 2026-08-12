/**
 * HybridLLM.cpp
 *
 * Bridges `rac_llm_set_stream_proto_callback` through Nitro so the
 * TypeScript `RunAnywhere.generateStream` consumer can decode canonical
 * `LLMStreamEvent` proto bytes from the raw `ArrayBuffer` callbacks.
 *
 * --- Lifetime / concurrency protocol (pass3-syn-045) ----------------
 *
 * The commons LLM stream dispatcher (`rac_llm_stream.cpp`) copies the
 * registered slot {fn, user_data} under its lock, RELEASES the lock,
 * and then calls the trampoline. The trampoline therefore runs WITHOUT
 * the commons lock held, which means our unsubscribe path cannot
 * assume that a successful `rac_llm_unset_stream_proto_callback` is
 * sufficient to free the Registration: a generation-thread dispatcher
 * may still be mid-call with the raw `user_data` pointer it snapshotted
 * before the unset.
 *
 * Naive `delete reg` after `unset` therefore opens a UAF window where
 * the trampoline reads `reg->active` from freed memory.
 *
 * Fix: ownership is held by a process-global `shared_ptr<Registration>`
 * registry keyed by the raw Registration address. The trampoline looks
 * the registration up under a short mutex, takes its OWN strong copy of
 * the `shared_ptr`, drops the mutex, and only then dereferences the
 * Registration. The unsubscribe lambda follows the canonical commons
 * teardown sequence documented on `rac_llm_set_stream_proto_callback`
 * (see rac_llm_stream.h) and mirrored by Swift's HandleStreamAdapter:
 *   (1) `rac_llm_unset_stream_proto_callback` — no NEW dispatch starts;
 *   (2) `rac_llm_proto_quiesce` — spin-wait until every in-flight
 *       dispatch has returned;
 *   (3) erase the registry entry, dropping the registry's strong ref.
 * Step (2) closes the window where a dispatcher that snapshotted the
 * slot before step (1) is still inside the trampoline when the erase
 * could otherwise free the Registration. The shared_ptr registry keeps
 * the trampoline read-path safe even if a dispatch overlaps the erase.
 *
 * Mirrors Swift's HandleStreamAdapter (per-handle fan-out kept alive
 * via `Unmanaged.passRetained` + a static dictionary, torn down with
 * unregister → quiesce → release) and Kotlin's 2-phase install/uninstall.
 */

#include "HybridLLM.hpp"

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>

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

// Process-global registry: maps a Registration's raw address (the value
// we pass to the C ABI as `user_data`) to the owning `shared_ptr`.
// The mutex guards both lookups (from the dispatcher trampoline) and
// erasures (from the unsubscribe lambda). We never dereference the raw
// pointer as a Registration* — it's only ever used as a map key — so
// even a stale raw pointer from a freed Registration is safe to look up.
std::mutex& llm_registry_mu() {
  static std::mutex m;
  return m;
}

std::unordered_map<void*, std::shared_ptr<Registration>>& llm_registry() {
  static std::unordered_map<void*, std::shared_ptr<Registration>> reg;
  return reg;
}

// Acquire a strong reference for the duration of one dispatch. Returns
// nullptr if the registration has already been unsubscribed.
std::shared_ptr<Registration> acquire_llm_registration(void* user_data) {
  std::lock_guard<std::mutex> lock(llm_registry_mu());
  auto it = llm_registry().find(user_data);
  if (it == llm_registry().end()) return nullptr;
  return it->second;  // copy, bumps refcount
}

void llm_trampoline(const uint8_t* event_bytes,
                    size_t event_size,
                    void* user_data) {
  if (user_data == nullptr || event_bytes == nullptr) return;

  // Take a strong reference BEFORE dereferencing. If the unsubscribe
  // lambda has already won the race and removed the entry, this
  // returns null and we exit without touching freed memory.
  auto reg = acquire_llm_registration(user_data);
  if (!reg) return;
  if (!reg->active.load(std::memory_order_acquire) || !reg->onBytes) return;

  auto buffer = ArrayBuffer::copy(event_bytes, event_size);
  try {
    reg->onBytes(buffer);
  } catch (...) {
    // Keep native dispatch isolated from JS exceptions.
  }
  // `reg` strong reference released here; if the unsubscribe lambda
  // removed the registry entry concurrently, the Registration is
  // destroyed when our local strong ref drops.
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

  auto reg = std::make_shared<Registration>();
  reg->onBytes = onBytes;
  reg->onDone = onDone;
  reg->onError = onError;
  reg->handle = llm_handle;

  // Identity for the C ABI's `user_data` slot. The raw Registration*
  // is used solely as a map key — never dereferenced via this pointer.
  void* user_data = reg.get();

  // Publish the strong reference into the registry BEFORE installing
  // the C callback. If we install first and the callback fires
  // synchronously, the trampoline would observe an empty registry and
  // drop the event.
  {
    std::lock_guard<std::mutex> lock(llm_registry_mu());
    llm_registry()[user_data] = reg;
  }

  rac_result_t rc = rac_llm_set_stream_proto_callback(
      llm_handle, &llm_trampoline, user_data);

  if (rc != RAC_SUCCESS) {
    {
      std::lock_guard<std::mutex> lock(llm_registry_mu());
      llm_registry().erase(user_data);
    }
    std::string msg = "rac_llm_set_stream_proto_callback failed: code=";
    msg += std::to_string(static_cast<int>(rc));
    try {
      if (onError) onError(msg);
    } catch (...) {}
    return []() {};
  }

  // The unsubscribe lambda owns its own strong reference (`reg`). The
  // registry holds another. The unsubscribe follows the canonical
  // commons teardown sequence (rac_llm_stream.h):
  //   1. Flips `active` (cheap fast-path skip for any dispatcher whose
  //      registry lookup happens to win the race with us).
  //   2. Calls `rac_llm_unset_stream_proto_callback` so no NEW dispatch
  //      starts after this point.
  //   3. Calls `rac_llm_proto_quiesce` so every in-flight dispatch that
  //      snapshotted the slot before step 2 has returned before we drop
  //      the registry's ownership in step 4.
  //   4. Erases the registry entry — drops the registry's strong ref.
  //   5. Drops the lambda's `reg` capture when the lambda is destroyed.
  return [reg, llm_handle, user_data]() mutable {
    bool was_active = reg->active.exchange(false, std::memory_order_acq_rel);
    if (!was_active) return;
    rac_llm_unset_stream_proto_callback(llm_handle);
    rac_llm_proto_quiesce();
    {
      std::lock_guard<std::mutex> lock(llm_registry_mu());
      llm_registry().erase(user_data);
    }
    // `reg` drops here when the lambda goes out of scope.
  };
}

}  // namespace margelo::nitro::runanywhere
