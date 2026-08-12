/**
 * @file rac_stream_adapter.h
 * @brief RunAnywhere Commons - Shared stream-callback adapter for plugin vtables
 *
 * Backend vtable adapters that forward token streaming to an engine API
 * frequently need a 2-field `{callback, user_data}` bridge struct. This
 * header provides a single template so each primitive (LLM, VLM, STT, ...)
 * can parameterize the adapter on its own `rac_*_stream_callback_fn` type
 * instead of copy-pasting the struct.
 *
 * Usage:
 *   using LLMStreamAdapter = rac::plugin::StreamAdapter<rac_llm_stream_callback_fn>;
 *   LLMStreamAdapter adapter = {callback, user_data};
 *   rac_llm_<backend>_generate_stream(..., &stream_adapter_trampoline<rac_llm_stream_callback_fn>,
 * &adapter);
 *
 * Each backend still supplies its own C trampoline function to thread the
 * `is_final` / context -> user_data translation, because those shapes differ
 * per primitive.
 */

#pragma once

namespace rac {
namespace plugin {

/// Generic {callback, user_data} bridge parameterized on the user-facing
/// callback type. Intentionally POD: no ctor, no dtor, safe to stack-allocate
/// at the call site.
template <typename CallbackT>
struct StreamAdapter {
    CallbackT callback;
    void* user_data;
};

}  // namespace plugin
}  // namespace rac
