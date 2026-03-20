// MSVC C++20 fix: u8"..." returns const char8_t*, which cannot be cast to const char*.
// This header is force-included before llama-chat.cpp (and all llama/common sources)
// via /FI so it overrides the LU8 macro defined in llama-chat.cpp.
// /utf-8 is also set so MSVC reads source files as UTF-8, preserving multi-byte chars.
#pragma once
#if defined(_MSC_VER) && defined(__cplusplus) && __cplusplus >= 202002L
#  ifdef LU8
#    undef LU8
#  endif
#  define LU8(x) x
#endif
