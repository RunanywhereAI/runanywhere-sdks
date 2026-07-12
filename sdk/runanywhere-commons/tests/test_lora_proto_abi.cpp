/**
 * @file test_lora_proto_abi.cpp
 * @brief Focused lifecycle-loaded LoRA proto ABI parity tests (T2.2).
 *
 * Exercises the v2 ABI: every rac_lora_*_proto entry point resolves its
 * backend via the model-lifecycle service (rac_model_lifecycle_acquire_proto)
 * instead of taking a caller-supplied rac_handle_t. The legacy
 * rac_llm_component_create + rac_llm_component_load_model flow is intentionally
 * NOT used here — these tests pin the contract the v2 SDK bridges rely on.
 */

#include <cstdio>
#include <cstdlib>
#include <exception>
#include <string>
#include <vector>

#if defined(RAC_HAVE_PROTOBUF)
#include "lora_options.pb.h"
#include "model_types.pb.h"

#include <algorithm>
#include <ranges>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_model_lifecycle.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/lora/rac_lora_service.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/plugin/rac_plugin_entry.h"
#endif

namespace {

int test_count = 0;
int fail_count = 0;

#define CHECK(cond, label)                                                                       \
    do {                                                                                         \
        ++test_count;                                                                            \
        if (cond) {                                                                              \
            std::fprintf(stdout, "  ok:   %s\n", label);                                         \
        } else {                                                                                 \
            ++fail_count;                                                                        \
            std::fprintf(stderr, "  FAIL: %s (%s:%d) - %s\n", label, __FILE__, __LINE__, #cond); \
        }                                                                                        \
    } while (0)

#if defined(RAC_HAVE_PROTOBUF)

// Backend state captured per LoRA operation so the test can assert that the
// proto ABI dispatches to the lifecycle-owned backend (and not, say, a stale
// legacy llm_component instance).
struct LifecycleBackend {
    int load_calls{0};
    int remove_calls{0};
    int clear_calls{0};
    std::vector<std::string> loaded_paths;
    std::vector<float> loaded_scales;
};

rac_result_t backend_create(const char* /*model_id*/, const char* /*config*/, void** out_impl) {
    if (!out_impl)
        return RAC_ERROR_NULL_POINTER;
    *out_impl = new LifecycleBackend();
    return *out_impl ? RAC_SUCCESS : RAC_ERROR_OUT_OF_MEMORY;
}

rac_result_t backend_initialize(void*, const char*) {
    return RAC_SUCCESS;
}

rac_result_t backend_generate(void*, const char*, const rac_llm_options_t*, rac_llm_result_t*) {
    return RAC_SUCCESS;
}

rac_result_t backend_stream(void*, const char*, const rac_llm_options_t*,
                            rac_llm_stream_callback_fn, void*) {
    return RAC_SUCCESS;
}

rac_result_t backend_load_lora(void* impl, const char* adapter_path, float scale) {
    if (!adapter_path || adapter_path[0] == '\0')
        return RAC_ERROR_INVALID_ARGUMENT;
    auto* backend = static_cast<LifecycleBackend*>(impl);
    backend->load_calls += 1;
    auto existing = std::ranges::find(backend->loaded_paths, adapter_path);
    if (existing != backend->loaded_paths.end()) {
        backend->loaded_scales[static_cast<size_t>(existing - backend->loaded_paths.begin())] =
            scale;
    } else {
        backend->loaded_paths.emplace_back(adapter_path);
        backend->loaded_scales.push_back(scale);
    }
    return RAC_SUCCESS;
}

rac_result_t backend_remove_lora(void* impl, const char* adapter_path) {
    if (!adapter_path || adapter_path[0] == '\0')
        return RAC_ERROR_INVALID_ARGUMENT;
    auto* backend = static_cast<LifecycleBackend*>(impl);
    auto existing = std::ranges::find(backend->loaded_paths, adapter_path);
    if (existing == backend->loaded_paths.end())
        return RAC_ERROR_NOT_FOUND;
    const auto index = existing - backend->loaded_paths.begin();
    backend->loaded_paths.erase(existing);
    backend->loaded_scales.erase(backend->loaded_scales.begin() + index);
    backend->remove_calls += 1;
    return RAC_SUCCESS;
}

rac_result_t backend_clear_lora(void* impl) {
    auto* backend = static_cast<LifecycleBackend*>(impl);
    backend->clear_calls += 1;
    backend->loaded_paths.clear();
    backend->loaded_scales.clear();
    return RAC_SUCCESS;
}

void backend_destroy(void* impl) {
    delete static_cast<LifecycleBackend*>(impl);
}

const uint32_t g_supported_formats[] = {static_cast<uint32_t>(runanywhere::v1::MODEL_FORMAT_GGUF)};

rac_llm_service_ops_t make_ops(bool supports_lora) {
    rac_llm_service_ops_t ops{};
    ops.create = backend_create;
    ops.initialize = backend_initialize;
    ops.generate = backend_generate;
    ops.generate_stream = backend_stream;
    ops.destroy = backend_destroy;
    if (supports_lora) {
        ops.load_lora = backend_load_lora;
        ops.remove_lora = backend_remove_lora;
        ops.clear_lora = backend_clear_lora;
    }
    return ops;
}

rac_engine_vtable_t make_vtable(const rac_llm_service_ops_t* ops) {
    rac_engine_vtable_t v{};
    v.metadata.abi_version = RAC_PLUGIN_API_VERSION;
    v.metadata.name = "llamacpp";
    v.metadata.display_name = "lifecycle-lora-mock";
    v.metadata.engine_version = "0.0.0";
    v.metadata.priority = 10000;
    v.metadata.formats = g_supported_formats;
    v.metadata.formats_count = sizeof(g_supported_formats) / sizeof(g_supported_formats[0]);
    v.llm_ops = ops;
    return v;
}

bool serialize(const google::protobuf::MessageLite& message, std::vector<uint8_t>* out) {
    out->resize(message.ByteSizeLong());
    return out->empty() || message.SerializeToArray(out->data(), static_cast<int>(out->size()));
}

template <typename T>
bool parse_buffer(const rac_proto_buffer_t& buffer, T* out) {
    return buffer.status == RAC_SUCCESS &&
           out->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
}

runanywhere::v1::ModelInfo build_test_llm(const std::string& id, const std::string& name) {
    runanywhere::v1::ModelInfo model;
    model.set_id(id);
    model.set_name(name);
    model.set_category(runanywhere::v1::MODEL_CATEGORY_LANGUAGE);
    model.set_format(runanywhere::v1::MODEL_FORMAT_GGUF);
    model.set_framework(runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP);
    model.set_local_path("/tmp/" + id + ".gguf");
    model.set_supports_lora(true);
    model.set_is_downloaded(true);
    model.set_is_available(true);
    return model;
}

bool register_test_llm(rac_model_registry_handle_t registry,
                       const runanywhere::v1::ModelInfo& model) {
    std::vector<uint8_t> bytes;
    if (!serialize(model, &bytes))
        return false;
    return rac_model_registry_register_proto(registry, bytes.empty() ? nullptr : bytes.data(),
                                             bytes.size()) == RAC_SUCCESS;
}

bool register_test_lora_adapter(const std::string& adapter_id, const std::string& model_id) {
    const char* compatible_models[] = {model_id.c_str()};
    rac_lora_entry_t entry{};
    entry.id = const_cast<char*>(adapter_id.c_str());
    entry.name = const_cast<char*>(adapter_id.c_str());
    entry.compatible_model_ids = const_cast<char**>(compatible_models);
    entry.compatible_model_count = 1;
    return rac_lora_registry_register(rac_get_lora_registry(), &entry) == RAC_SUCCESS;
}

bool lifecycle_load(rac_model_registry_handle_t registry, const std::string& model_id) {
    runanywhere::v1::ModelLoadRequest request;
    request.set_model_id(model_id);
    std::vector<uint8_t> bytes;
    if (!serialize(request, &bytes))
        return false;
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc =
        rac_model_lifecycle_load_proto(registry, bytes.data(), bytes.size(), &out);
    runanywhere::v1::ModelLoadResult result;
    const bool ok = rc == RAC_SUCCESS && parse_buffer(out, &result) && result.success();
    rac_proto_buffer_free(&out);
    return ok;
}

void reset_environment() {
    rac_model_lifecycle_reset();
    rac_sdk_event_clear_queue();
    (void)rac_plugin_unregister("llamacpp");
}

bool state_carries(const runanywhere::v1::LoRAState& state, const std::string& adapter_id,
                   const std::string& adapter_path) {
    return std::ranges::any_of(state.loaded_adapters(),
                               [&](const runanywhere::v1::LoRAAdapterInfo& info) {
                                   return info.adapter_id() == adapter_id &&
                                          info.adapter_path() == adapter_path && info.applied();
                               });
}

// Apply/remove without a caller-supplied handle must succeed end-to-end when
// the lifecycle service owns a READY backend, and must return typed errors
// when it does not.
int test_apply_remove_via_lifecycle_only(rac_model_registry_handle_t registry) {
    reset_environment();

    // Lifecycle not ready → COMPONENT_NOT_READY surfaced on the typed result.
    runanywhere::v1::LoRAApplyRequest precheck;
    precheck.set_request_id("precheck");
    auto* precheck_adapter = precheck.add_adapters();
    precheck_adapter->set_adapter_path("/tmp/precheck.gguf");
    std::vector<uint8_t> precheck_bytes;
    CHECK(serialize(precheck, &precheck_bytes), "precheck request serializes");

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_lora_apply_proto(precheck_bytes.data(), precheck_bytes.size(), &out);
    runanywhere::v1::LoRAApplyResult precheck_result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &precheck_result),
          "apply without lifecycle returns typed LoRAApplyResult");
    CHECK(!precheck_result.success(), "apply without lifecycle is unsuccessful");
    CHECK(precheck_result.error_code() == RAC_ERROR_COMPONENT_NOT_READY,
          "apply without lifecycle reports COMPONENT_NOT_READY");
    CHECK(precheck_result.error_message().find("LoRA service is not loaded") != std::string::npos,
          "apply without lifecycle explains missing service");
    rac_proto_buffer_free(&out);

