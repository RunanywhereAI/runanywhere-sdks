/**
 * @file rac_hardware.cpp
 * @brief Hardware capability detection implementation.
 *
 * Compile-time checks for SIMD feature flags (via __has_include /
 * preprocessor macros set by the build system), then a small amount of
 * runtime probing for counts (logical cores, GPU memory).
 *
 * Never throws; if a probe fails (e.g. sysctl on a minimal Linux), the
 * corresponding field is left at 0 / RAC_FALSE and the caller gets a
 * partial report instead of an error.
 */

#include "rac/core/rac_hardware.h"

#include <cstdio>
#include <cstring>
#include <string>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"

// ---- Platform includes for probing ---------------------------------------
#if defined(__APPLE__)
#include <TargetConditionals.h>
#include <sys/sysctl.h>
#include <unistd.h>
#endif

#if defined(__linux__) || defined(__ANDROID__)
#include <unistd.h>
#endif

#if defined(_WIN32)
#include <windows.h>
#include <sysinfoapi.h>
#endif

// ---- SIMD detection helpers ---------------------------------------------
// These are compile-time constants by design. Runtime CPUID probing would
// be needed to say "binary supports AVX2 but running CPU doesn't" on x86;
// today we report what the binary was compiled with.

namespace {

constexpr rac_bool_t kHasNeon =
#if defined(__ARM_NEON) || defined(__ARM_NEON__) || defined(__aarch64__)
    RAC_TRUE;
#else
    RAC_FALSE;
#endif

constexpr rac_bool_t kHasSSE42 =
#if defined(__SSE4_2__)
    RAC_TRUE;
#else
    RAC_FALSE;
#endif

constexpr rac_bool_t kHasAVX =
#if defined(__AVX__)
    RAC_TRUE;
#else
    RAC_FALSE;
#endif

constexpr rac_bool_t kHasAVX2 =
#if defined(__AVX2__)
    RAC_TRUE;
#else
    RAC_FALSE;
#endif

constexpr rac_bool_t kHasAVX512 =
#if defined(__AVX512F__) || defined(__AVX512BW__) || defined(__AVX512VL__)
    RAC_TRUE;
#else
    RAC_FALSE;
#endif

constexpr rac_bool_t kHasMetal =
#if defined(__APPLE__) && (defined(GGML_USE_METAL) || defined(RAC_ENABLE_METAL))
    RAC_TRUE;
#else
    RAC_FALSE;
#endif

constexpr rac_bool_t kHasCUDA =
#if defined(GGML_USE_CUDA) || defined(RAC_ENABLE_CUDA)
    RAC_TRUE;
#else
    RAC_FALSE;
#endif

constexpr rac_bool_t kHasVulkan =
#if defined(GGML_USE_VULKAN) || defined(RAC_ENABLE_VULKAN)
    RAC_TRUE;
#else
    RAC_FALSE;
#endif

constexpr rac_bool_t kHasOpenCL =
#if defined(GGML_USE_OPENCL) || defined(RAC_ENABLE_OPENCL)
    RAC_TRUE;
#else
    RAC_FALSE;
#endif

constexpr rac_bool_t kHasWebGPU =
#if defined(__EMSCRIPTEN__) && defined(RAC_WASM_WEBGPU)
    RAC_TRUE;
#else
    RAC_FALSE;
#endif

constexpr rac_bool_t kHasANE =
#if defined(__APPLE__)
    // Apple Silicon and A-series from A11 onward ship the Neural Engine;
    // Core ML dispatches to it automatically. We can't cheaply introspect
    // "is ANE actually present" - it effectively is on every modern Apple
    // target commons builds for, so we trust the target.
    RAC_TRUE;
#else
    RAC_FALSE;
#endif

constexpr rac_bool_t kHasQNN =
#if defined(RAC_ENABLE_QNN)
    RAC_TRUE;
#else
    RAC_FALSE;
#endif

constexpr rac_bool_t kHasGenio =
#if defined(RAC_ENABLE_GENIO)
    RAC_TRUE;
#else
    RAC_FALSE;
#endif

constexpr rac_bool_t kIsAppleSilicon =
#if defined(__APPLE__) && defined(__aarch64__)
    RAC_TRUE;
#else
    RAC_FALSE;
#endif

constexpr rac_bool_t kIsIosSimulator =
#if defined(__APPLE__) && TARGET_OS_SIMULATOR
    RAC_TRUE;
#else
    RAC_FALSE;
#endif

int32_t probe_logical_cpus() {
#if defined(_WIN32)
    SYSTEM_INFO si;
    GetSystemInfo(&si);
    return static_cast<int32_t>(si.dwNumberOfProcessors);
#else
    long n = sysconf(_SC_NPROCESSORS_ONLN);
    return n > 0 ? static_cast<int32_t>(n) : 0;
#endif
}

int32_t probe_physical_cpus() {
#if defined(__APPLE__)
    int32_t count = 0;
    size_t size = sizeof(count);
    if (sysctlbyname("hw.physicalcpu", &count, &size, nullptr, 0) == 0) {
        return count;
    }
    return 0;
#else
    // On Linux the physical count requires parsing /proc/cpuinfo which is
    // messy; fall back to logical count. Accurate-enough for our purposes
    // (used for thread pool sizing hints).
    return probe_logical_cpus();
#endif
}

int64_t probe_total_gpu_memory_mb() {
    // Cheap probes only; not a goal to be exhaustive.
#if defined(__APPLE__) && defined(__aarch64__)
    // Apple Silicon is unified memory: GPU can access up to ~75% of RAM.
    // Estimate from hw.memsize.
    int64_t ram_bytes = 0;
    size_t size = sizeof(ram_bytes);
    if (sysctlbyname("hw.memsize", &ram_bytes, &size, nullptr, 0) == 0) {
        return (ram_bytes / (1024 * 1024)) * 3 / 4;
    }
#endif
    return 0;  // Unknown / not probed.
}

}  // namespace

