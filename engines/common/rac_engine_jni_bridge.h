#ifndef RUNANYWHERE_ENGINES_COMMON_JNI_BRIDGE_H
#define RUNANYWHERE_ENGINES_COMMON_JNI_BRIDGE_H

/**
 * Shared JNI bridge boilerplate for engine backends.
 *
 * Every Android engine JNI bridge (onnx, llamacpp, ...) repeated the same
 * quartet of `Java_<pkg>_<Class>_native{Register,Unregister,IsRegistered,
 * GetVersion}` functions plus `JNI_OnLoad` plus the `LOGi`/`LOGe`/`LOGw` log
 * macros — ~30 lines of identical glue per engine. This header collapses that
 * to a single token-pasting macro so the bridge .cpp only hand-writes the parts
 * that are genuinely engine-specific (e.g. llamacpp's extra nativeCreate /
 * nativeGenerate methods, or onnx's sibling-backend cross-registration).
 *
 * CRITICAL — JNI symbol parity: the JVM resolves native methods by the exact
 * mangled symbol `Java_<class-path-with-underscores>_<method>`. The class-path
 * token is a macro PARAMETER so the pasted symbol matches each engine's Kotlin
 * `*Bridge` class byte-for-byte. If it drifts by one character, registration
 * silently no-ops at runtime. Do not "tidy" the token forms below.
 *
 * Platform guard: the source bridges emit these symbols unconditionally inside
 * their `extern "C"` block (they are only ever compiled into the Android JNI
 * .so target). This macro preserves that exactly — it adds NO `__ANDROID__`
 * guard, because doing so would drop the symbols on any other build of the TU
 * and change observable behavior. The caller places the macro inside its own
 * `extern "C" { ... }` so the emitted symbols keep C linkage.
 *
 * Internal to the engines/ tree. Not part of the stable rac_* C ABI.
 */

#include <jni.h>

#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_primitive.h"

// =============================================================================
// JNI log macros (LOGi / LOGe / LOGw)
// =============================================================================
//
// Route JNI logging through the unified RAC_LOG_* system. These read a
// `LOG_TAG` that must be in scope; stamp one with RAC_DEFINE_ENGINE_JNI_LOG_TAG
// (or declare it by hand, as the bridges originally did). Defined object-like so
// a bridge .cpp can also use them inside its own hand-written native methods
// (llamacpp logs from nativeGenerate, etc.). Guarded so a bridge that already
// defines them is left untouched.

#ifndef LOGi
#define LOGi(...) RAC_LOG_INFO(LOG_TAG, __VA_ARGS__)
#endif
#ifndef LOGe
#define LOGe(...) RAC_LOG_ERROR(LOG_TAG, __VA_ARGS__)
#endif
#ifndef LOGw
#define LOGw(...) RAC_LOG_WARNING(LOG_TAG, __VA_ARGS__)
#endif

/**
 * Stamp the file-scope `static const char* LOG_TAG` the log macros above read,
 * matching what each bridge declared by hand before extraction. Invoke once at
 * file scope (e.g. `RAC_DEFINE_ENGINE_JNI_LOG_TAG("JNI.ONNX");`).
 */
#define RAC_DEFINE_ENGINE_JNI_LOG_TAG(TAG_LITERAL) static const char* LOG_TAG = TAG_LITERAL

/**
 * Paste the JVM-mangled native-method symbol for a given class-path token and
 * method name: `Java_<JCLASS_TOKENS>_<METHOD>`.
 *
 * JCLASS_TOKENS and METHOD are always passed as bare tokens, never as macros
 * that must expand first, so this is a DIRECT paste with no expansion layer.
 * That is deliberate: forcing macro expansion of the operands would let a stray
 * object-like macro silently rewrite a symbol fragment — exactly the parity
 * hazard we guard against. Keep this a single-level paste.
 */
#define RAC_JNI_FN(JCLASS_TOKENS, METHOD) Java_##JCLASS_TOKENS##_##METHOD

/**
 * No-op after-register statement for engines that need nothing extra in
 * nativeRegister (e.g. llamacpp). Pass this as RAC_DEFINE_ENGINE_JNI_BRIDGE's
 * AFTER_REGISTER_STMT argument.
 */