    // Now load via lifecycle and exercise the full happy path.
    rac_llm_service_ops_t ops = make_ops(/*supports_lora=*/true);
    rac_engine_vtable_t vtable = make_vtable(&ops);
    CHECK(rac_plugin_register(&vtable) == RAC_SUCCESS, "lifecycle lora plugin registers");
    CHECK(register_test_llm(registry, build_test_llm("lifecycle.lora", "Lifecycle LoRA")),
          "lifecycle.lora model registers");
    CHECK(register_test_lora_adapter("primary", "lifecycle.lora"),
          "primary adapter registers for lifecycle.lora");
    CHECK(register_test_lora_adapter("secondary", "lifecycle.lora"),
          "secondary adapter registers for lifecycle.lora");
    CHECK(lifecycle_load(registry, "lifecycle.lora"), "lifecycle service loads lifecycle.lora");

    runanywhere::v1::LoRAApplyRequest apply;
    apply.set_request_id("apply-lifecycle");
    apply.set_replace_existing(true);
    auto* primary = apply.add_adapters();
    primary->set_adapter_id("primary");
    primary->set_adapter_path("/tmp/primary.gguf");
    primary->set_scale(0.25f);
    auto* secondary = apply.add_adapters();
    secondary->set_adapter_id("secondary");
    secondary->set_adapter_path("/tmp/secondary.gguf");
    secondary->set_scale(0.6f);
    std::vector<uint8_t> apply_bytes;
    CHECK(serialize(apply, &apply_bytes), "lifecycle apply request serializes");

