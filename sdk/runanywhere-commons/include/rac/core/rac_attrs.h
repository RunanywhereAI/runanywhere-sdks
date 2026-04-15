/**
 * @file rac_attrs.h
 * @brief RunAnywhere Commons - Compiler Attribute Macros
 *
 * Portable macros for C and C++ attributes used across the public RAC API:
 *   - RAC_NODISCARD         : warn when a return value is silently ignored
 *   - RAC_NONNULL(...)      : assert that pointer parameters cannot be NULL
 *   - RAC_DEPRECATED(msg)   : mark a symbol as deprecated with a migration hint
 *   - RAC_ATTR_PRINTF(f,a)  : printf-style format check for variadic functions
 *   - RAC_NORETURN          : function does not return (fatal error helpers)
 *
 * All macros degrade gracefully to nothing when the compiler does not support
 * the underlying attribute, so the header is safe to include from any C or
 * C++ translation unit on any supported platform.
 *
 * Compiler support matrix:
 *   | Attribute       | Clang | GCC | MSVC | Apple Clang | Android NDK |
 *   | nodiscard       |  3.9+ | 4.8+| 19.14+| 3.9+       | r14+        |
 *   | nonnull         |  3.9+ | 4.0+| n/a  | 3.9+        | r14+        |
 *   | deprecated(msg) |  3.9+ | 4.5+| 14.0+| 3.9+        | r14+        |
 *
 * For MSVC, RAC_NONNULL maps to _In_ SAL annotations where applicable.
 *
 * Include this header from every public RAC header that exposes functions
 * returning rac_result_t or taking pointer parameters.
 */

#ifndef RAC_ATTRS_H
#define RAC_ATTRS_H

/* ---------------------------------------------------------------------------
 * RAC_NODISCARD - warn if return value is ignored
 *
 * Usage:
 *   RAC_API RAC_NODISCARD rac_result_t rac_init(const rac_config_t* config);
 *
 * Callers that write `rac_init(&cfg);` without capturing the result will get
 * a compiler warning (or error with -Werror). This catches silent error code
 * drops, the #1 source of bugs in C-style API consumers.
 * --------------------------------------------------------------------------- */
#if defined(__cplusplus) && __cplusplus >= 201703L
    /* C++17 [[nodiscard]] */
    #define RAC_NODISCARD [[nodiscard]]
#elif defined(__has_attribute)
    #if __has_attribute(warn_unused_result)
        #define RAC_NODISCARD __attribute__((warn_unused_result))
    #endif
#elif defined(__GNUC__) && (__GNUC__ * 100 + __GNUC_MINOR__ >= 304)
    /* GCC 3.4+ supports warn_unused_result */
    #define RAC_NODISCARD __attribute__((warn_unused_result))
#endif
#if defined(_MSC_VER) && _MSC_VER >= 1700 && !defined(RAC_NODISCARD)
    /* MSVC 2012+: _Check_return_ is a SAL annotation that triggers /analyze */
    #define RAC_NODISCARD _Check_return_
#endif
#ifndef RAC_NODISCARD
    #define RAC_NODISCARD
#endif

/* ---------------------------------------------------------------------------
 * RAC_NONNULL(...) - mark pointer parameters as non-null
 *
 * Usage:
 *   RAC_API rac_result_t rac_module_register(
 *       RAC_NONNULL(1) const rac_module_info_t* info);
 *
 * Index arguments are 1-based (because GCC / Clang count them that way).
 * For member functions in C++ the implicit `this` is parameter 1, so shift.
 *
 * MSVC does not have a direct equivalent; falls back to empty macro (the
 * intent can still be checked manually / via clang-tidy's
 * bugprone-not-null-terminated-result check).
 * --------------------------------------------------------------------------- */
#if defined(__has_attribute)
    #if __has_attribute(nonnull)
        #define RAC_NONNULL(...) __attribute__((nonnull(__VA_ARGS__)))
    #endif
#elif defined(__GNUC__) && (__GNUC__ * 100 + __GNUC_MINOR__ >= 400)
    #define RAC_NONNULL(...) __attribute__((nonnull(__VA_ARGS__)))