#define RAC_ENGINE_JNI_NO_AFTER_REGISTER(env, clazz) ((void)(env), (void)(clazz))

/**
 * Emit the standard engine JNI bridge quartet + `JNI_OnLoad`.
 *
 * @param JCLASS_TOKENS  Fully-qualified Kotlin class path with '.' / the class
 *                       separator rewritten as '_', exactly as the JVM mangles
 *                       it — e.g. for `com.runanywhere.sdk.core.onnx.ONNXBridge`
 *                       pass `com_runanywhere_sdk_core_onnx_ONNXBridge`. Pasted
 *                       into every `Java_*` symbol, so it MUST match the Kotlin
 *                       class byte-for-byte.
 * @param REGISTER_FN    C registration entry point, e.g. `rac_backend_onnx_register`.
 *                       Forward-declare it (extern "C") before invoking the macro.
 * @param UNREGISTER_FN  C unregistration entry point, e.g. `rac_backend_onnx_unregister`.
 * @param ENGINE_LABEL   Human-readable engine name for log lines, e.g. "ONNX".
 * @param REGISTER_OK_SUFFIX  String literal appended to the "registered
 *                       successfully" log line (concatenated), e.g.
 *                       " (generic ONNX services)" — pass "" for none. Log text
 *                       only; does not affect return codes or symbols.
 * @param AFTER_REGISTER_STMT  A single statement, invoked as
 *                       `AFTER_REGISTER_STMT(env, clazz)`, run inside
 *                       nativeRegister AFTER REGISTER_FN() + already-registered
 *                       tolerance succeed and BEFORE the success return — where
 *                       onnx slots its sibling cross-registration + EMBED plugin
 *                       debug listing. Its result (if any) is discarded: onnx's
 *                       original post-register block logged warnings but always
 *                       returned RAC_SUCCESS, which this preserves. Pass
 *                       RAC_ENGINE_JNI_NO_AFTER_REGISTER when nothing extra is
 *                       needed (e.g. llamacpp), or the name of a helper taking
 *                       `(JNIEnv*, jclass)`. Passed as a macro argument (not a
 *                       redefinable hook) so there is no define-order coupling.
 * @param ISREG_PRIMITIVE     rac_primitive_t whose plugin list nativeIsRegistered
 *                       scans (e.g. RAC_PRIMITIVE_EMBED for onnx).
 * @param ISREG_PLUGIN_NAME   plugin metadata.name nativeIsRegistered matches
 *                       (e.g. "onnx").
 * @param VERSION_EXPR   Expression yielding a `const char*` version string for
 *                       nativeGetVersion.
 *
 * Behavior matches the hand-written quartet it replaces:
 *  - nativeRegister calls REGISTER_FN(); tolerates RAC_ERROR_MODULE_ALREADY_REGISTERED
 *    (continues), returns the raw error code on any other failure; then runs
 *    AFTER_REGISTER_STMT(env, clazz) and returns RAC_SUCCESS.
 *  - nativeUnregister calls UNREGISTER_FN() and returns its raw rac_result_t.
 *  - nativeIsRegistered scans the plugin registry for ISREG_PLUGIN_NAME under
 *    ISREG_PRIMITIVE.
 *  - nativeGetVersion returns env->NewStringUTF(VERSION_EXPR).
 *
 * NOT wrapped in `extern "C"`: place inside the bridge's `extern "C" { ... }`.
 *
 * ── JNI_OnLoad ownership ──────────────────────────────────────────────────────
 * This full macro EMITS `JNI_OnLoad`, which is correct for an engine bridge that
 * links as its OWN standalone `.so` (onnx → rac_backend_onnx_jni, llamacpp →
 * rac_backend_llamacpp_jni): each such library needs exactly one JNI_OnLoad and
 * has no other provider. If instead the engine JNI TU is FOLDED INTO a host lib
 * that ALREADY defines `JNI_OnLoad` — e.g. cloud_stt's rac_stt_cloud_jni.cpp is
 * compiled straight into `runanywhere_commons_jni` (librunanywhere_jni.so), and
 * commons already owns JNI_OnLoad (runanywhere_commons_jni.cpp) to cache the
 * JavaVM — emitting a second JNI_OnLoad is a hard duplicate-symbol link error.
 * Such TUs MUST use RAC_DEFINE_ENGINE_JNI_BRIDGE_NO_ONLOAD below: it emits the
 * identical register quartet (Kotlin still binds those symbols) but omits the
 * JNI_OnLoad, deferring JavaVM ownership to the host. Registration is unaffected
 * — the Kotlin `*Bridge.nativeRegister()` path drives REGISTER_FN() and never
 * depends on this TU's JNI_OnLoad.
 */

