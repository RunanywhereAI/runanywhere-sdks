/**
 * @file cpu_state.cpp
 * @brief In-process CPU state sampling for per-event telemetry.
 *
 * Reads OS accounting directly (no platform-adapter callback needed):
 * - Linux/Android: /proc/stat aggregate; falls back to /proc/self/stat
 *   (process CPU normalized to total capacity) where SELinux hides /proc/stat.
 * - Apple: host_statistics(HOST_CPU_LOAD_INFO).
 * - Windows: GetSystemTimes().
 * - Others (WASM): unavailable, reports -1.
 *
 * Usage percent is the busy/total tick delta since the previous call, so the
 * telemetry manager gets "average CPU since the last event" — the useful
 * number for benchmark runs. First call establishes the baseline.
 */

#include "rac_device_live_state_internal.h"

#include <mutex>

#if defined(_WIN32)
#include <windows.h>
#elif defined(__APPLE__)
#include <unistd.h>

#include <mach/host_info.h>
#include <mach/mach_host.h>
#include <mach/mach_init.h>
#else
#include <unistd.h>

#include <cinttypes>
#include <cstdio>
#include <cstring>
#include <ctime>
#endif

namespace {

std::mutex g_cpu_mutex;

#if defined(_WIN32)

uint64_t filetime_u64(const FILETIME& ft) {
    return (static_cast<uint64_t>(ft.dwHighDateTime) << 32) | ft.dwLowDateTime;
}

bool read_ticks(uint64_t* busy, uint64_t* total) {
    FILETIME idle_ft, kernel_ft, user_ft;
    if (!GetSystemTimes(&idle_ft, &kernel_ft, &user_ft)) {
        return false;
    }
    const uint64_t idle = filetime_u64(idle_ft);
    const uint64_t kernel = filetime_u64(kernel_ft);  // includes idle
    const uint64_t user = filetime_u64(user_ft);
    *total = kernel + user;
    *busy = *total - idle;
    return true;
}

#elif defined(__APPLE__)

bool read_ticks(uint64_t* busy, uint64_t* total) {
    host_cpu_load_info_data_t info;
    mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
    if (host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, reinterpret_cast<host_info_t>(&info),
                        &count) != KERN_SUCCESS) {
        return false;
    }
    const uint64_t user = info.cpu_ticks[CPU_STATE_USER];
    const uint64_t system = info.cpu_ticks[CPU_STATE_SYSTEM];
    const uint64_t nice = info.cpu_ticks[CPU_STATE_NICE];
    const uint64_t idle = info.cpu_ticks[CPU_STATE_IDLE];
    *busy = user + system + nice;
    *total = *busy + idle;
    return true;
}

#else

// Aggregate system ticks from /proc/stat. Unreadable on Android 8+ app
// processes (SELinux) — read_process_ticks covers that case.
bool read_ticks(uint64_t* busy, uint64_t* total) {
    FILE* f = fopen("/proc/stat", "re");
    if (!f) {
        return false;
    }
    uint64_t user = 0, nice = 0, system = 0, idle = 0, iowait = 0, irq = 0, softirq = 0, steal = 0;
    const int matched = fscanf(f,
                               "cpu %" SCNu64 " %" SCNu64 " %" SCNu64 " %" SCNu64 " %" SCNu64
                               " %" SCNu64 " %" SCNu64 " %" SCNu64,
                               &user, &nice, &system, &idle, &iowait, &irq, &softirq, &steal);
    fclose(f);
    if (matched < 4) {
        return false;
    }
    *busy = user + nice + system + irq + softirq + steal;
    *total = *busy + idle + iowait;
    return true;
}

// Process CPU ticks + wall clock, for the /proc/stat-restricted fallback.
// "total" is wall time scaled to all cores so the percentage stays 0-100
// relative to full device capacity.
bool read_process_ticks(uint64_t* busy, uint64_t* total) {
    FILE* f = fopen("/proc/self/stat", "re");
    if (!f) {
        return false;
    }
    // Fields 14 (utime) and 15 (stime); field 2 (comm) may contain spaces, so
    // skip past the closing paren first.
    char buf[512];
    const size_t n = fread(buf, 1, sizeof(buf) - 1, f);
    fclose(f);
    if (n == 0) {
        return false;
    }
    buf[n] = '\0';
    const char* p = strrchr(buf, ')');
    if (!p) {
        return false;
    }
    p += 1;
    uint64_t utime = 0, stime = 0;
    // After comm: state + 10 fields precede utime.
    char state = 0;
    unsigned long long skip[10] = {};
    if (sscanf(p, " %c %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu %" SCNu64 " %" SCNu64,
               &state, &skip[0], &skip[1], &skip[2], &skip[3], &skip[4], &skip[5], &skip[6],
               &skip[7], &skip[8], &skip[9], &utime, &stime) < 13) {
        return false;
    }
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
        return false;
    }
    const long ticks_per_sec = sysconf(_SC_CLK_TCK);
    const long ncpu = sysconf(_SC_NPROCESSORS_ONLN);
    if (ticks_per_sec <= 0 || ncpu <= 0) {
        return false;
    }
    *busy = utime + stime;
    const uint64_t wall_ticks = (static_cast<uint64_t>(ts.tv_sec) * ticks_per_sec) +
                                (static_cast<uint64_t>(ts.tv_nsec) * ticks_per_sec / 1000000000ULL);
    *total = wall_ticks * static_cast<uint64_t>(ncpu);
    return true;
}

#endif

}  // namespace

extern "C" {

double rac_cpu_sample_usage_percent(void) {
    std::lock_guard<std::mutex> lock(g_cpu_mutex);

    static uint64_t prev_busy = 0;
    static uint64_t prev_total = 0;
    static bool has_baseline = false;

    uint64_t busy = 0, total = 0;
    bool ok = read_ticks(&busy, &total);
#if !defined(_WIN32) && !defined(__APPLE__)
    static bool use_process_fallback = false;
    if (!ok || use_process_fallback) {
        use_process_fallback = true;
        ok = read_process_ticks(&busy, &total);
    }
#endif
    if (!ok) {
        return -1.0;
    }

    if (!has_baseline) {
        prev_busy = busy;
        prev_total = total;
        has_baseline = true;
        return -1.0;
    }

    const uint64_t busy_delta = busy >= prev_busy ? busy - prev_busy : 0;
    const uint64_t total_delta = total >= prev_total ? total - prev_total : 0;
    prev_busy = busy;
    prev_total = total;

    if (total_delta == 0) {
        return -1.0;
    }
    double pct = 100.0 * static_cast<double>(busy_delta) / static_cast<double>(total_delta);
    if (pct < 0.0) {
        pct = 0.0;
    }
    if (pct > 100.0) {
        pct = 100.0;
    }
    return pct;
}

int32_t rac_cpu_online_core_count(void) {
#if defined(_WIN32)
    SYSTEM_INFO info;
    GetSystemInfo(&info);
    return static_cast<int32_t>(info.dwNumberOfProcessors);
#else
    const long n = sysconf(_SC_NPROCESSORS_ONLN);
    return n > 0 ? static_cast<int32_t>(n) : 0;
#endif
}

}  // extern "C"
