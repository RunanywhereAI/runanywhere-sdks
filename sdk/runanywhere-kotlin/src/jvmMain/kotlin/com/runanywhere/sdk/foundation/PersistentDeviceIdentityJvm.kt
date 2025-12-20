package com.runanywhere.sdk.foundation

import java.lang.management.ManagementFactory
import java.net.InetAddress
import java.security.MessageDigest

/**
 * JVM-specific implementations for PersistentDeviceIdentity
 * Collects comprehensive device information including:
 * - Architecture, core count, memory, OS version
 * - Device model (hostname)
 * - Platform info
 */

/**
 * Get platform vendor UUID - uses hardware identifiers when available
 */
actual suspend fun getPlatformVendorUUID(): String? =
    try {
        // Try to create a stable identifier based on hardware characteristics
        val identifier =
            buildString {
                append(System.getProperty("user.name", ""))
                append(System.getProperty("os.name", ""))
                append(System.getProperty("os.arch", ""))
                append(System.getProperty("java.vm.vendor", ""))

                // Try to get hostname as a stable identifier
                try {
                    append(InetAddress.getLocalHost().hostName)
                } catch (e: Exception) {
                    append("localhost")
                }

                // Add hardware serial if available (requires special permissions)
                try {
                    val systemSerial = System.getProperty("system.serial")
                    if (!systemSerial.isNullOrBlank()) {
                        append(systemSerial)
                    }
                } catch (e: Exception) {
                    // Ignore - not available
                }
            }

        // Create a stable UUID from the identifier
        val digest = MessageDigest.getInstance("SHA-256")
        val hash = digest.digest(identifier.toByteArray())

        // Format as UUID
        val bytes = hash.take(16).toByteArray()
        bytes[6] = (bytes[6].toInt() and 0x0f or 0x40).toByte() // Version 4
        bytes[8] = (bytes[8].toInt() and 0x3f or 0x80).toByte() // Variant bits

        val uuid =
            "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x".format(
                bytes[0],
                bytes[1],
                bytes[2],
                bytes[3],
                bytes[4],
                bytes[5],
                bytes[6],
                bytes[7],
                bytes[8],
                bytes[9],
                bytes[10],
                bytes[11],
                bytes[12],
                bytes[13],
                bytes[14],
                bytes[15],
            )

        uuid
    } catch (e: Exception) {
        // Return null to fall back to generated UUID
        null
    }

/**
 * Get comprehensive platform device information for fingerprinting
 */
actual fun getPlatformDeviceInfo(): PlatformDeviceInfo {
    val runtime = Runtime.getRuntime()
    val osBean = ManagementFactory.getOperatingSystemMXBean()

    // Get total memory
    val totalMemory = runtime.maxMemory()

    // Get architecture
    val architecture = System.getProperty("os.arch", "unknown")

    // Get core count
    val coreCount = runtime.availableProcessors()

    // Get device model (hostname + JVM info)
    val deviceModel =
        try {
            val hostname = InetAddress.getLocalHost().hostName
            val jvmName = System.getProperty("java.vm.name", "Unknown JVM")
            "$hostname ($jvmName)"
        } catch (e: Exception) {
            "JVM-${System.getProperty("java.vm.name", "Unknown")}"
        }

    // Get OS major version
    val osMajorVersion =
        try {
            val osVersion = System.getProperty("os.version", "unknown")
            // Extract major version (e.g., "10.15.7" -> "10")
            osVersion.split(".").firstOrNull() ?: osVersion
        } catch (e: Exception) {
            "unknown"
        }

    return PlatformDeviceInfo(
        totalMemory = totalMemory,
        architecture = architecture,
        coreCount = coreCount,
        deviceModel = deviceModel,
        osMajorVersion = osMajorVersion,
    )
}

/**
 * Platform-specific SHA256 implementation
 */
actual fun platformSha256(input: String): String =
    try {
        val digest = MessageDigest.getInstance("SHA-256")
        val hash = digest.digest(input.toByteArray(Charsets.UTF_8))
        hash.joinToString("") { "%02x".format(it) }
    } catch (e: Exception) {
        // Fallback to hashCode if SHA256 is not available
        input.hashCode().toString(16)
    }

/**
 * Extended JVM device information collector
 * Provides comprehensive system information for device registration
 */