// Internal: the engine JNI register quartet (nativeRegister / nativeUnregister /
// nativeIsRegistered / nativeGetVersion) WITHOUT JNI_OnLoad. Shared verbatim by
// both the full RAC_DEFINE_ENGINE_JNI_BRIDGE (which prepends JNI_OnLoad) and the
// RAC_DEFINE_ENGINE_JNI_BRIDGE_NO_ONLOAD variant (which does not), so the quartet
// body is written exactly once. Not intended to be invoked directly — use one of
// the two public macros so JNI_OnLoad ownership is an explicit choice. Parameters
// are identical to the public macros' (minus none): see their docs above.
#define RAC_DEFINE_ENGINE_JNI_REGISTER_QUARTET(                                                     \
    JCLASS_TOKENS, REGISTER_FN, UNREGISTER_FN, ENGINE_LABEL, REGISTER_OK_SUFFIX,                    \
    AFTER_REGISTER_STMT, ISREG_PRIMITIVE, ISREG_PLUGIN_NAME, VERSION_EXPR)                          \
                                                                                                   \
    JNIEXPORT jint JNICALL RAC_JNI_FN(JCLASS_TOKENS, nativeRegister)(JNIEnv* env, jclass clazz) {   \
        (void)env;                                                                                 \
        (void)clazz;                                                                               \
        LOGi(ENGINE_LABEL " nativeRegister called");                                                \
        rac_result_t result = REGISTER_FN();                                                       \
        if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {              \
            LOGe("Failed to register " ENGINE_LABEL " backend: %d", result);                        \
            return static_cast<jint>(result);                                                      \
        }                                                                                          \
        AFTER_REGISTER_STMT(env, clazz);                                                            \
        LOGi(ENGINE_LABEL " backend registered successfully" REGISTER_OK_SUFFIX);                   \
        return RAC_SUCCESS;                                                                         \
    }                                                                                              \
                                                                                                   \
    JNIEXPORT jint JNICALL RAC_JNI_FN(JCLASS_TOKENS, nativeUnregister)(JNIEnv* env,                 \
                                                                       jclass clazz) {             \
        (void)env;                                                                                 \
        (void)clazz;                                                                               \
        LOGi(ENGINE_LABEL " nativeUnregister called");                                              \
        rac_result_t result = UNREGISTER_FN();                                                     \
        if (result != RAC_SUCCESS) {                                                               \
            LOGe("Failed to unregister " ENGINE_LABEL " backend: %d", result);                      \
        } else {                                                                                   \
            LOGi(ENGINE_LABEL " backend unregistered");                                             \
        }                                                                                          \
        return static_cast<jint>(result);                                                          \
    }                                                                                              \
                                                                                                   \
    JNIEXPORT jboolean JNICALL RAC_JNI_FN(JCLASS_TOKENS, nativeIsRegistered)(JNIEnv* env,           \
                                                                             jclass clazz) {       \
        (void)env;                                                                                 \
        (void)clazz;                                                                               \
        const rac_engine_vtable_t* _plugins[16] = {};                                              \
        size_t _plugin_count = 0;                                                                  \
        rac_result_t _result =                                                                     \
            rac_plugin_list((ISREG_PRIMITIVE), _plugins, 16, &_plugin_count);                       \
        if (_result == RAC_SUCCESS) {                                                              \
            for (size_t _i = 0; _i < _plugin_count; ++_i) {                                        \
                if (_plugins[_i] && _plugins[_i]->metadata.name &&                                 \
                    strcmp(_plugins[_i]->metadata.name, (ISREG_PLUGIN_NAME)) == 0) {               \
                    return JNI_TRUE;                                                                \
                }                                                                                  \
            }                                                                                      \
        }                                                                                          \
        return JNI_FALSE;                                                                          \
    }                                                                                              \
                                                                                                   \
    JNIEXPORT jstring JNICALL RAC_JNI_FN(JCLASS_TOKENS, nativeGetVersion)(JNIEnv* env,              \
                                                                          jclass clazz) {          \
        (void)clazz;                                                                               \
        return env->NewStringUTF(VERSION_EXPR);                                                     \
    }

