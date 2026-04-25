/**
 * @file rac_hardware_profile.h
 * @brief Detected hardware capabilities of the host process.
 *
 * GAP 04 Phase 9 — see v2_gap_specs/GAP_04_ENGINE_ROUTER.md.
 *
 * The router uses this profile to score plugins against the caller's
 * `rac_routing_hints_t::preferred_runtime`. Detection is performed once on
 * first call to `cached()` and memoized for the process's lifetime; callers
 * that need a re-scan (e.g. external GPU hot-plug) call `refresh()` explicitly.
 *
 * Detection probes are deliberately conservative — we prefer false-negatives
 * (skip a runtime we can't prove is alive) over false-positives (claim a
 * runtime that won't actually serve a request). The `RAC_FORCE_RUNTIME=cpu`
 * environment variable forces a CPU-only profile for CI / debug.
 */

#ifndef RAC_ROUTER_HARDWARE_PROFILE_H
#define RAC_ROUTER_HARDWARE_PROFILE_H

#include <cstddef>
#include <cstdint>
#include <string>

#include "rac/plugin/rac_primitive.h"   /* rac_runtime_id_t */

namespace rac {
namespace router {

enum class CpuVendor : uint8_t { Unknown = 0, Intel, Amd, Apple, Arm, Qualcomm, Other };
enum class GpuVendor : uint8_t { Unknown = 0, Apple, Nvidia, Amd, Intel, Adreno, Mali, PowerVR, Other };

/**
 * Snapshot of the host's detected accelerators, memory, and identifying
 * information. `detect()` is the heavy probe; `cached()` returns the memoized
 * result; `refresh()` re-runs detection (call sparingly).
 */
struct HardwareProfile {
    CpuVendor cpu_vendor = CpuVendor::Unknown;
    GpuVendor gpu_vendor = GpuVendor::Unknown;

    /** Bytes of physical RAM as reported by the OS. 0 = unknown. */
    std::size_t total_ram_bytes = 0;

    /** Apple chip generation if `cpu_vendor == Apple` (e.g. "M1", "M2 Pro",
     *  "A17 Pro", or "" when not detected). Empty for non-Apple hosts. */
    std::string apple_chip_gen;

    /** Per-runtime availability flags. The router consults the matching
     *  bool for the caller's `preferred_runtime`. */
    bool has_metal   = false;   /**< Apple Metal compute. */
    bool has_ane     = false;   /**< Apple Neural Engine — only when chip is known good. */
    bool has_coreml  = false;   /**< Apple Core ML runtime present. */
    bool has_cuda    = false;   /**< NVIDIA CUDA driver + at least 1 device node. */
    bool has_vulkan  = false;   /**< Vulkan loader + at least 1 physical device. */
    bool has_qnn     = false;   /**< Qualcomm Hexagon (libQnnHtp + /dev/fastrpc-adsp). */
    bool has_nnapi   = false;   /**< Android NNAPI (API level >= 27). */
    bool has_webgpu  = false;   /**< Browser WebGPU adapter present (Emscripten only). */

    /**
     * Heavy probe: shells out to platform APIs (sysctl, /proc, dlopen on
     * libcuda/libQnnHtp, etc.). Honors `RAC_FORCE_RUNTIME=cpu` env var by
     * returning a CPU-only profile.
     */
    static HardwareProfile detect();

    /**
     * Memoized accessor. The first call performs `detect()`; subsequent
     * callers receive the same const-ref. Thread-safe.
     */
    static const HardwareProfile& cached();

    /**
     * Drop the memoized cache so the next `cached()` call re-runs `detect()`.
     * Useful for tests + when the host knows the hardware topology changed.
     */
    static void refresh();

    /**
     * True if the profile would say "yes" to a plugin declaring this runtime.
     * Convenience method for the router scoring code.
     */
    bool supports_runtime(rac_runtime_id_t r) const;
};

}  // namespace router
}  // namespace rac

#endif  /* RAC_ROUTER_HARDWARE_PROFILE_H */
