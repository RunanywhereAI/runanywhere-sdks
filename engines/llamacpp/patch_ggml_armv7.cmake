# patch_ggml_armv7.cmake — run as the llama.cpp FetchContent PATCH_COMMAND (cwd = llamacpp source root).
#
# ggml's ggml/src/ggml-cpu/arch/arm/quants.c calls the RAW AArch64-only intrinsic `vqtbl1q_u8(...)` at two
# sites, guarded only by `#if defined(__ARM_NEON)` — which is TRUE for 32-bit armeabi-v7a (the NDK enables
# NEON there), but `vqtbl1q_u8` is an AArch64 (128-bit table-lookup) intrinsic with no 32-bit-NEON form, so the
# armv7 cross-compile fails ("call to undeclared function 'vqtbl1q_u8'"). Everywhere else the file already uses
# the portable `ggml_vqtbl1q_u8` wrapper (ggml-cpu-impl.h) that maps to the raw intrinsic on aarch64 and to a
# vtbl-based fallback on armv7. This rewrites the two raw uses to that wrapper.
#
# Safe on ALL arches/versions: the wrapper == the raw intrinsic on aarch64, and the negative-context regex
# skips the already-wrapped `ggml_vqtbl1q_u8` calls, so it is idempotent and a no-op when the file or pattern
# is absent (e.g. a future llama.cpp bump that fixes this upstream). Pure CMake → no sed/perl portability gap.
set(_f "ggml/src/ggml-cpu/arch/arm/quants.c")
if(EXISTS "${_f}")
    file(READ "${_f}" _content)
    # Match `vqtbl1q_u8(` only when the char before it is NOT an identifier char (so `ggml_vqtbl1q_u8(`,
    # preceded by `_`, is left alone). Capture that char and re-emit it.
    string(REGEX REPLACE "([^A-Za-z0-9_])vqtbl1q_u8\\(" "\\1ggml_vqtbl1q_u8(" _patched "${_content}")
    if(NOT _patched STREQUAL _content)
        file(WRITE "${_f}" "${_patched}")
        message(STATUS "patch_ggml_armv7: rewrote raw vqtbl1q_u8 -> ggml_vqtbl1q_u8 in ${_f}")
    endif()
endif()
