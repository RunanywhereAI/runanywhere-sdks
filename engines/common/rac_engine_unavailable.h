#ifndef RUNANYWHERE_ENGINES_COMMON_ENGINE_UNAVAILABLE_H
#define RUNANYWHERE_ENGINES_COMMON_ENGINE_UNAVAILABLE_H

/**
 * @file rac_engine_unavailable.h
 * @brief Shared "compiled but not routable" engine-plugin shell.
 *
 * Several engine plugins ship a translation unit that is always *buildable*
 * but, on the current host / build flavor, must register without advertising
 * any primitive so the router can never select it:
 *
 *   - qhexrt — private Android NPU engine whose prebuilt archive may be absent.
 *   - coreml — Apple-only; its non-routable arm publishes nothing.
 *
 * Each of those hand-rolls the identical four-part shell:
 *   1. an empty / not-routable `rac_engine_manifest_t` (zero primitives /
 *      runtimes / formats, priority 0, `"<Name> [unavailable]"` display name);
 *   2. an all-NULL-ops `rac_engine_vtable_t` `.rodata` literal whose only live
 *      field besides `metadata` is `capability_check`;
 *   3. a 3-way `capability_check()` returning CAPABILITY_UNSUPPORTED when the
 *      platform is wrong, BACKEND_UNAVAILABLE when the engine/ops are absent,
 *      SUCCESS otherwise;
 *   4. `RAC_PLUGIN_ENTRY_DEF(<name>)` forwarding to
 *      `rac_engine_entry_with_manifest(&manifest, &vtable)`.
 *
 * This header collapses (1), (2) and (4) into one macro and provides an inline
 * helper for the *body* of (3). The engine keeps owning its own
 * `capability_check` function (so per-engine `#if` gating stays local and
 * flexible) — the macro only takes a pointer to it.
 *
 * ABI / layering notes:
 *   - C-compatible and `extern "C"`-safe: no C++-only constructs leak out of
 *     the macro expansion. The emitted vtable keeps the
 *     `extern "C" const rac_engine_vtable_t` contract and lives in `.rodata`
 *     (no runtime allocation), exactly like a hand-written entry.
 *   - The emitted vtable mirrors the real `rac_engine_vtable_t` slot count and
 *     order (10 active primitive slots + 7 reserved slots, all explicit NULL).
 *     If a future ABI bump promotes a reserved slot, the aggregate initializer
 *     here becomes a compile error — the same tripwire the hand-written entries
 *     rely on — forcing this header to be revisited in lockstep with the ABI.
 *   - This header lives in engines/common/ and is header-only; adopting it adds
 *     no new .cpp / CMake wiring.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * USAGE A — a plain always-unavailable stub (e.g. sample)
 *
 * The engine is never routable in-tree, so there is a single arm. Define the
 * capability_check with whatever `#if` gating the engine needs, then emit the
 * shell:
 *
 * @code
 *   namespace {
 *   rac_result_t sample_capability_check(void) {
 *       // Build-derived booleans for this engine's host/runtime gate.
 *       return rac_engine_unavailable_capability(
 *   #if defined(__ANDROID__)
 *           1,                          // platform_supported
 *   #else
 *           0,
 *   #endif
 *   #if defined(RAC_SAMPLE_BACKEND_AVAILABLE) && RAC_SAMPLE_BACKEND_AVAILABLE
 *           1                           // backend_present
 *   #else
 *           0
 *   #endif
 *       );
 *   }
 *   }  // namespace
 *
 *   RAC_ENGINE_UNAVAILABLE_PLUGIN(sample, "Sample Engine",
 *                                 sample_capability_check)
 * @endcode
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * USAGE B — an `#if`-gated real/stub engine (e.g. qhexrt)
 *
 * An engine that is a real plugin when its binary is linked and
 * a not-routable stub otherwise. The engine guards its real hand-written
 * manifest/vtable under the routable branch and uses this macro for the stub
 * branch, so both branches still expose the SAME `rac_plugin_entry_<name>`
 * symbol and the same all-NULL `.rodata` vtable contract on the stub side:
 *
 * @code
 *   #if defined(__ANDROID__) && defined(RAC_QHEXRT_ENGINE_AVAILABLE) && \
 *       RAC_QHEXRT_ENGINE_AVAILABLE
 *   #define RAC_QHEXRT_ROUTABLE 1
 *   #else
 *   #define RAC_QHEXRT_ROUTABLE 0
 *   #endif
 *
 *   static rac_result_t qhexrt_capability_check(void) {
 *       return rac_engine_unavailable_capability(
 *   #if defined(__ANDROID__)
 *           1,                          // platform_supported (Android only)
 *   #else
 *           0,
 *   #endif
 *   #if defined(RAC_QHEXRT_ENGINE_AVAILABLE) && RAC_QHEXRT_ENGINE_AVAILABLE
 *           1                           // backend_present (engine binary linked)
 *   #else
 *           0
 *   #endif
 *       );
 *   }
 *
 *   #if RAC_QHEXRT_ROUTABLE
 *       // ... real manifest + multi-primitive vtable + RAC_PLUGIN_ENTRY_DEF ...
 *   #else
 *       RAC_ENGINE_UNAVAILABLE_PLUGIN(qhexrt, "QHexRT", qhexrt_capability_check)
 *   #endif
 * @endcode
 *
 * Note the macro is invoked at the same scope a hand-written entry would be —
 * inside the file's `extern "C"` block (the macro itself does not open one), so
 * the emitted manifest/vtable/entry-fn all keep C linkage.
 */

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_engine_manifest.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Canonical 3-way capability decision shared by every unavailable shell.
 *
 * Engines pass their own `#if`-derived booleans (1/0):
 *   - @p platform_supported — is this OS/arch a target for the engine at all?
 *     (e.g. `__ANDROID__` for qhexrt, `__APPLE__` for coreml).
 *   - @p backend_present    — is the real engine implementation linked / wired
 *     on this build? (the QHexRT prebuilt archive, the generate path for coreml).
 *
 * Returns, in priority order:
 *   - `RAC_ERROR_CAPABILITY_UNSUPPORTED` when the platform itself is wrong —
 *     the registry treats this as a silent reject (no error log), which is the
 *     correct outcome for "this engine never runs here".
 *   - `RAC_ERROR_BACKEND_UNAVAILABLE`    when the platform is right but the
 *     engine implementation is absent (stub build).
 *   - `RAC_SUCCESS`                      when both hold (the engine's *routable*
 *     arm should be in effect; an all-NULL shell would never reach here).
 *
 * The platform check is evaluated first so a stub build on the wrong OS reports
 * UNSUPPORTED rather than UNAVAILABLE, matching the hand-written gates in
 * qhexrt / coreml.
 */
