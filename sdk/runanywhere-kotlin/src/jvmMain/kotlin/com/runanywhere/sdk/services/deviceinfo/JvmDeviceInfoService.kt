package com.runanywhere.sdk.services.deviceinfo

import com.runanywhere.sdk.foundation.SDKLogger
import java.net.InetAddress
import java.security.MessageDigest

/**
 * JVM Device Info Service
 * Provides device information using JVM system properties
 */
class JvmDeviceInfoService {

    private val logger = SDKLogger("JvmDeviceInfoService")
    private var deviceId: String? = null

    suspend fun initialize() {
        deviceId = generateDeviceId()
        logger.info("Device info service initialized for ${getPlatformName()}")
    }

    fun getDeviceId(): String = deviceId ?: generateDeviceId()

    fun getPlatformName(): String = "${System.getProperty("os.name")} ${System.getProperty("os.version")}"

    fun getPlatformVersion(): String = System.getProperty("os.version", "unknown")

    fun getDeviceModel(): String = "JVM ${System.getProperty("java.vm.name", "unknown")}"

    fun getArchitecture(): String = System.getProperty("os.arch", "unknown")

    fun getAvailableMemory(): Long = Runtime.getRuntime().maxMemory()

    fun getJvmVersion(): String = "${System.getProperty("java.vendor")} ${System.getProperty("java.version")}"

    private fun generateDeviceId(): String {
        return try {
            // Create a stable device ID based on system properties
            val identifier = buildString {
                append(System.getProperty("user.name", ""))
                append(System.getProperty("os.name", ""))
                append(System.getProperty("os.arch", ""))
                append(System.getProperty("java.vm.name", ""))
                try {
                    append(InetAddress.getLocalHost().hostName)
                } catch (e: Exception) {
                    append("localhost")
                }
            }

            // Hash the identifier to create a stable device ID
            val digest = MessageDigest.getInstance("SHA-256")
            val hash = digest.digest(identifier.toByteArray())
            "jvm-" + hash.take(8).joinToString("") { "%02x".format(it) }
        } catch (e: Exception) {
            logger.error("Failed to generate device ID", e)
            "jvm-${System.currentTimeMillis().toString(16)}"
        }
    }

    fun getSystemInfo(): Map<String, String> {
        return mapOf(
            "platform" to getPlatformName(),
            "architecture" to getArchitecture(),
            "device_model" to getDeviceModel(),
            "jvm_version" to getJvmVersion(),
            "device_id" to getDeviceId(),
            "available_memory" to getAvailableMemory().toString()
        )
    }
}
