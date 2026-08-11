/**
 * @file rac_device_facts.h
 * @brief Canonical device-fact derivations shared by every platform SDK.
 *
 * Platforms supply OS-readable strings and measurements (SoC manufacturer /
 * model, Build.HARDWARE, /proc/cpuinfo Hardware, per-core max frequencies,
 * probed available RAM). Commons owns the classification policy:
 *
 *   - four-tier chip-name resolution
 *   - GPU vendor / family from SoC + chip strings
 *   - NPU-presence heuristic
 *   - P/E core split from sysfs max-frequency samples
 *   - available-memory coalesce (real probe or UNKNOWN=0 — never total/2)
 *
 * These are pure functions: no syscalls, no adapter callbacks. Platform SDKs
 * gather inputs and call these; they must not re-derive the policy locally.
 */

#ifndef RAC_DEVICE_FACTS_H
#define RAC_DEVICE_FACTS_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Resolve a human-readable chip name from platform-supplied candidates.
 *
 * Tier order (first usable wins):
 *   1. soc_model, optionally prefixed with soc_manufacturer when the model
 *      does not already contain the manufacturer (e.g. "Qualcomm SM8750")
 *   2. build_hardware, rejecting bare vendor tokens like "qcom"
 *   3. cpuinfo_hardware, same bare-vendor reject
 *   4. architecture_fallback (e.g. "arm64-v8a")
 *
 * Empty / NULL / "unknown" inputs are skipped. On success writes a
 * NUL-terminated UTF-8 string into @p out.
 *
 * @return RAC_SUCCESS, RAC_ERROR_NULL_POINTER if @p out is NULL,
 *         RAC_ERROR_BUFFER_TOO_SMALL if @p out_size < 2,
 *         RAC_ERROR_NOT_FOUND if every tier is empty.
 */
RAC_API rac_result_t rac_device_resolve_chip_name(const char* soc_manufacturer,
                                                   const char* soc_model,
                                                   const char* build_hardware,
                                                   const char* cpuinfo_hardware,
                                                   const char* architecture_fallback,
                                                   char* out, size_t out_size);

/**
 * Classify GPU family from SoC manufacturer/model and/or an already-resolved
 * chip name. Writes a lowercase family token into @p out:
 *   "adreno" | "mali" | "xclipse" | "immortalis" | "apple" | "intel" |
 *   "nvidia" | "unknown"
 *
 * Manufacturer gates (API-31-style) take precedence over chip-name substrings
 * when manufacturer is non-empty. Exynos 2200+ → xclipse; Dimensity 9xxx →
 * immortalis; otherwise Mali for Samsung/MediaTek/Google/HiSilicon.
 *
 * @return RAC_SUCCESS (always writes at least "unknown"),
 *         RAC_ERROR_NULL_POINTER / RAC_ERROR_BUFFER_TOO_SMALL on bad buffers.
 */
RAC_API rac_result_t rac_device_classify_gpu_family(const char* soc_manufacturer,
                                                    const char* soc_model,
                                                    const char* chip_name, char* out,
                                                    size_t out_size);

/**
 * Heuristic NPU presence from SoC + chip strings.
 *
 * True for Qualcomm SM8/SM7/QCM, Google Tensor / GS1xx / GS2xx, MediaTek
 * Dimensity, and Exynos / s5e 2xxx parts. False when nothing matches —
 * never invents presence for unknown silicon.
 */
RAC_API rac_bool_t rac_device_heuristic_has_npu(const char* soc_manufacturer,
                                                const char* soc_model,
                                                const char* chip_name);

/**
 * Split logical cores into performance / efficiency from per-core max
 * frequency samples (e.g. cpuinfo_max_freq from sysfs, any unit as long as
 * consistent). Cores at the shared maximum count as performance; the rest
 * are efficiency.
 *
 * When @p max_freqs is NULL, @p count is 0, or any sample is missing/non-
 * positive, both outputs are set to 0 (UNKNOWN split). Never invents a
 * half/half split.
 *
 * @return RAC_SUCCESS, or RAC_ERROR_NULL_POINTER if an out pointer is NULL.
 */
RAC_API rac_result_t rac_device_split_performance_cores(const int64_t* max_freqs,
                                                        size_t count,
                                                        int32_t* out_performance,
                                                        int32_t* out_efficiency);

/**
 * Coalesce a probed available-RAM reading to the DeviceInfo contract:
 *   probed > 0  → return probed
 *   otherwise   → return 0 (UNKNOWN)
 *
 * Callers MUST NOT substitute total/2 or any other fabrication. Consumers of
 * DeviceInfo.available_memory_bytes / rac_memory_info_t.available_bytes treat
 * 0 as unknown, never as "no memory left".
 */
RAC_API int64_t rac_device_coalesce_available_memory(int64_t probed_available_bytes);

#ifdef __cplusplus
}
#endif

#endif /* RAC_DEVICE_FACTS_H */