#endif
#ifndef RAC_NONNULL
    #define RAC_NONNULL(...)
#endif

/* Variant: mark ALL pointer params as nonnull (no indices). */
#if defined(__has_attribute)
    #if __has_attribute(nonnull)
        #define RAC_NONNULL_ALL __attribute__((nonnull))
    #endif
#elif defined(__GNUC__) && (__GNUC__ * 100 + __GNUC_MINOR__ >= 400)
    #define RAC_NONNULL_ALL __attribute__((nonnull))
#endif
#ifndef RAC_NONNULL_ALL
    #define RAC_NONNULL_ALL
#endif

/* ---------------------------------------------------------------------------
 * RAC_DEPRECATED(msg) - mark a symbol as deprecated with migration text
 *
 * Usage:
 *   RAC_DEPRECATED("use rac_llm_generate_v2 instead")
 *   RAC_API rac_result_t rac_llm_generate(rac_handle_t h, ...);
 * --------------------------------------------------------------------------- */
#if defined(__cplusplus) && __cplusplus >= 201402L
    #define RAC_DEPRECATED(msg) [[deprecated(msg)]]
#elif defined(__has_attribute)
    #if __has_attribute(deprecated)
        #if defined(__clang__) || (defined(__GNUC__) && __GNUC__ >= 5)
            #define RAC_DEPRECATED(msg) __attribute__((deprecated(msg)))
        #else
            #define RAC_DEPRECATED(msg) __attribute__((deprecated))
        #endif
    #endif
#elif defined(_MSC_VER) && _MSC_VER >= 1400
    #define RAC_DEPRECATED(msg) __declspec(deprecated(msg))
#endif
#ifndef RAC_DEPRECATED
    #define RAC_DEPRECATED(msg)
#endif

/* ---------------------------------------------------------------------------
 * RAC_ATTR_PRINTF(fmt_index, args_index) - printf-style format checking
 *
 * Usage (variadic logger wrapper):
 *   RAC_API void rac_logger_log_fmt(rac_log_level_t lvl,
 *                                   const char* fmt, ...)
 *                                   RAC_ATTR_PRINTF(2, 3);
 * --------------------------------------------------------------------------- */
#if defined(__has_attribute)
    #if __has_attribute(format)
        #define RAC_ATTR_PRINTF(fmt_idx, args_idx) \
            __attribute__((format(printf, fmt_idx, args_idx)))
    #endif
#elif defined(__GNUC__)
    #define RAC_ATTR_PRINTF(fmt_idx, args_idx) \
        __attribute__((format(printf, fmt_idx, args_idx)))
#endif
#ifndef RAC_ATTR_PRINTF
    #define RAC_ATTR_PRINTF(fmt_idx, args_idx)
#endif

/* ---------------------------------------------------------------------------
 * RAC_NORETURN - function does not return
 * --------------------------------------------------------------------------- */
#if defined(__cplusplus) && __cplusplus >= 201103L
    #define RAC_NORETURN [[noreturn]]
#elif defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
    #define RAC_NORETURN _Noreturn
#elif defined(__GNUC__)
    #define RAC_NORETURN __attribute__((noreturn))
#elif defined(_MSC_VER)
    #define RAC_NORETURN __declspec(noreturn)
#else
    #define RAC_NORETURN
#endif

/* ---------------------------------------------------------------------------
 * RAC_PURE - function result depends only on its arguments (no globals, no I/O)
 * RAC_CONST - like pure, but also must not read any memory through a pointer
 *
 * Both enable compile-time deduplication and CSE by the optimizer.
 * --------------------------------------------------------------------------- */
#if defined(__has_attribute)
    #if __has_attribute(pure)
        #define RAC_PURE __attribute__((pure))
    #endif
    #if __has_attribute(const)
        #define RAC_CONST_FN __attribute__((const))
    #endif
#endif
#ifndef RAC_PURE
    #define RAC_PURE
#endif
#ifndef RAC_CONST_FN
    #define RAC_CONST_FN
#endif

#endif /* RAC_ATTRS_H */