    rac_proto_buffer_init(&out);
    rc = rac_lora_apply_proto(apply_bytes.data(), apply_bytes.size(), &out);
    runanywhere::v1::LoRAApplyResult apply_result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &apply_result),
          "lifecycle apply returns typed result");
    CHECK(apply_result.success(), "lifecycle apply succeeds");
    CHECK(apply_result.adapters_size() == 2, "lifecycle apply returns adapter info");
    CHECK(apply_result.request_id() == "apply-lifecycle", "lifecycle apply preserves request id");
    rac_proto_buffer_free(&out);

    runanywhere::v1::LoRAState state_request;
    std::vector<uint8_t> state_bytes;
    CHECK(serialize(state_request, &state_bytes), "state request serializes");

    rac_proto_buffer_init(&out);
    rc = rac_lora_state_proto(state_bytes.data(), state_bytes.size(), &out);
    runanywhere::v1::LoRAState state;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &state),
          "lifecycle state returns LoRAState after apply");
    CHECK(state.base_model_id() == "lifecycle.lora", "state carries lifecycle base model id");
    CHECK(state.has_active_adapters() && state.loaded_adapters_size() == 2,
          "state mirrors applied adapter count");
    CHECK(state_carries(state, "primary", "/tmp/primary.gguf"), "state contains primary adapter");
    CHECK(state_carries(state, "secondary", "/tmp/secondary.gguf"),
          "state contains secondary adapter");
    rac_proto_buffer_free(&out);

    // Remove by adapter id (resolved through the tracked-state map keyed on
    // the lifecycle backend impl pointer).
    runanywhere::v1::LoRARemoveRequest remove_by_id;
    remove_by_id.set_request_id("remove-primary");
    remove_by_id.add_adapter_ids("primary");
    std::vector<uint8_t> remove_by_id_bytes;
    CHECK(serialize(remove_by_id, &remove_by_id_bytes), "remove-by-id request serializes");

    rac_proto_buffer_init(&out);
    rc = rac_lora_remove_proto(remove_by_id_bytes.data(), remove_by_id_bytes.size(), &out);
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &state),
          "lifecycle remove-by-id returns LoRAState");
    CHECK(state.loaded_adapters_size() == 1, "remove-by-id leaves remaining adapter");
    CHECK(!state_carries(state, "primary", "/tmp/primary.gguf"), "remove-by-id removes primary");
    CHECK(state_carries(state, "secondary", "/tmp/secondary.gguf"), "remove-by-id keeps secondary");
    rac_proto_buffer_free(&out);

    // Remove by path then clear_all.
    runanywhere::v1::LoRARemoveRequest remove_by_path;
    remove_by_path.add_adapter_paths("/tmp/secondary.gguf");
    std::vector<uint8_t> remove_by_path_bytes;
    CHECK(serialize(remove_by_path, &remove_by_path_bytes), "remove-by-path request serializes");
    rac_proto_buffer_init(&out);
    rc = rac_lora_remove_proto(remove_by_path_bytes.data(), remove_by_path_bytes.size(), &out);
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &state),
          "lifecycle remove-by-path returns LoRAState");
    CHECK(state.loaded_adapters_size() == 0 && !state.has_active_adapters(),
          "remove-by-path empties state");
    rac_proto_buffer_free(&out);

    rac_proto_buffer_init(&out);
    rc = rac_lora_list_proto(state_bytes.data(), state_bytes.size(), &out);
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &state),
          "lifecycle list returns LoRAState after full remove");
    CHECK(state.loaded_adapters_size() == 0, "lifecycle list reflects no remaining adapters");
    CHECK(state.base_model_id() == "lifecycle.lora", "list still reports base model id");
    rac_proto_buffer_free(&out);

    reset_environment();
    return 0;
}

