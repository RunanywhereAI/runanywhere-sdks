/**
 * @file test_platform_bridge.cpp
 * @brief Every platform value a binding supplies must reach the wire intact.
 *
 * Each SDK (Swift, Kotlin, Flutter, React Native, Web, Electron, Python, rcli)
 * collects device and app facts from its own platform APIs and hands them to
 * commons through two flat C structs: rac_device_callbacks_t.get_device_info for
 * hardware/OS, and rac_sdk_set_client_info for app identity. Everything after
 * that point is shared C++.
 *
 * That makes this the one test that covers the platform half for ALL bindings:
 * it installs a fake adapter whose every field carries a distinct sentinel, then
 * asserts each sentinel arrives under the right key in the JSON commons actually
 * sends. A binding bug then shows up as "my value never reached the struct",
 * which its own suite can check, rather than as a silently missing column in a
 * database nobody is watching.
 *
 * It exists because that is precisely how these were lost before:
 *   - app_identifier / app_name / app_version were collected by every binding
 *     and never put on a telemetry event at all;
 *   - device_fingerprint carried a hardware-class hash instead of identity;
 *   - platform carried the binding name ("flutter", "react-native") instead of
 *     the OS.
 */

#include <cstdio>
#include <cstring>
#include <string>

#include "rac/infrastructure/device/rac_device_manager.h"
#include "rac/infrastructure/network/rac_client_info.h"
#include "rac/infrastructure/network/rac_environment.h"

static int g_checks = 0;
static int g_failures = 0;

#define CHECK(cond, msg)                                        \
    do {                                                        \
        ++g_checks;                                             \
        if (!(cond)) {                                          \
            ++g_failures;                                       \
            std::fprintf(stdout, "  FAIL: %s\n", (msg));        \
        }                                                       \
    } while (0)

static bool has(const std::string& haystack, const std::string& needle) {
    return haystack.find(needle) != std::string::npos;
}

// ---------------------------------------------------------------------------
// A stand-in for a platform SDK. Distinct sentinels per field so a value landing
// under the wrong key is a failure, not a coincidence.
// ---------------------------------------------------------------------------
namespace {

constexpr const char* kDeviceId = "11111111-2222-3333-4444-555555555555";
constexpr const char* kDeviceModel = "SentinelModel99";
constexpr const char* kDeviceName = "Sentinel Device Name";
constexpr const char* kPlatform = "macos";  // an OS family, never a binding name
constexpr const char* kOsVersion = "14.5.1";
constexpr const char* kFormFactor = "desktop";
constexpr const char* kArchitecture = "arm64";
constexpr const char* kChipName = "SentinelChip";
constexpr const char* kGpuFamily = "SentinelGPU";
constexpr const char* kHardwareClass = "aaaabbbbccccddddeeeeffff00001111"
                                      "22223333444455556666777788889999";

struct Capture {
    bool posted = false;
    std::string endpoint;
    std::string body;
};

void fake_get_device_info(rac_device_registration_info_t* out, void* /*user_data*/) {
    *out = {};
    out->device_id = kDeviceId;
    out->device_model = kDeviceModel;
    out->device_name = kDeviceName;
    out->platform = kPlatform;
    out->os_version = kOsVersion;
    out->form_factor = kFormFactor;
    out->architecture = kArchitecture;
    out->chip_name = kChipName;
    out->gpu_family = kGpuFamily;
    out->total_memory = 17179869184;  // 16 GiB
    out->available_memory = 8589934592;
    out->has_neural_engine = RAC_TRUE;
    out->neural_engine_cores = 16;
    out->core_count = 12;
    out->performance_cores = 8;
    out->efficiency_cores = 4;
    out->battery_level = -1.0;  // no battery on this form factor
    // Identity is the persistent per-install id; the hardware-class hash is a
    // separate attribute and must not be mistaken for it.
    out->device_fingerprint = kDeviceId;
    out->hardware_class_fingerprint = kHardwareClass;
}

const char* fake_get_device_id(void* /*user_data*/) {
    return kDeviceId;
}

rac_bool_t fake_is_registered(void* /*user_data*/) {
    return RAC_FALSE;  // force a registration so we can inspect the payload
}

void fake_set_registered(rac_bool_t /*registered*/, void* /*user_data*/) {}

rac_result_t fake_http_post(const char* endpoint, const char* json_body,
                            rac_bool_t /*requires_auth*/,
                            rac_device_http_response_t* out_response, void* user_data) {
    auto* cap = static_cast<Capture*>(user_data);
    cap->posted = true;
    cap->endpoint = endpoint != nullptr ? endpoint : "";
    cap->body = json_body != nullptr ? json_body : "";
    if (out_response != nullptr) {
        *out_response = {};
        out_response->status_code = 200;
    }
    return RAC_SUCCESS;
}

}  // namespace