object JvmDeviceInfoCollector {
    /**
     * Collect comprehensive device information for registration
     */
    fun collectDeviceInfo(): Map<String, Any> {
        val info = mutableMapOf<String, Any>()
        val runtime = Runtime.getRuntime()
        val osBean = ManagementFactory.getOperatingSystemMXBean()

        try {
            // Basic system information
            info["platform"] = "JVM"
            info["os_name"] = System.getProperty("os.name", "unknown")
            info["os_version"] = System.getProperty("os.version", "unknown")
            info["os_arch"] = System.getProperty("os.arch", "unknown")

            // JVM information
            info["java_version"] = System.getProperty("java.version", "unknown")
            info["java_vendor"] = System.getProperty("java.vendor", "unknown")
            info["jvm_name"] = System.getProperty("java.vm.name", "unknown")
            info["jvm_version"] = System.getProperty("java.vm.version", "unknown")

            // Hardware information
            info["processor_count"] = runtime.availableProcessors()
            info["max_memory"] = runtime.maxMemory()
            info["total_memory"] = runtime.totalMemory()
            info["free_memory"] = runtime.freeMemory()

            // System load if available
            try {
                val systemLoad = osBean.systemLoadAverage
                if (systemLoad >= 0) {
                    info["system_load"] = systemLoad
                }
            } catch (e: Exception) {
                // Not available on all systems
            }

            // Network information
            try {
                val localhost = InetAddress.getLocalHost()
                info["hostname"] = localhost.hostName
                info["host_address"] = localhost.hostAddress
            } catch (e: Exception) {
                info["hostname"] = "localhost"
                info["host_address"] = "127.0.0.1"
            }

            // User information (non-sensitive)
            info["user_language"] = System.getProperty("user.language", "unknown")
            info["user_country"] = System.getProperty("user.country", "unknown")
            info["user_timezone"] = System.getProperty("user.timezone", "unknown")

            // File system information
            info["file_separator"] = System.getProperty("file.separator", "/")
            info["path_separator"] = System.getProperty("path.separator", ":")
            info["line_separator"] = System.getProperty("line.separator", "\n")

            // Additional system properties
            info["temp_dir"] = System.getProperty("java.io.tmpdir", "unknown")
            info["class_path"] = System.getProperty("java.class.path", "unknown").length // Just the length for privacy
        } catch (e: Exception) {
            info["collection_error"] = e.message ?: "Unknown error"
        }

        return info
    }

    /**
     * Get device capabilities assessment
     */
    fun getDeviceCapabilities(): Map<String, Any> {
        val capabilities = mutableMapOf<String, Any>()
        val runtime = Runtime.getRuntime()

        try {
            val maxMemoryMB = runtime.maxMemory() / (1024 * 1024)
            val processors = runtime.availableProcessors()

            // Memory capability
            capabilities["memory_tier"] =
                when {
                    maxMemoryMB >= 16384 -> "high" // 16GB+
                    maxMemoryMB >= 8192 -> "medium" // 8GB+
                    maxMemoryMB >= 4096 -> "low" // 4GB+
                    else -> "minimal" // < 4GB
                }

            // CPU capability
            capabilities["cpu_tier"] =
                when {
                    processors >= 16 -> "high" // 16+ cores
                    processors >= 8 -> "medium" // 8+ cores
                    processors >= 4 -> "low" // 4+ cores
                    else -> "minimal" // < 4 cores
                }

            // Overall capability score (0-100)
            var score = 0
            score +=
                when {
                    maxMemoryMB >= 16384 -> 40
                    maxMemoryMB >= 8192 -> 30
                    maxMemoryMB >= 4096 -> 20
                    else -> 10
                }
            score +=
                when {
                    processors >= 16 -> 30
                    processors >= 8 -> 20
                    processors >= 4 -> 15
                    else -> 5
                }
            // Add bonus for 64-bit architecture
            if (System.getProperty("os.arch", "").contains("64")) {
                score += 10
            }
            // Add bonus for modern JVM
            val javaVersion = System.getProperty("java.version", "8")
            if (javaVersion.startsWith("11") || javaVersion.startsWith("17") || javaVersion.startsWith("21")) {
                score += 10
            }

            capabilities["capability_score"] = minOf(score, 100)
            capabilities["recommended_models"] =
                when {
                    score >= 80 -> listOf("large", "medium", "small", "tiny")
                    score >= 60 -> listOf("medium", "small", "tiny")
                    score >= 40 -> listOf("small", "tiny")
                    else -> listOf("tiny")
                }
        } catch (e: Exception) {
            capabilities["error"] = e.message ?: "Unknown error"
        }

        return capabilities
    }
}