static inline rac_result_t rac_engine_unavailable_capability(int platform_supported,
                                                             int backend_present) {
    if (!platform_supported) {
        return RAC_ERROR_CAPABILITY_UNSUPPORTED;
    }
    if (!backend_present) {
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }
    return RAC_SUCCESS;
}

/**
 * @brief Emit the not-routable `rac_engine_manifest_t` for an unavailable shell.
 *
 * Internal building block of `RAC_ENGINE_UNAVAILABLE_PLUGIN`; usable on its own
 * if an engine wants the shared empty manifest but a bespoke vtable/entry. The
 * manifest advertises nothing: zero primitives / runtimes / formats, priority 0,
 * private availability, and a `"<display> [unavailable]"` name so logs/UI make
 * the stub state obvious. The symbol is `static const` (.rodata, internal
 * linkage) — one per TU, keyed by @p name.
 */
#define RAC_ENGINE_UNAVAILABLE_MANIFEST_DEF(name, display)                          \
    static const rac_engine_manifest_t k_##name##_unavailable_manifest = {          \
        /* .name             */ #name,                                              \
        /* .display_name      */ display " [unavailable]",                          \
        /* .version           */ RAC_NULL,                                          \
        /* .package_owner      */ "runanywhere",                                    \
        /* .package_name       */ RAC_NULL,                                         \
        /* .availability        */ RAC_ENGINE_AVAILABILITY_PRIVATE,                 \
        /* .priority             */ 0,                                              \
        /* .capability_flags      */ 0,                                             \
        /* .primitives             */ RAC_NULL,                                     \
        /* .primitives_count         */ 0,                                          \
        /* .runtimes                   */ RAC_NULL,                                 \
        /* .runtimes_count               */ 0,                                      \
        /* .formats                       */ RAC_NULL,                              \
        /* .formats_count                   */ 0,                                   \
        /* .reserved_0                        */ 0,                                 \
        /* .reserved_1                         */ 0,                                \
    }