// After the lifecycle service unloads the model, the next proto call must
// fall back to the COMPONENT_NOT_READY path even though tracked state from
// the previous load is still around — this verifies that the lifecycle
// guard short-circuits before any state lookup.
int test_unload_reverts_to_not_ready(rac_model_registry_handle_t registry) {
    reset_environment();

    rac_llm_service_ops_t ops = make_ops(/*supports_lora=*/true);
    rac_engine_vtable_t vtable = make_vtable(&ops);
    CHECK(rac_plugin_register(&vtable) == RAC_SUCCESS, "unload-revert plugin registers");
    CHECK(register_test_llm(registry, build_test_llm("unload.lora", "Unload LoRA")),
          "unload.lora model registers");
    CHECK(register_test_lora_adapter("temp", "unload.lora"),
          "temp adapter registers for unload.lora");
    CHECK(lifecycle_load(registry, "unload.lora"), "lifecycle loads unload.lora");

    runanywhere::v1::LoRAApplyRequest apply;
    apply.set_request_id("apply-before-unload");
    auto* adapter = apply.add_adapters();
    adapter->set_adapter_id("temp");
    adapter->set_adapter_path("/tmp/temp.gguf");
    adapter->set_scale(1.0f);
    std::vector<uint8_t> bytes;
    CHECK(serialize(apply, &bytes), "apply-before-unload request serializes");

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_lora_apply_proto(bytes.data(), bytes.size(), &out);
    runanywhere::v1::LoRAApplyResult apply_result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &apply_result),
          "apply-before-unload returns LoRAApplyResult");
    CHECK(apply_result.success(), "apply-before-unload succeeds");
    rac_proto_buffer_free(&out);

    rac_model_lifecycle_reset();

    runanywhere::v1::LoRAState state_request;
    std::vector<uint8_t> state_bytes;
    CHECK(serialize(state_request, &state_bytes), "state request serializes for post-unload");

    rac_proto_buffer_init(&out);
    rc = rac_lora_state_proto(state_bytes.data(), state_bytes.size(), &out);
    runanywhere::v1::LoRAState state;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &state),
          "lifecycle state after unload returns typed LoRAState");
    CHECK(state.error_code() == RAC_ERROR_COMPONENT_NOT_READY,
          "lifecycle state after unload reports COMPONENT_NOT_READY");
    CHECK(state.error_message().find("LoRA service is not loaded") != std::string::npos,
          "lifecycle state after unload explains missing service");
    rac_proto_buffer_free(&out);

    reset_environment();
    return 0;
}

