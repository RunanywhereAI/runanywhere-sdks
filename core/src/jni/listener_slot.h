#ifndef RAC_JNI_LISTENER_SLOT_H
#define RAC_JNI_LISTENER_SLOT_H

#include <mutex>
#include <utility>

namespace rac::jni {

/**
 * Replaces the listener stored in `slot` with `next` and then registers the
 * native callback, without holding `mutex` across the registration.
 *
 * The native setter may take a lock that the native side also holds while it
 * invokes the callback, and the callback takes `mutex` to read `slot`. Holding
 * `mutex` across the setter would lock the two in opposite orders.
 *
 * `registration_mutex` is held for the whole call so concurrent calls finish
 * their native registrations in the same order they publish to `slot`. The
 * callback must never take it.
 *
 * `register_native(bool has_listener)` returns 0 on success. On failure the
 * previous listener is restored if `slot` still holds `next`. Every ref this
 * call swaps out of `slot` is released through `release(ref)` exactly once;
 * a ref swapped out by a concurrent call belongs to that call.
 */
template <typename Ref, typename RegisterFn, typename ReleaseFn>
auto replace_listener_then_register(std::mutex& registration_mutex, std::mutex& mutex, Ref& slot,
                                    Ref next, RegisterFn&& register_native, ReleaseFn&& release) {
    std::lock_guard<std::mutex> registration(registration_mutex);
    Ref previous;
    {
        std::lock_guard<std::mutex> lock(mutex);
        previous = std::exchange(slot, next);
    }
    const auto rc = register_native(next != Ref{});
    if (rc == 0) {
        if (previous != Ref{}) {
            release(previous);
        }
        return rc;
    }
    Ref discard = previous;
    {
        std::lock_guard<std::mutex> lock(mutex);
        if (slot == next) {
            slot = previous;
            discard = next;
        }
    }
    if (discard != Ref{}) {
        release(discard);
    }
    return rc;
}

}  // namespace rac::jni

#endif  // RAC_JNI_LISTENER_SLOT_H
