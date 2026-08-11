/**
 * @file rac_http_transport_ref.h
 * @brief RAII guard around the refcounted transport accessor.
 *
 * `rac_internal::get_http_transport` bumps the active transport slot's
 * refcount so the adapter's `user_data` stays alive for the duration of
 * a dispatch, and `put_http_transport` drops it (running the adapter's
 * deferred `destroy()` once the last in-flight caller releases). The
 * contract is "every successful get is paired with exactly one put on
 * every exit path" — the kind of invariant C++ expresses with a scope
 * guard (cf. `std::lock_guard`) rather than a comment. `TransportRef`
 * acquires in its constructor and releases in its destructor, so the
 * pairing cannot be broken by an early return.
 */

#ifndef RAC_INFRASTRUCTURE_HTTP_RAC_HTTP_TRANSPORT_REF_H
#define RAC_INFRASTRUCTURE_HTTP_RAC_HTTP_TRANSPORT_REF_H

#include "rac/infrastructure/http/rac_http_transport.h"

namespace rac_internal {

// Defined in rac_http_transport.cpp. Acquires a reference to the active
// transport slot; the matching put_http_transport() releases it.
bool get_http_transport(const rac_http_transport_ops_t** out_ops, void** out_user_data);
void put_http_transport();

/// Scoped reference to the currently-registered platform transport. The
/// stack-scoped lifetime mirrors the LIFO acquire/release stack inside
/// the registry, so nested guards stay paired.
class TransportRef {
   public:
    TransportRef() { ok_ = get_http_transport(&ops_, &user_data_); }
    ~TransportRef() {
        if (ok_) {
            put_http_transport();
        }
    }

    TransportRef(const TransportRef&) = delete;
    TransportRef& operator=(const TransportRef&) = delete;
    TransportRef(TransportRef&&) = delete;
    TransportRef& operator=(TransportRef&&) = delete;

    explicit operator bool() const noexcept { return ok_ && ops_ != nullptr; }
    const rac_http_transport_ops_t* ops() const noexcept { return ops_; }
    void* user_data() const noexcept { return user_data_; }

   private:
    const rac_http_transport_ops_t* ops_ = nullptr;
    void* user_data_ = nullptr;
    bool ok_ = false;
};

}  // namespace rac_internal

#endif  // RAC_INFRASTRUCTURE_HTTP_RAC_HTTP_TRANSPORT_REF_H