// Negative-case coverage for the v2 proto ABI. These pin the typed-error
// contract that platform SDKs rely on so future ABI changes cannot silently
// weaken the error path.

// NULL output buffer arguments must surface RAC_ERROR_NULL_POINTER directly
// (no typed result is producible without a buffer to copy into). NULL request
// bytes with non-zero size route through rac_proto_bytes_validate and surface
// a typed RAC_ERROR_DECODING_ERROR via the out buffer status.
int test_null_inputs_return_typed_errors() {
    reset_environment();

    // NULL out_result → RAC_ERROR_NULL_POINTER.
    CHECK(rac_lora_apply_proto(nullptr, 0, nullptr) == RAC_ERROR_NULL_POINTER,
          "apply with NULL out_result returns NULL_POINTER");
    CHECK(rac_lora_remove_proto(nullptr, 0, nullptr) == RAC_ERROR_NULL_POINTER,
          "remove with NULL out_state returns NULL_POINTER");
    CHECK(rac_lora_state_proto(nullptr, 0, nullptr) == RAC_ERROR_NULL_POINTER,
          "state with NULL out_state returns NULL_POINTER");
    CHECK(rac_lora_list_proto(nullptr, 0, nullptr) == RAC_ERROR_NULL_POINTER,
          "list with NULL out_state returns NULL_POINTER");
    CHECK(rac_lora_compatibility_proto(nullptr, 0, nullptr) == RAC_ERROR_NULL_POINTER,
          "compatibility with NULL out_result returns NULL_POINTER");

    // NULL bytes + non-zero size → DECODING_ERROR on the out buffer status.
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_lora_apply_proto(nullptr, 8, &out);
    CHECK(rc == RAC_ERROR_DECODING_ERROR,
          "apply with NULL bytes + non-zero size returns DECODING_ERROR");
    CHECK(out.status == RAC_ERROR_DECODING_ERROR,
          "apply NULL-bytes propagates DECODING_ERROR to out.status");
    rac_proto_buffer_free(&out);

    rac_proto_buffer_init(&out);
    rc = rac_lora_remove_proto(nullptr, 8, &out);
    CHECK(rc == RAC_ERROR_DECODING_ERROR,
          "remove with NULL bytes + non-zero size returns DECODING_ERROR");
    rac_proto_buffer_free(&out);

    reset_environment();
    return 0;
}

// Malformed proto bytes must surface a typed RAC_ERROR_DECODING_ERROR via the
// out buffer status — not crash and not silently succeed. Truncated payloads
// and arbitrary garbage both exercise the ParseFromArray failure branch in
// parse_message().
int test_malformed_proto_bytes_return_decoding_error() {
    reset_environment();

    // Bytes that are highly unlikely to parse as a valid LoRAApplyRequest:
    // 0xFF tags with bogus varint lengths.
    const uint8_t garbage[] = {0xFFu, 0xFFu, 0xFFu, 0xFFu, 0xFFu, 0xFFu, 0xFFu, 0xFFu};

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_lora_apply_proto(garbage, sizeof(garbage), &out);
    CHECK(rc == RAC_ERROR_DECODING_ERROR, "apply with malformed bytes returns DECODING_ERROR");
    CHECK(out.status == RAC_ERROR_DECODING_ERROR,
          "apply malformed-bytes propagates DECODING_ERROR to out.status");
    rac_proto_buffer_free(&out);

    rac_proto_buffer_init(&out);
    rc = rac_lora_remove_proto(garbage, sizeof(garbage), &out);
    CHECK(rc == RAC_ERROR_DECODING_ERROR, "remove with malformed bytes returns DECODING_ERROR");
    rac_proto_buffer_free(&out);

    rac_proto_buffer_init(&out);
    rc = rac_lora_list_proto(garbage, sizeof(garbage), &out);
    CHECK(rc == RAC_ERROR_DECODING_ERROR, "list with malformed bytes returns DECODING_ERROR");
    rac_proto_buffer_free(&out);

    rac_proto_buffer_init(&out);
    rc = rac_lora_state_proto(garbage, sizeof(garbage), &out);
    CHECK(rc == RAC_ERROR_DECODING_ERROR, "state with malformed bytes returns DECODING_ERROR");
    rac_proto_buffer_free(&out);

    reset_environment();
    return 0;
}

