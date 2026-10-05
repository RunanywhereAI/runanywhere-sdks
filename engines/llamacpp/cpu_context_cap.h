// CPU-only context ceiling for the llama.cpp backend (see
// llamacpp_backend.cpp: on CPU-only builds common_fit_params answers in
// VRAM terms, so the backend re-caps against host RAM here instead).
//
// Header-only and std-only so core/tests can cover the tier mapping without
// linking llama.cpp.

#pragma once

#include <cstdint>
#include <fstream>
#include <string>

#if defined(_WIN32)
#include <windows.h>
#elif defined(__APPLE__)
#include <sys/sysctl.h>
#endif

namespace runanywhere {

// Host RAM in bytes, 0 when unknowable.
inline uint64_t host_ram_bytes() {
#if defined(_WIN32)
    MEMORYSTATUSEX status;
    status.dwLength = sizeof(status);
    if (GlobalMemoryStatusEx(&status)) {
        return static_cast<uint64_t>(status.ullTotalPhys);
    }
    return 0;
#elif defined(__APPLE__)
    uint64_t memsize = 0;
    size_t len = sizeof(memsize);
    if (sysctlbyname("hw.memsize", &memsize, &len, nullptr, 0) == 0) {
        return memsize;
    }
    return 0;
#else
    std::ifstream meminfo("/proc/meminfo");
    std::string key;
    while (meminfo >> key) {
        if (key == "MemTotal:") {
            uint64_t kb = 0;
            std::string unit;
            if (meminfo >> kb >> unit) {
                return kb * 1024ULL;
            }
            return 0;
        }
        std::string rest;
        std::getline(meminfo, rest);
    }
    return 0;
#endif
}

// Largest context a CPU-only load may keep, tiered off host RAM the way the
// harness sizes its requests (8k/16k/32k/64k). A fit that already clears the
// bar passes through untouched below; unknown RAM keeps today's 4096 rather
// than risking an OOM nobody can see.
inline uint32_t cpu_ram_context_cap(uint64_t ram_bytes) {
    const uint64_t gib = 1024ULL * 1024ULL * 1024ULL;
    if (ram_bytes >= 48 * gib) {
        return 65536;
    }
    if (ram_bytes >= 24 * gib) {
        return 32768;
    }
    if (ram_bytes >= 12 * gib) {
        return 16384;
    }
    return 4096;
}

inline uint32_t cpu_ram_context_cap() { return cpu_ram_context_cap(host_ram_bytes()); }

}  // namespace runanywhere
