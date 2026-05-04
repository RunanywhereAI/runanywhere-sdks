/**
 * @file rac_hardware_profile.cpp
 * @brief Cross-platform hardware-capability detection.
 *
 * GAP 04 Phase 9 — see v2_gap_specs/GAP_04_ENGINE_ROUTER.md.
 *
 * Probe philosophy:
 *   - Be conservative. We'd rather miss a runtime than claim one that won't
 *     work and crash later.
 *   - One probe per runtime. Don't combine probes from unrelated runtimes
 *     (e.g. don't infer ANE from "we saw Metal + an A-series chip").
 *   - Honor `RAC_FORCE_RUNTIME=cpu` by short-circuiting to a CPU-only profile.
 */

#include "rac/router/rac_hardware_profile.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <optional>

#if defined(__APPLE__)
  #include <sys/sysctl.h>
  #include <TargetConditionals.h>
#endif

#if defined(__linux__) || defined(__ANDROID__)
  #include <dlfcn.h>
  #include <unistd.h>
  #include <sys/stat.h>
  #include <sys/sysinfo.h>
#endif

#if defined(__ANDROID__)
  #include <sys/system_properties.h>
#endif

#if defined(_WIN32)
  #include <windows.h>
  #include <sysinfoapi.h>
#endif

namespace rac {
namespace router {

namespace {

bool env_force_cpu() {
    const char* v = std::getenv("RAC_FORCE_RUNTIME");
    return v != nullptr && std::strcmp(v, "cpu") == 0;
}

#if defined(__APPLE__)
std::string sysctl_str(const char* name) {
    char buf[128] = {};
    size_t len = sizeof(buf) - 1;
    if (sysctlbyname(name, buf, &len, nullptr, 0) != 0) return {};
    return std::string(buf, len);
}

uint64_t sysctl_u64(const char* name) {
    uint64_t v = 0;
    size_t   sz = sizeof(v);
    if (sysctlbyname(name, &v, &sz, nullptr, 0) != 0) return 0;
    return v;
}

/** "M1 Pro" / "A17 Pro" — parsed loosely from `hw.machine` + `machdep.cpu.brand_string`. */
std::string detect_apple_chip_gen() {
    std::string brand = sysctl_str("machdep.cpu.brand_string");
    if (brand.find("Apple ") == 0) {
        return brand.substr(6);  /* strip "Apple " */
    }
    /* iOS: hw.machine like "iPhone16,1" — leave parsing to GAP-04 follow-up;
     * absence is fine, the router falls back to has_ane=false. */
    return {};
}

/** Coarse filter: any 2020+ Apple Silicon (M-series) and A11+ are ANE-capable. */
bool ane_supported(const std::string& chip) {
    if (chip.empty()) return false;
    /* Conservative whitelist: M1/M2/M3/M4 + their Pro/Max/Ultra variants,
     * plus A14+ on iOS. */
    if (chip.rfind("M", 0) == 0 && chip.size() >= 2 &&
        (chip[1] == '1' || chip[1] == '2' || chip[1] == '3' || chip[1] == '4')) {
        return true;
    }
    return false;
}
#endif  /* __APPLE__ */

#if defined(__linux__) && !defined(__ANDROID__)
bool detect_cuda_linux() {
    /* Two AND-gated probes: device node present + driver lib loadable. */
    struct stat st{};
    if (stat("/dev/nvidiactl", &st) != 0) return false;
    void* h = dlopen("libcuda.so.1", RTLD_LAZY | RTLD_LOCAL);
    if (h == nullptr) return false;
    dlclose(h);
    return true;
}
bool detect_vulkan_linux() {
    void* h = dlopen("libvulkan.so.1", RTLD_LAZY | RTLD_LOCAL);
    if (h == nullptr) return false;
    dlclose(h);
    return true;
}
#endif

#if defined(__ANDROID__)
std::string android_property(const char* key) {
    char buf[PROP_VALUE_MAX] = {};
    if (__system_property_get(key, buf) <= 0) return {};
    return std::string(buf);
}
bool detect_qnn_android() {
    /* Combined probe: the Hexagon runtime libs AND the FastRPC device node. */
    struct stat st{};
    if (stat("/dev/fastrpc-adsp", &st) != 0 &&
        stat("/dev/fastrpc-cdsp", &st) != 0) return false;
    void* h = dlopen("libQnnHtp.so", RTLD_LAZY | RTLD_LOCAL);
    if (h == nullptr) return false;
    dlclose(h);
    return true;
}
bool detect_nnapi_android() {
    void* h = dlopen("libneuralnetworks.so", RTLD_LAZY | RTLD_LOCAL);
    if (h == nullptr) return false;
    dlclose(h);
    return true;
}
#endif

std::size_t detect_total_ram() {
#if defined(__APPLE__)
    return static_cast<std::size_t>(sysctl_u64("hw.memsize"));
#elif defined(__linux__) || defined(__ANDROID__)
    struct sysinfo si{};
    if (sysinfo(&si) != 0) return 0;
    return static_cast<std::size_t>(si.totalram) * static_cast<std::size_t>(si.mem_unit);
#elif defined(_WIN32)
    MEMORYSTATUSEX m;
    m.dwLength = sizeof(m);
    if (GlobalMemoryStatusEx(&m) == 0) return 0;
    return static_cast<std::size_t>(m.ullTotalPhys);
#else
    return 0;
#endif
}

}  // namespace

HardwareProfile HardwareProfile::detect() {
    HardwareProfile p{};

    if (env_force_cpu()) {
        p.cpu_vendor = CpuVendor::Other;
        p.total_ram_bytes = detect_total_ram();
        return p;  /* All has_* stay false. */
    }

    p.total_ram_bytes = detect_total_ram();

#if defined(__APPLE__)
    p.cpu_vendor      = CpuVendor::Apple;
    p.gpu_vendor      = GpuVendor::Apple;
    p.apple_chip_gen  = detect_apple_chip_gen();
    p.has_metal       = true;
    p.has_coreml      = true;
    p.has_ane         = ane_supported(p.apple_chip_gen);
#elif defined(__ANDROID__)
    {
        std::string vendor = android_property("ro.hardware");
        if (vendor.find("qcom") != std::string::npos ||
            vendor.find("kona") != std::string::npos ||
            vendor.find("sm")   == 0) {
            p.cpu_vendor = CpuVendor::Qualcomm;
        } else {
            p.cpu_vendor = CpuVendor::Arm;
        }
        p.has_qnn   = detect_qnn_android();
        p.has_nnapi = detect_nnapi_android();
    }
#elif defined(__linux__)
    p.cpu_vendor   = CpuVendor::Other;  /* could parse /proc/cpuinfo for Intel/Amd */
    p.has_cuda     = detect_cuda_linux();
    p.has_vulkan   = detect_vulkan_linux();
    if (p.has_cuda) p.gpu_vendor = GpuVendor::Nvidia;
#elif defined(__EMSCRIPTEN__)
    /* WebGPU detection happens in JS land; the Emscripten-built host sets
     * has_webgpu via a JS shim that calls back into HardwareProfile::refresh()
     * (out of scope for GAP 04 Phase 9 — left false here). */
    p.has_webgpu = false;
#elif defined(_WIN32)
    p.cpu_vendor = CpuVendor::Other;
    /* CUDA / Vulkan probing on Windows requires LoadLibrary("nvcuda.dll") /
     * "vulkan-1.dll"; left for a follow-up since main has no Windows
     * build today. */
#endif

    return p;
}

namespace {
std::mutex g_cache_mu;
std::optional<HardwareProfile> g_cached;
}  // namespace

const HardwareProfile& HardwareProfile::cached() {
    std::lock_guard<std::mutex> lock(g_cache_mu);
    if (!g_cached.has_value()) {
        g_cached = HardwareProfile::detect();
    }
    return *g_cached;
}

void HardwareProfile::refresh() {
    std::lock_guard<std::mutex> lock(g_cache_mu);
    g_cached.reset();
}

bool HardwareProfile::supports_runtime(rac_runtime_id_t r) const {
    switch (r) {
        case RAC_RUNTIME_CPU:       return true;  /* always available */
        case RAC_RUNTIME_ONNXRT:    return true;  /* host runtime; EP selection happens inside ORT */
        case RAC_RUNTIME_METAL:     return has_metal;
        case RAC_RUNTIME_COREML:    return has_coreml;
        case RAC_RUNTIME_ANE:       return has_ane;
        case RAC_RUNTIME_CUDA:      return has_cuda;
        case RAC_RUNTIME_VULKAN:    return has_vulkan;
        case RAC_RUNTIME_QNN:       return has_qnn;
        case RAC_RUNTIME_NNAPI:     return has_nnapi;
        case RAC_RUNTIME_WEBGPU:    return has_webgpu;
        case RAC_RUNTIME_WASM_SIMD: return false;  /* compile-time only */
        default:                    return false;
    }
}

}  // namespace router
}  // namespace rac