// All LoRA proto entry points must report COMPONENT_NOT_READY (via the typed
// result message, not the C return code) when no LLM has been loaded through
// the lifecycle service. This is the v2 "no caller-supplied handle" contract.
int test_apis_before_load_report_component_not_ready() {
    reset_environment();

    // Apply against the empty lifecycle — must return a typed
    // LoRAApplyResult with error_code == COMPONENT_NOT_READY.
    runanywhere::v1::LoRAApplyRequest apply;
    apply.set_request_id("apply-before-load");
    auto* adapter = apply.add_adapters();
    adapter->set_adapter_id("never");
    adapter->set_adapter_path("/tmp/never.gguf");
    std::vector<uint8_t> apply_bytes;
    CHECK(serialize(apply, &apply_bytes), "apply-before-load serializes");

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_lora_apply_proto(apply_bytes.data(), apply_bytes.size(), &out);
    runanywhere::v1::LoRAApplyResult apply_result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &apply_result),
          "apply-before-load returns typed LoRAApplyResult");
    CHECK(!apply_result.success(), "apply-before-load reports failure");
    CHECK(apply_result.error_code() == RAC_ERROR_COMPONENT_NOT_READY,
          "apply-before-load reports COMPONENT_NOT_READY");
    rac_proto_buffer_free(&out);

    // Remove (clear_all) against the empty lifecycle — must return a typed
    // LoRAState with error_code == COMPONENT_NOT_READY.
    runanywhere::v1::LoRARemoveRequest remove;
    remove.set_clear_all(true);
    std::vector<uint8_t> remove_bytes;
    CHECK(serialize(remove, &remove_bytes), "remove-before-load serializes");

    rac_proto_buffer_init(&out);
    rc = rac_lora_remove_proto(remove_bytes.data(), remove_bytes.size(), &out);
    runanywhere::v1::LoRAState remove_state;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &remove_state),
          "remove-before-load returns typed LoRAState");
    CHECK(remove_state.error_code() == RAC_ERROR_COMPONENT_NOT_READY,
          "remove-before-load reports COMPONENT_NOT_READY");
    rac_proto_buffer_free(&out);

    // list_proto and state_proto on a never-loaded lifecycle must surface the
    // same typed COMPONENT_NOT_READY on the LoRAState message.
    runanywhere::v1::LoRAState state_request;
    std::vector<uint8_t> state_bytes;
    CHECK(serialize(state_request, &state_bytes), "state request serializes");

    rac_proto_buffer_init(&out);
    rc = rac_lora_list_proto(state_bytes.data(), state_bytes.size(), &out);
    runanywhere::v1::LoRAState list_state;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &list_state),
          "list-before-load returns typed LoRAState");
    CHECK(list_state.error_code() == RAC_ERROR_COMPONENT_NOT_READY,
          "list-before-load reports COMPONENT_NOT_READY");
    rac_proto_buffer_free(&out);

    rac_proto_buffer_init(&out);
    rc = rac_lora_state_proto(state_bytes.data(), state_bytes.size(), &out);
    runanywhere::v1::LoRAState lora_state;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &lora_state),
          "state-before-load returns typed LoRAState");
    CHECK(lora_state.error_code() == RAC_ERROR_COMPONENT_NOT_READY,
          "state-before-load reports COMPONENT_NOT_READY");
    rac_proto_buffer_free(&out);

    reset_environment();
    return 0;
}