int main() {
    std::fprintf(stdout, "test_platform_bridge\n");

    Capture cap;
    rac_device_callbacks_t callbacks = {};
    callbacks.get_device_info = fake_get_device_info;
    callbacks.get_device_id = fake_get_device_id;
    callbacks.is_registered = fake_is_registered;
    callbacks.set_registered = fake_set_registered;
    callbacks.http_post = fake_http_post;
    callbacks.user_data = &cap;

    CHECK(rac_device_manager_set_callbacks(&callbacks) == RAC_SUCCESS,
          "platform callbacks installed");

    // App identity comes through a separate struct, exactly as each binding
    // supplies it (Bundle.main, PackageManager, host-app options, ...).
    rac_client_info_t client = {};
    client.sdk_binding = "cli";
    client.app_identifier = "ai.runanywhere.sentinel";
    client.app_name = "Sentinel App";
    client.app_version = "9.8.7";
    client.app_build = "4242";
    client.locale = "en_US";
    client.timezone = "UTC";
    rac_sdk_set_client_info(&client);

    (void)rac_device_manager_register_if_needed(RAC_ENV_DEVELOPMENT, nullptr);

    CHECK(cap.posted, "registration was POSTed");
    if (!cap.posted) {
        std::fprintf(stdout, "  %d checks, %d failures\n", g_checks, g_failures);
        return 1;
    }

    // --- Hardware / OS facts survive the bridge ----------------------------
    CHECK(has(cap.body, kDeviceModel), "device_model reached the wire");
    CHECK(has(cap.body, kDeviceName), "device_name reached the wire");
    CHECK(has(cap.body, std::string("\"platform\":\"") + kPlatform + "\""),
          "platform reached the wire as an OS family");
    CHECK(has(cap.body, kOsVersion), "os_version reached the wire");
    CHECK(has(cap.body, kArchitecture), "architecture reached the wire");
    CHECK(has(cap.body, kChipName), "chip_name reached the wire");
    CHECK(has(cap.body, kGpuFamily), "gpu_family reached the wire");
    CHECK(has(cap.body, kFormFactor), "form_factor reached the wire");
    CHECK(has(cap.body, "17179869184"), "total_memory reached the wire");
    CHECK(has(cap.body, "\"core_count\":12"), "core_count reached the wire");
    CHECK(has(cap.body, "\"performance_cores\":8"), "performance_cores reached the wire");
    CHECK(has(cap.body, "\"efficiency_cores\":4"), "efficiency_cores reached the wire");
    CHECK(has(cap.body, "\"neural_engine_cores\":16"), "neural_engine_cores reached the wire");

    // --- Identity is identity, and the hardware hash is not ----------------
    CHECK(has(cap.body, std::string("\"device_fingerprint\":\"") + kDeviceId + "\""),
          "device_fingerprint carries the persistent id, not a hardware hash");
    CHECK(has(cap.body, kHardwareClass), "hardware_class_fingerprint reached the wire");
    CHECK(!has(cap.body, std::string("\"device_fingerprint\":\"") + kHardwareClass + "\""),
          "the hardware-class hash is never sent as identity");

    // --- App identity survives the bridge ----------------------------------
    CHECK(has(cap.body, "ai.runanywhere.sentinel"), "app_identifier reached the wire");
    CHECK(has(cap.body, "Sentinel App"), "app_name reached the wire");
    CHECK(has(cap.body, "9.8.7"), "app_version reached the wire");
    CHECK(has(cap.body, "\"sdk_binding\":\"cli\""), "sdk_binding reached the wire");

    rac_device_manager_clear_callbacks();

    std::fprintf(stdout, "  %d checks, %d failures\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
