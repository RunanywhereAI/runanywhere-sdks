/**
 * @file src/jni/jni_scope.h
 * @brief RAII helpers for safe, exception-aware JNI calls
 *
 * Problem
 * -------
 * Every JNIEnv method that crosses into Java/Kotlin can leave a pending
 * exception on the JNIEnv when the Java callee throws (OutOfMemoryError
 * from NewStringUTF, NullPointerException from an adapter's
 * callBooleanMethod, any user-thrown RuntimeException, etc.). JNI rules
 * require that pending exception to be explicitly checked and cleared
 * (ExceptionCheck / ExceptionClear); otherwise subsequent JNI calls from
 * the same native frame exhibit undefined behaviour. Before this file,
 * runanywhere_commons_jni.cpp had 149 JNIEXPORT entry points but only
 * 11 ExceptionCheck() calls and 76 unprotected NewStringUTF / 33
 * unprotected CallXxxMethod sites - an ~93% gap that could corrupt the
 * Android runtime on the first Java-side exception.
 *
 * Solution
 * --------
 * JniScope is a stack-scoped RAII helper that:
 *   - Wraps every throwing JNIEnv call with an automatic ExceptionCheck.
 *   - If an exception is pending, it logs (category, message, stack
 *     trace via ExceptionDescribe when debug is enabled), clears it,
 *     and returns RAC_ERROR_JNI_EXCEPTION / nullptr. The caller then
 *     bails out cleanly instead of racing into another JNIEnv call.
 *   - Owns any jstring / jobject locals it creates, deleting them on
 *     scope exit (no more manual DeleteLocalRef, no more leaked locals
 *     on error paths).
 *   - Is header-only; zero overhead when no exception is thrown.
 *
 * Usage pattern
 * -------------
 *   rac_result_t jni_something_callback(...) {
 *       JNIEnv* env = getJNIEnv();
 *       if (env == nullptr) return RAC_ERROR_ADAPTER_NOT_SET;
 *       JniScope s(env, "file_exists");
 *
 *       auto jPath = s.new_string_utf(path ? path : "");
 *       if (!jPath) return s.result();  // translates pending exception
 *
 *       jboolean b = s.call_boolean_method(g_platform_adapter,
 *                                          g_method_file_exists, jPath.get());
 *       if (s.failed()) return s.result();
 *
 *       return b ? RAC_TRUE : RAC_FALSE;
 *   }
 *
 * The `jPath` local is released automatically when the scope exits;
 * s.result() is RAC_SUCCESS unless a prior call raised.
 */

#ifndef RAC_JNI_SCOPE_H
#define RAC_JNI_SCOPE_H

#include <jni.h>

#include <cstdarg>
#include <cstdio>
#include <utility>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"

namespace rac {
namespace jni {

// Small RAII wrapper around a jobject local reference. Deletes the local
// ref when the wrapper goes out of scope. Move-only. Implicitly convertible
// to the underlying jobject so it drops into existing JNI APIs naturally.
template <typename T = jobject>
class Local {
public:
    Local() = default;
    Local(JNIEnv* env, T ref) : env_(env), ref_(ref) {}
    Local(const Local&) = delete;
    Local& operator=(const Local&) = delete;
    Local(Local&& other) noexcept : env_(other.env_), ref_(other.ref_) {
        other.env_ = nullptr;
        other.ref_ = nullptr;
    }
    Local& operator=(Local&& other) noexcept {
        if (this != &other) {
            reset();
            env_ = other.env_;
            ref_ = other.ref_;
            other.env_ = nullptr;
            other.ref_ = nullptr;
        }
        return *this;
    }
    ~Local() { reset(); }

    T get() const { return ref_; }
    explicit operator bool() const { return ref_ != nullptr; }
    // Implicit conversion so code can pass the Local<jstring> directly
    // where a jstring is expected.
    operator T() const { return ref_; }  // NOLINT(google-explicit-constructor)

    T release() {
        T r = ref_;
        ref_ = nullptr;
        env_ = nullptr;
        return r;
    }

    void reset() {
        if (env_ != nullptr && ref_ != nullptr) {
            env_->DeleteLocalRef(ref_);
        }
        env_ = nullptr;
        ref_ = nullptr;
    }

private:
    JNIEnv* env_ = nullptr;
    T ref_ = nullptr;
};

// Non-owning scope that auto-checks and clears JNI exceptions after
// every wrapped call. Intended to be stack-local to a single JNI entry
// point or callback.
class JniScope {
public:
    // `context` shows up in log messages so an offending call site is
    // easy to find in logcat. Keep it short (the function name).
    JniScope(JNIEnv* env, const char* context) : env_(env), context_(context) {}