// Removing/clearing twice in a row must be idempotent — the second call
// returns a successful (error-free) LoRAState reflecting the same empty
// adapter set as the first. This guards against the ABI silently regressing
// to "double-unload returns INVALID_HANDLE" or similar.
int test_double_clear_is_idempotent(rac_model_registry_handle_t registry) {
    reset_environment();

    rac_llm_service_ops_t ops = make_ops(/*supports_lora=*/true);
    rac_engine_vtable_t vtable = make_vtable(&ops);
    CHECK(rac_plugin_register(&vtable) == RAC_SUCCESS, "double-clear plugin registers");
    CHECK(register_test_llm(registry, build_test_llm("double.clear", "Double Clear")),
          "double.clear model registers");
    CHECK(register_test_lora_adapter("only", "double.clear"),
          "only adapter registers for double.clear");
    CHECK(lifecycle_load(registry, "double.clear"), "lifecycle loads double.clear");

    // Apply one adapter so we have non-empty state to clear.
    runanywhere::v1::LoRAApplyRequest apply;
    apply.set_request_id("apply-pre-clear");
    auto* adapter = apply.add_adapters();
    adapter->set_adapter_id("only");
    adapter->set_adapter_path("/tmp/only.gguf");
    adapter->set_scale(0.5f);
    std::vector<uint8_t> apply_bytes;
    CHECK(serialize(apply, &apply_bytes), "apply-pre-clear serializes");

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_lora_apply_proto(apply_bytes.data(), apply_bytes.size(), &out);
    runanywhere::v1::LoRAApplyResult apply_result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &apply_result),
          "apply-pre-clear returns LoRAApplyResult");
    CHECK(apply_result.success(), "apply-pre-clear succeeds");
    rac_proto_buffer_free(&out);

    // First clear_all → state empties.
    runanywhere::v1::LoRARemoveRequest clear_request;
    clear_request.set_clear_all(true);
    std::vector<uint8_t> clear_bytes;
    CHECK(serialize(clear_request, &clear_bytes), "clear request serializes");

    rac_proto_buffer_init(&out);
    rc = rac_lora_remove_proto(clear_bytes.data(), clear_bytes.size(), &out);
    runanywhere::v1::LoRAState first_state;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &first_state),
          "first clear_all returns LoRAState");
    CHECK(first_state.error_code() == 0, "first clear_all carries no error");
    CHECK(first_state.loaded_adapters_size() == 0, "first clear_all empties tracked adapters");
    CHECK(!first_state.has_active_adapters(), "first clear_all sets has_active_adapters=false");
    rac_proto_buffer_free(&out);

    // Second clear_all on already-empty state must remain idempotent — no
    // error code, no adapters, no INVALID_HANDLE leak.
    rac_proto_buffer_init(&out);
    rc = rac_lora_remove_proto(clear_bytes.data(), clear_bytes.size(), &out);
    runanywhere::v1::LoRAState second_state;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &second_state),
          "second clear_all returns LoRAState");
    CHECK(second_state.error_code() == 0, "second clear_all carries no error (idempotent)");
    CHECK(second_state.loaded_adapters_size() == 0,
          "second clear_all leaves tracked adapters empty");
    CHECK(!second_state.has_active_adapters(), "second clear_all keeps has_active_adapters=false");
    CHECK(second_state.base_model_id() == "double.clear",
          "second clear_all preserves base model id");
    rac_proto_buffer_free(&out);

    reset_environment();
    return 0;
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

int main() {
    std::fprintf(stdout, "test_lora_proto_abi\n");
#if !defined(RAC_HAVE_PROTOBUF)
    std::fprintf(stdout, "  skip: LoRA proto ABI tests (no protobuf)\n");
    return 0;
#else
    rac_model_registry_handle_t registry = nullptr;
    if (rac_model_registry_create(&registry) != RAC_SUCCESS || registry == nullptr) {
        std::fprintf(stderr, "  FATAL: failed to create model registry\n");
        return 1;
    }

    try {
        test_apply_remove_via_lifecycle_only(registry);
        test_unload_reverts_to_not_ready(registry);
        test_null_inputs_return_typed_errors();
        test_malformed_proto_bytes_return_decoding_error();
        test_apis_before_load_report_component_not_ready();
        test_double_clear_is_idempotent(registry);
    } catch (const std::exception& e) {
        std::fprintf(stderr, "  FATAL: %s\n", e.what());
        reset_environment();
        rac_model_registry_destroy(registry);
        return 1;
    } catch (...) {
        std::fprintf(stderr, "  FATAL: unknown exception\n");
        reset_environment();
        rac_model_registry_destroy(registry);
        return 1;
    }

    reset_environment();
    rac_model_registry_destroy(registry);
    std::fprintf(stdout, "  %d checks, %d failures\n", test_count, fail_count);
    return fail_count == 0 ? 0 : 1;
#endif
}
