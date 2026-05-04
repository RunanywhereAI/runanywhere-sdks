/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Physical-memory probe shared by the jvmAndroidMain source set.
 *
 * Rationale (G-DV20): `Runtime.getRuntime().maxMemory()` returns the JVM heap
 * cap, which on Android is ~512 MB by default — NOT the physical device RAM.
 * All three Android example apps (Kotlin, RN, Flutter) were surfacing 512 MB
 * on a 6 GB Pixel 6a because of this. This helper prefers, in order:
 *
 *   1. `ActivityManager.MemoryInfo.totalMem` via reflection (most accurate).
 *   2. `/proc/meminfo` `MemTotal` parse (works without an Android Context).
 *   3. `Runtime.getRuntime().maxMemory()` as a last-resort desktop JVM fallback.
 *
 * Uses reflection so this file compiles cleanly in `jvmAndroidMain` (which is
 * shared between desktop JVM and Android) without a hard dependency on
 * `android.*` classes.
 */

package com.runanywhere.sdk.foundation.device

import java.io.File

internal object PhysicalMemoryProbe {
    /**
     * Return total physical RAM on this device/host, in bytes.
     *
     * Never throws — falls back to JVM `Runtime.maxMemory()` if every platform
     * probe fails. Callers that treat `0` as "unknown" should check the return
     * value, but this function always returns a positive number on a healthy
     * system.
     */
    fun totalPhysicalMemoryBytes(): Long {
        activityManagerTotalMem()?.takeIf { it > 0L }?.let { return it }
        procMemInfoTotalBytes()?.takeIf { it > 0L }?.let { return it }
        return Runtime.getRuntime().maxMemory()
    }

    /**
     * Convenience: same value in megabytes (integer division, floored).
     */
    fun totalPhysicalMemoryMB(): Long = totalPhysicalMemoryBytes() / (1024L * 1024L)

    /**
     * Android path — uses reflection so this code compiles on desktop JVM.
     * Acquires the current Application context via `ActivityThread` and calls
     * `ActivityManager.getMemoryInfo`.
     *
     * Returns null if we're not on Android, or the Android APIs aren't available
     * (e.g. context not yet initialised).
     */
    private fun activityManagerTotalMem(): Long? {
        return try {
            val contextClass = Class.forName("android.content.Context")
            val activityService =
                contextClass.getField("ACTIVITY_SERVICE").get(null) as? String ?: return null

            val activityThreadClass = Class.forName("android.app.ActivityThread")
            val context = activityThreadClass.getMethod("currentApplication").invoke(null) ?: return null

            val activityManager =
                contextClass
                    .getMethod("getSystemService", String::class.java)
                    .invoke(context, activityService) ?: return null

            val memInfoClass = Class.forName("android.app.ActivityManager\$MemoryInfo")
            val memInfo = memInfoClass.getDeclaredConstructor().newInstance()
            activityManager.javaClass
                .getMethod("getMemoryInfo", memInfoClass)
                .invoke(activityManager, memInfo)

            memInfoClass.getField("totalMem").getLong(memInfo)
        } catch (_: Throwable) {
            null
        }
    }

    /**
     * Linux/Android fallback — parses `/proc/meminfo`. `MemTotal` is reported
     * in kilobytes, e.g. `MemTotal:        5878160 kB`.
     *
     * Returns null on any parse error or if the file is absent (e.g. on macOS
     * Darwin where /proc does not exist).
     */
    private fun procMemInfoTotalBytes(): Long? {
        return try {
            val file = File("/proc/meminfo")
            if (!file.exists()) return null
            file.useLines { lines ->
                lines
                    .firstOrNull { it.startsWith("MemTotal:") }
                    ?.split(Regex("\\s+"))
                    ?.getOrNull(1)
                    ?.toLongOrNull()
                    ?.times(1024L)
            }
        } catch (_: Throwable) {
            null
        }
    }
}
