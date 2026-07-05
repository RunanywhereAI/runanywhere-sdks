/**
 * @file rac_http_upsert_mode.cpp
 * @brief Implementation of the Supabase-style upsert request flag.
 *
 * Lets callers tag a `rac_http_request_t*` as an UPSERT before
 * submitting it through `rac_http_request_send/stream/resume`. The
 * dispatch sites consume the tag and apply the URL / `Prefer` header
 * rewrite before handing off to the registered platform transport
 * adapter. This pulls the Supabase wire-protocol shape into commons
 * so every SDK has a single ABI to call instead of hand-rolling the
 * same upsert path-rewrite logic per platform.
 *
 * The mapping is keyed by the `rac_http_request_t*` pointer so the
 * stable public struct never has to change. State is consumed (cleared)
 * on the first `consume_upsert_transform` call so a second send of the
 * same struct without a fresh `set_upsert_mode` will not silently
 * inherit the previous configuration.
 *
 * Thread-safety: backed by a Meyers singleton + `std::mutex`. Any
 * thread can arm or consume; cross-thread arming is allowed.
 */

#include "rac_http_upsert_mode.h"

#include <mutex>
#include <string>
#include <unordered_map>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/infrastructure/http/rac_http_client.h"

namespace {

/// Per-request upsert configuration kept while the caller arms the
/// request. The dispatch path reads (and removes) the entry.
struct UpsertEntry {
    std::string on_conflict_field;
};

/// Global registry of armed requests. Meyers singleton ensures
/// initialization-order safety; the mutex protects all accesses.
struct Registry {
    std::mutex mu;
    std::unordered_map<const rac_http_request_t*, UpsertEntry> entries;
};

Registry& registry() {
    static Registry r;
    return r;
}

/// Build the rewritten URL — appends `on_conflict=<field>` as either
/// the first query parameter (`?...`) or an additional one (`&...`).
std::string build_upsert_url(const char* original_url, const std::string& on_conflict_field) {
    std::string url = original_url ? original_url : "";
    const bool has_query = url.find('?') != std::string::npos;
    url.append(has_query ? "&on_conflict=" : "?on_conflict=");
    url.append(on_conflict_field);
    return url;
}

}  // namespace

// Public C ABI — set_upsert_mode

extern "C" rac_result_t rac_http_request_set_upsert_mode(rac_http_request_t* req,
                                                         const char* on_conflict_field) {
    if (req == nullptr) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    auto& reg = registry();
    std::lock_guard<std::mutex> lock(reg.mu);

    if (on_conflict_field == nullptr) {
        // Explicit "clear" — disarm any previous arming for this pointer.
        reg.entries.erase(req);
        return RAC_SUCCESS;
    }

    try {
        reg.entries[req] = UpsertEntry{std::string(on_conflict_field)};
    } catch (const std::bad_alloc&) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    return RAC_SUCCESS;
}

// Internal helpers — consume_upsert_transform

namespace rac::http {

UpsertTransform consume_upsert_transform(const rac_http_request_t* req) {
    UpsertTransform out;
    if (req == nullptr) {
        return out;
    }

    auto& reg = registry();
    std::string on_conflict;
    {
        std::lock_guard<std::mutex> lock(reg.mu);
        auto it = reg.entries.find(req);
        if (it == reg.entries.end()) {
            return out;
        }
        on_conflict = std::move(it->second.on_conflict_field);
        reg.entries.erase(it);
    }

    out.engaged = true;
    out.transformed_url = build_upsert_url(req->url, on_conflict);
    out.prefer_header_value = "resolution=merge-duplicates,return=representation";
    return out;
}

}  // namespace rac::http