/**
 * Emit the standard engine JNI bridge: `JNI_OnLoad` + the register quartet.
 *
 * The DEFAULT/full variant. Use this for an engine bridge that links as its own
 * standalone JNI `.so` (onnx, llamacpp), where this TU is the sole owner of
 * JNI_OnLoad. Parameters and per-symbol behavior are documented on the block
 * immediately above. The JNI_OnLoad it emits just logs and returns
 * JNI_VERSION_1_6 (these standalone engine libs cache no JavaVM of their own).
 *
 * NOT wrapped in `extern "C"`: place inside the bridge's `extern "C" { ... }`.
 */
#define RAC_DEFINE_ENGINE_JNI_BRIDGE(JCLASS_TOKENS, REGISTER_FN, UNREGISTER_FN, ENGINE_LABEL,       \
                                     REGISTER_OK_SUFFIX, AFTER_REGISTER_STMT, ISREG_PRIMITIVE,      \
                                     ISREG_PLUGIN_NAME, VERSION_EXPR)                               \
                                                                                                   \
    JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {                                         \
        (void)vm;                                                                                  \
        (void)reserved;                                                                            \
        LOGi("JNI_OnLoad: " ENGINE_LABEL " JNI bridge loaded");                                     \
        return JNI_VERSION_1_6;                                                                     \
    }                                                                                              \
                                                                                                   \
    RAC_DEFINE_ENGINE_JNI_REGISTER_QUARTET(JCLASS_TOKENS, REGISTER_FN, UNREGISTER_FN, ENGINE_LABEL, \
                                           REGISTER_OK_SUFFIX, AFTER_REGISTER_STMT, ISREG_PRIMITIVE, \
                                           ISREG_PLUGIN_NAME, VERSION_EXPR)

/**
 * Emit the standard engine JNI bridge WITHOUT `JNI_OnLoad` — register quartet only.
 *
 * Use this when the engine JNI TU is folded into a HOST library that already
 * defines `JNI_OnLoad`, so a second definition would be a duplicate-symbol link
 * error. The in-tree case is cloud_stt: rac_stt_cloud_jni.cpp is compiled into
 * `runanywhere_commons_jni` (librunanywhere_jni.so), and commons already owns
 * JNI_OnLoad to cache the JavaVM. The four
 * `Java_<...>Bridge_native{Register,Unregister,IsRegistered,GetVersion}` symbols
 * are emitted byte-for-byte identically to the full macro (Kotlin still binds
 * them); only JNI_OnLoad is omitted. Registration is unaffected: it flows through
 * nativeRegister → REGISTER_FN(), independent of any JNI_OnLoad in this TU.
 *
 * Standalone per-engine `.so`s must use the full RAC_DEFINE_ENGINE_JNI_BRIDGE so
 * their library still provides exactly one JNI_OnLoad.
 *
 * Same parameters / per-symbol behavior as RAC_DEFINE_ENGINE_JNI_BRIDGE (minus
 * the JNI_OnLoad). NOT wrapped in `extern "C"`: place inside the bridge's
 * `extern "C" { ... }`.
 */
#define RAC_DEFINE_ENGINE_JNI_BRIDGE_NO_ONLOAD(                                                     \
    JCLASS_TOKENS, REGISTER_FN, UNREGISTER_FN, ENGINE_LABEL, REGISTER_OK_SUFFIX,                    \
    AFTER_REGISTER_STMT, ISREG_PRIMITIVE, ISREG_PLUGIN_NAME, VERSION_EXPR)                          \
                                                                                                   \
    RAC_DEFINE_ENGINE_JNI_REGISTER_QUARTET(JCLASS_TOKENS, REGISTER_FN, UNREGISTER_FN, ENGINE_LABEL, \
                                           REGISTER_OK_SUFFIX, AFTER_REGISTER_STMT, ISREG_PRIMITIVE, \
                                           ISREG_PLUGIN_NAME, VERSION_EXPR)

#endif  // RUNANYWHERE_ENGINES_COMMON_JNI_BRIDGE_H