/**
 * @brief Emit the all-NULL-ops `rac_engine_vtable_t` for an unavailable shell.
 *
 * Internal building block of `RAC_ENGINE_UNAVAILABLE_PLUGIN`. Every primitive
 * and reserved slot is an explicit NULL — the registry reads that as "serves
 * nothing". The only live fields are `metadata` (projected from the matching
 * unavailable manifest) and `capability_check` (the engine-provided @p cap_fn).
 *
 * The literal mirrors the real `rac_engine_vtable_t` slot count/order: 10 active
 * primitive slots (llm/stt/tts/vad/embedding/vlm/diffusion/diarization/
 * segmentation/vocoder) + 7 reserved slots. A future reserved-slot promotion changes the struct and makes this
 * aggregate initializer a compile error — the intended tripwire.
 *
 * Emitted as `static const` `.rodata`; @p cap_fn must have C linkage so the
 * function-pointer field stays ABI-correct across the FFI boundary.
 */
#define RAC_ENGINE_UNAVAILABLE_VTABLE_DEF(name, cap_fn)                                      \
    static const rac_engine_vtable_t g_##name##_unavailable_vtable = {                       \
        /* metadata         */ RAC_ENGINE_METADATA_FROM_MANIFEST(                            \
            k_##name##_unavailable_manifest),                                                \
        /* capability_check */ (cap_fn),                                                     \
        /* on_unload        */ RAC_NULL,                                                     \
                                                                                            \
        /* llm_ops          */ RAC_NULL,                                                     \
        /* stt_ops          */ RAC_NULL,                                                     \
        /* tts_ops          */ RAC_NULL,                                                     \
        /* vad_ops          */ RAC_NULL,                                                     \
        /* embedding_ops    */ RAC_NULL,                                                     \
        /* vlm_ops          */ RAC_NULL,                                                     \
        /* diffusion_ops    */ RAC_NULL,                                                     \
        /* diarization_ops  */ RAC_NULL,                                                     \
        /* segmentation_ops */ RAC_NULL,                                                     \
        /* vocoder_ops      */ RAC_NULL,                                                     \
                                                                                            \
        /* reserved_slot_3..9 */                                                            \
        RAC_NULL, RAC_NULL, RAC_NULL, RAC_NULL,                                              \
        RAC_NULL, RAC_NULL, RAC_NULL,                                                        \
    }

/**
 * @brief Emit the complete not-routable plugin shell for engine @p name.
 *
 * Generates, all keyed by @p name:
 *   - `k_<name>_unavailable_manifest`  — empty / not-routable manifest;
 *   - `g_<name>_unavailable_vtable`    — all-NULL `.rodata` vtable whose
 *     `capability_check` is @p cap_fn;
 *   - `RAC_PLUGIN_ENTRY_DEF(<name>)`   — returns
 *     `rac_engine_entry_with_manifest(&manifest, &vtable)`.
 *
 * Parameters:
 *   @param name    bare engine identifier — token, not a string. Drives the
 *                  `manifest.name` (stringized), the generated symbol names, and
 *                  the `rac_plugin_entry_<name>` symbol. MUST match the engine's
 *                  registration name / library entry-name convention.
 *   @param display human-readable display name as a string literal (e.g.
 *                  "QHexRT"); `" [unavailable]"` is appended for
 *                  the manifest's `display_name`.
 *   @param cap_fn  the engine-owned `rac_result_t (*)(void)` capability_check.
 *                  Keeping it engine-supplied lets per-engine `#if` gating stay
 *                  local; its body should typically just
 *                  `return rac_engine_unavailable_capability(...)`.
 *
 * Invoke at file scope inside the engine's own `extern "C"` block (this macro
 * does not open one), so the manifest, vtable and entry function all have C
 * linkage — preserving the `extern "C" const rac_engine_vtable_t` contract.
 */
#define RAC_ENGINE_UNAVAILABLE_PLUGIN(name, display, cap_fn)         \
    RAC_ENGINE_UNAVAILABLE_MANIFEST_DEF(name, display);             \
    RAC_ENGINE_UNAVAILABLE_VTABLE_DEF(name, cap_fn);               \
    RAC_PLUGIN_ENTRY_DEF(name) {                                    \
        return rac_engine_entry_with_manifest(                     \
            &k_##name##_unavailable_manifest,                      \
            &g_##name##_unavailable_vtable);                       \
    }

#ifdef __cplusplus
}
#endif

#endif  // RUNANYWHERE_ENGINES_COMMON_ENGINE_UNAVAILABLE_H
