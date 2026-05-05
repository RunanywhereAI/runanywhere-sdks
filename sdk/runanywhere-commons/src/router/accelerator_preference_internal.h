/**
 * @file accelerator_preference_internal.h
 * @brief Internal accessor for the global accelerator preference.
 *
 * `rac_hardware_set_accelerator_preference` (see `rac_hardware_abi.h`) stores
 * a single process-wide integer that downstream routing uses as an additional
 * scoring hint.  This header exposes that value to the engine router TU
 * without making it part of the public C ABI — the preference is an internal
 * routing knob, not a stable external contract.
 *
 * Values follow `runanywhere.v1.AccelerationPreference` (hardware_profile.proto):
 *   0 = UNSPECIFIED (treated as no hint)
 *   1 = AUTO        (no hint — let priority/profile decide)
 *   2 = CPU
 *   3 = GPU
 *   4 = NPU
 *
 * The setter currently validates 0..3, matching historic SDK usage; callers
 * that pass NPU=4 are clamped by the ABI validator and never reach here.
 */

#ifndef RAC_ROUTER_ACCELERATOR_PREFERENCE_INTERNAL_H
#define RAC_ROUTER_ACCELERATOR_PREFERENCE_INTERNAL_H

namespace rac {
namespace router {
namespace internal {

/** Get the current process-wide accelerator preference (thread-safe read). */
int get_accelerator_preference();

}  // namespace internal
}  // namespace router
}  // namespace rac

#endif  // RAC_ROUTER_ACCELERATOR_PREFERENCE_INTERNAL_H
