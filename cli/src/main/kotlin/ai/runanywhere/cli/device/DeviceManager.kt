package ai.runanywhere.cli.device

import java.io.BufferedReader

/**
 * Manages connected iOS and Android devices
 */
class DeviceManager {
    
    /**
     * List all connected iOS devices and simulators
     */
    fun listIOSDevices(): List<IOSDeviceInfo> {
        val devices = mutableListOf<IOSDeviceInfo>()
        
        // List simulators
        try {
            val simulatorOutput = runCommand("xcrun", "simctl", "list", "devices", "-j")
            devices.addAll(parseSimulators(simulatorOutput))
        } catch (e: Exception) {
            // xcrun not available
        }
        
        // List physical devices using ios-deploy or idevice_id
        try {
            // Try idevice_id first (from libimobiledevice)
            val physicalOutput = runCommand("idevice_id", "-l")
            val udids = physicalOutput.lines().filter { it.isNotBlank() }
            
            udids.forEach { udid ->
                val name = runCommand("idevicename", "-u", udid).trim()
                val version = runCommand("ideviceinfo", "-u", udid, "-k", "ProductVersion").trim()
                
                devices.add(IOSDeviceInfo(
                    udid = udid,
                    name = name.ifBlank { "iOS Device" },
                    osVersion = version.ifBlank { "Unknown" },
                    isSimulator = false
                ))
            }
        } catch (e: Exception) {
            // libimobiledevice not installed, try ios-deploy
            try {
                val deployOutput = runCommand("ios-deploy", "--detect", "--no-wifi")
                // Parse ios-deploy output
            } catch (e2: Exception) {
                // No physical device tools available
            }
        }
        
        return devices
    }
    
    /**
     * List all connected Android devices and emulators
     */
    fun listAndroidDevices(): List<AndroidDeviceInfo> {
        val devices = mutableListOf<AndroidDeviceInfo>()
        
        try {
            val output = runCommand("adb", "devices", "-l")
            
            output.lines()
                .drop(1) // Skip "List of devices attached" header
                .filter { it.isNotBlank() && it.contains("device") && !it.contains("offline") }
                .forEach { line ->
                    val parts = line.split("\\s+".toRegex())
                    if (parts.isNotEmpty()) {
                        val serial = parts[0]
                        val isEmulator = serial.startsWith("emulator")
                        
                        // Get device properties
                        val model = getAdbProperty(serial, "ro.product.model") ?: "Unknown"
                        val manufacturer = getAdbProperty(serial, "ro.product.manufacturer") ?: ""
                        val apiLevel = getAdbProperty(serial, "ro.build.version.sdk") ?: "0"
                        
                        devices.add(AndroidDeviceInfo(
                            serial = serial,
                            model = "$manufacturer $model".trim(),
                            apiLevel = apiLevel.toIntOrNull() ?: 0,
                            isEmulator = isEmulator
                        ))
                    }
                }
        } catch (e: Exception) {
            // adb not available
        }
        
        return devices
    }
    
    private fun parseSimulators(json: String): List<IOSDeviceInfo> {
        val devices = mutableListOf<IOSDeviceInfo>()
        
        // Simple JSON parsing for simulator list
        // Format: "devices": { "iOS-17.2": [...] }
        try {
            val devicesSection = json.substringAfter("\"devices\"")
                .substringAfter("{")
                .substringBefore("}")
            
            // Find booted simulators
            val bootedPattern = """"udid"\s*:\s*"([^"]+)"[^}]*"state"\s*:\s*"Booted"[^}]*"name"\s*:\s*"([^"]+)"""".toRegex()
            val altPattern = """"name"\s*:\s*"([^"]+)"[^}]*"state"\s*:\s*"Booted"[^}]*"udid"\s*:\s*"([^"]+)"""".toRegex()
            
            // Simpler approach: find all booted devices
            val runtimePattern = """"com\.apple\.CoreSimulator\.SimRuntime\.(iOS|watchOS|tvOS)-(\d+-\d+)"""".toRegex()
            
            // For now, use xcrun simctl to get booted devices directly
            val bootedOutput = runCommand("xcrun", "simctl", "list", "devices", "booted")
            
            bootedOutput.lines().forEach { line ->
                // Format: "    iPhone 15 Pro (UDID) (Booted)"
                val match = """^\s+(.+?)\s+\(([A-F0-9-]+)\)\s+\(Booted\)""".toRegex().find(line)
                if (match != null) {
                    val (name, udid) = match.destructured
                    
                    // Get runtime version
                    val infoOutput = runCommand("xcrun", "simctl", "list", "devices", "-j")
                    val versionMatch = """"$udid"[^}]*"isAvailable"[^}]*"runtimeIdentifier"[^}]*iOS-(\d+)-(\d+)""".toRegex()
                        .find(infoOutput)
                    val version = versionMatch?.let { "${it.groupValues[1]}.${it.groupValues[2]}" } ?: "17.0"
                    
                    devices.add(IOSDeviceInfo(
                        udid = udid,
                        name = name.trim(),
                        osVersion = version,
                        isSimulator = true
                    ))
                }
            }
        } catch (e: Exception) {
            // Parsing failed
        }
        
        return devices
    }
    
    private fun getAdbProperty(serial: String, property: String): String? {
        return try {
            runCommand("adb", "-s", serial, "shell", "getprop", property).trim()
        } catch (e: Exception) {
            null
        }
    }
    
    private fun runCommand(vararg args: String): String {
        val process = ProcessBuilder(*args)
            .redirectErrorStream(true)
            .start()
        
        val output = process.inputStream.bufferedReader().use(BufferedReader::readText)
        process.waitFor()
        
        return output
    }
}

/**
 * iOS device information
 */
data class IOSDeviceInfo(
    val udid: String,
    val name: String,
    val osVersion: String,
    val isSimulator: Boolean,
)

/**
 * Android device information
 */
data class AndroidDeviceInfo(
    val serial: String,
    val model: String,
    val apiLevel: Int,
    val isEmulator: Boolean,
)