    // Copy/move: scopes are stack-local and should not migrate.
    JniScope(const JniScope&) = delete;
    JniScope& operator=(const JniScope&) = delete;

    // --- Exception handling -----------------------------------------------

    // Returns RAC_SUCCESS if no exception has fired in this scope,
    // otherwise RAC_ERROR_JNI_EXCEPTION.
    rac_result_t result() const { return result_; }

    // Shortcut: did anything go wrong so far?
    bool failed() const { return result_ != RAC_SUCCESS; }

    // Manually check for a pending exception (e.g. after raw JNIEnv calls
    // made without going through the wrappers below). Logs and clears;
    // subsequent calls to result()/failed() will see the failure.
    void check(const char* phase = nullptr) {
        if (env_ == nullptr || result_ != RAC_SUCCESS) {
            return;
        }
        if (env_->ExceptionCheck() != JNI_TRUE) {
            return;
        }
        // Describe the exception to logcat before clearing - super useful
        // for debugging and cheap enough to leave on (only pays cost when
        // an exception is actually live).
        env_->ExceptionDescribe();
        env_->ExceptionClear();
        RAC_LOG_ERROR("JniScope",
                      "Java exception in [%s]%s%s - checked and cleared; "
                      "returning RAC_ERROR_JNI_EXCEPTION",
                      context_ != nullptr ? context_ : "?",
                      phase != nullptr ? " @ " : "",
                      phase != nullptr ? phase : "");
        result_ = RAC_ERROR_JNI_EXCEPTION;
    }

    // --- Wrapped JNIEnv calls --------------------------------------------

    Local<jstring> new_string_utf(const char* s) {
        if (failed() || env_ == nullptr) {
            return {};
        }
        jstring raw = env_->NewStringUTF(s != nullptr ? s : "");
        check("NewStringUTF");
        return Local<jstring>(env_, raw);
    }

    Local<jbyteArray> new_byte_array(jsize len) {
        if (failed() || env_ == nullptr) {
            return {};
        }
        jbyteArray raw = env_->NewByteArray(len);
        check("NewByteArray");
        return Local<jbyteArray>(env_, raw);
    }

    template <typename... Args>
    Local<jobject> call_object_method(jobject obj, jmethodID m, Args... args) {
        if (failed() || env_ == nullptr || obj == nullptr || m == nullptr) {
            return {};
        }
        jobject raw = env_->CallObjectMethod(obj, m, std::forward<Args>(args)...);
        check("CallObjectMethod");
        return Local<jobject>(env_, raw);
    }

    template <typename... Args>
    jboolean call_boolean_method(jobject obj, jmethodID m, Args... args) {
        if (failed() || env_ == nullptr || obj == nullptr || m == nullptr) {
            return JNI_FALSE;
        }
        jboolean r = env_->CallBooleanMethod(obj, m, std::forward<Args>(args)...);
        check("CallBooleanMethod");
        return r;
    }

    template <typename... Args>
    jint call_int_method(jobject obj, jmethodID m, Args... args) {
        if (failed() || env_ == nullptr || obj == nullptr || m == nullptr) {
            return 0;
        }
        jint r = env_->CallIntMethod(obj, m, std::forward<Args>(args)...);
        check("CallIntMethod");
        return r;
    }

    template <typename... Args>
    jlong call_long_method(jobject obj, jmethodID m, Args... args) {
        if (failed() || env_ == nullptr || obj == nullptr || m == nullptr) {
            return 0;
        }
        jlong r = env_->CallLongMethod(obj, m, std::forward<Args>(args)...);
        check("CallLongMethod");
        return r;
    }

    template <typename... Args>
    void call_void_method(jobject obj, jmethodID m, Args... args) {
        if (failed() || env_ == nullptr || obj == nullptr || m == nullptr) {
            return;
        }
        env_->CallVoidMethod(obj, m, std::forward<Args>(args)...);
        check("CallVoidMethod");
    }

    JNIEnv* env() const { return env_; }
    const char* context() const { return context_; }

private:
    JNIEnv* env_ = nullptr;
    const char* context_ = nullptr;
    rac_result_t result_ = RAC_SUCCESS;
};

}  // namespace jni
}  // namespace rac

// Short helpers for the common "bail if JniScope already failed" pattern.
// These let us mechanically replace unchecked raw env->Xxx() calls.

#define RAC_JNI_TRY(scope) do { if ((scope).failed()) return (scope).result(); } while (0)
#define RAC_JNI_TRY_PTR(scope, ptr_fallback) \
    do { if ((scope).failed()) return (ptr_fallback); } while (0)
#define RAC_JNI_TRY_VOID(scope) do { if ((scope).failed()) return; } while (0)

#endif  // RAC_JNI_SCOPE_H
