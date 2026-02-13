#pragma once

#include "rac/core/rac_types.h"
#include <cstdint>
#include <string>
#include <vector>

namespace runanywhere {

/**
 * @brief Information about a Vulkan-capable GPU device
 */
struct RAC_API VulkanDeviceInfo {
    bool is_available = false;
    std::string device_name;
    std::string driver_version;
    uint32_t api_version = 0;
    size_t max_memory_mb = 0;
    bool supports_compute = false;
    int device_id = -1;
};

/**
 * @brief Vulkan GPU detection and capability checking
 * 
 * Detects Vulkan-capable GPUs on Android devices and provides
 * information about their capabilities for ML inference.
 */
class RAC_API VulkanDetector {
public:
    /**
     * @brief Detect the primary Vulkan GPU device
     * @return VulkanDeviceInfo with device details, or empty if unavailable
     */
    static VulkanDeviceInfo detect();
    
    /**
     * @brief Check if Vulkan is supported on this device
     * @return true if at least one Vulkan-capable GPU is available
     */
    static bool is_vulkan_supported();
    
    /**
     * @brief List all available Vulkan devices
     * @return Vector of VulkanDeviceInfo for all detected devices
     */
    static std::vector<VulkanDeviceInfo> list_devices();
    
    /**
     * @brief Get human-readable Vulkan version string
     * @param api_version Vulkan API version number
     * @return Version string (e.g., "1.3.0")
     */
    static std::string get_version_string(uint32_t api_version);
};

}  // namespace runanywhere