extern "C" {

rac_result_t rac_hardware_query_capabilities(rac_hardware_report_t* out_report) {
    if (out_report == nullptr) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    if (out_report->version != RAC_HARDWARE_REPORT_V1) {
        RAC_LOG_ERROR("Hardware",
                      "Report struct version mismatch: caller expects %u, "
                      "runtime supports %u. Refusing to fill struct.",
                      out_report->version, (unsigned)RAC_HARDWARE_REPORT_V1);
        return RAC_ERROR_BACKEND_INCOMPATIBLE_VERSION;
    }

    out_report->has_neon          = kHasNeon;
    out_report->has_sse42         = kHasSSE42;
    out_report->has_avx           = kHasAVX;
    out_report->has_avx2          = kHasAVX2;
    out_report->has_avx512        = kHasAVX512;
    out_report->num_logical_cpus  = probe_logical_cpus();
    out_report->num_physical_cpus = probe_physical_cpus();

    out_report->has_metal         = kHasMetal;
    out_report->has_cuda          = kHasCUDA;
    out_report->has_vulkan        = kHasVulkan;
    out_report->has_opencl        = kHasOpenCL;
    out_report->has_webgpu        = kHasWebGPU;
    out_report->total_gpu_memory_mb = probe_total_gpu_memory_mb();

    out_report->has_ane           = kHasANE;
    out_report->has_qnn           = kHasQNN;
    out_report->has_genio         = kHasGenio;

    out_report->is_apple_silicon   = kIsAppleSilicon;
    out_report->is_ios_simulator   = kIsIosSimulator;
    out_report->is_android_emulator = RAC_FALSE;  // TODO: detect via ro.kernel.qemu

    std::memset(out_report->_reserved, 0, sizeof(out_report->_reserved));
    return RAC_SUCCESS;
}

char* rac_hardware_format_report(const rac_hardware_report_t* report) {
    if (report == nullptr) {
        return rac_strdup("(null hardware report)");
    }
    std::string s;
    char buf[512];

    std::snprintf(buf, sizeof(buf),
                  "Hardware capabilities (version %u):\n"
                  "  CPU: logical=%d physical=%d\n"
                  "  SIMD: neon=%d sse42=%d avx=%d avx2=%d avx512=%d\n"
                  "  GPU: metal=%d cuda=%d vulkan=%d opencl=%d webgpu=%d mem_mb=%lld\n"
                  "  NPU: ane=%d qnn=%d genio=%d\n"
                  "  Platform: apple_silicon=%d ios_simulator=%d android_emulator=%d\n",
                  report->version,
                  report->num_logical_cpus, report->num_physical_cpus,
                  (int)report->has_neon, (int)report->has_sse42,
                  (int)report->has_avx, (int)report->has_avx2, (int)report->has_avx512,
                  (int)report->has_metal, (int)report->has_cuda,
                  (int)report->has_vulkan, (int)report->has_opencl, (int)report->has_webgpu,
                  (long long)report->total_gpu_memory_mb,
                  (int)report->has_ane, (int)report->has_qnn, (int)report->has_genio,
                  (int)report->is_apple_silicon, (int)report->is_ios_simulator,
                  (int)report->is_android_emulator);
    s += buf;
    return rac_strdup(s.c_str());
}

}  // extern "C"
