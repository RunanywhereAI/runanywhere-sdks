#include "rac/infrastructure/device/vulkan_detector.h"
#include "rac/core/rac_logger.h"

#include <sstream>

#ifdef __ANDROID__
#include <unistd.h>
#include <sys/wait.h>
#include <signal.h>
#endif

#ifdef GGML_USE_VULKAN
#include <vulkan/vulkan.h>

// Fallback for older Vulkan headers that don't define these macros
#ifndef VK_VERSION_MAJOR
#define VK_VERSION_MAJOR(version) ((uint32_t)(version) >> 22)
#endif
#ifndef VK_VERSION_MINOR
#define VK_VERSION_MINOR(version) (((uint32_t)(version) >> 12) & 0x3ff)
#endif
#ifndef VK_VERSION_PATCH
#define VK_VERSION_PATCH(version) ((uint32_t)(version) & 0xfff)
#endif
#endif

namespace runanywhere {

#ifdef __ANDROID__
// Fork-based safe Vulkan detection for buggy Android drivers
static bool test_vulkan_in_child_process() {
    RAC_LOG_INFO("VulkanDetector", "Testing Vulkan in child process (safe mode)...");
    
    pid_t pid = fork();
    
    if (pid == -1) {
        RAC_LOG_ERROR("VulkanDetector", "Fork failed, assuming Vulkan unavailable");
        return false;
    }
    
    if (pid == 0) {
        // Child process - test Vulkan
        // If driver crashes here, only child dies
        
#ifdef GGML_USE_VULKAN
        VkInstance instance = VK_NULL_HANDLE;
        VkInstanceCreateInfo create_info = {};
        create_info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
        
        VkResult result = vkCreateInstance(&create_info, nullptr, &instance);
        if (result != VK_SUCCESS) {
            _exit(1);  // Failed
        }
        
        uint32_t device_count = 0;
        vkEnumeratePhysicalDevices(instance, &device_count, nullptr);
        
        if (device_count == 0) {
            vkDestroyInstance(instance, nullptr);
            _exit(1);  // No devices
        }
        
        // Test actual device creation (this is where buggy drivers crash)
        std::vector<VkPhysicalDevice> devices(device_count);
        vkEnumeratePhysicalDevices(instance, &device_count, devices.data());
        
        // Try to create a logical device (fence creation happens here)
        VkDeviceQueueCreateInfo queue_info = {};
        queue_info.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        queue_info.queueFamilyIndex = 0;
        queue_info.queueCount = 1;
        float priority = 1.0f;
        queue_info.pQueuePriorities = &priority;
        
        VkDeviceCreateInfo device_info = {};
        device_info.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
        device_info.queueCreateInfoCount = 1;
        device_info.pQueueCreateInfos = &queue_info;
        
        VkDevice device = VK_NULL_HANDLE;
        result = vkCreateDevice(devices[0], &device_info, nullptr, &device);
        
        if (device != VK_NULL_HANDLE) {
            vkDestroyDevice(device, nullptr);
        }
        
        vkDestroyInstance(instance, nullptr);
        
        // If we got here without crashing, Vulkan works!
        _exit(result == VK_SUCCESS ? 0 : 1);
#else
        _exit(1);  // Vulkan not compiled
#endif
    }
    
    // Parent process - wait for child
    int status;
    pid_t result = waitpid(pid, &status, 0);
    
    if (result == -1) {
        RAC_LOG_ERROR("VulkanDetector", "waitpid failed");
        return false;
    }
    
    if (WIFEXITED(status)) {
        int exit_code = WEXITSTATUS(status);
        if (exit_code == 0) {
            RAC_LOG_INFO("VulkanDetector", "✅ Vulkan test passed in child process");
            return true;
        } else {
            RAC_LOG_WARNING("VulkanDetector", "❌ Vulkan test failed in child (exit code: %d)", exit_code);
            return false;
        }
    }
    
    if (WIFSIGNALED(status)) {
        int signal = WTERMSIG(status);
        RAC_LOG_ERROR("VulkanDetector", "❌ Child process crashed with signal %d (SIGSEGV=%d) - BUGGY DRIVER DETECTED!", 
                     signal, SIGSEGV);
        RAC_LOG_ERROR("VulkanDetector", "This device has a buggy Vulkan driver. Using CPU fallback.");
        return false;
    }
    
    return false;
}
#endif

VulkanDeviceInfo VulkanDetector::detect() {
    VulkanDeviceInfo info;
    
#ifdef GGML_USE_VULKAN
    
#ifdef __ANDROID__
    // On Android, use fork-based safe detection first
    if (!test_vulkan_in_child_process()) {
        RAC_LOG_WARNING("VulkanDetector", "Vulkan not available or driver is buggy - using CPU");
        return info;  // Return unavailable
    }
    RAC_LOG_INFO("VulkanDetector", "Vulkan driver verified safe, proceeding with detection...");
#endif
    
    try {
        RAC_LOG_INFO("VulkanDetector", "Detecting Vulkan GPU...");
        
        // Create Vulkan instance
        VkInstance instance = VK_NULL_HANDLE;
        VkInstanceCreateInfo create_info = {};
        create_info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
        create_info.pApplicationInfo = nullptr;
        create_info.enabledLayerCount = 0;
        create_info.enabledExtensionCount = 0;
        
        VkResult result = vkCreateInstance(&create_info, nullptr, &instance);
        if (result != VK_SUCCESS) {
            RAC_LOG_WARNING("VulkanDetector", "Failed to create Vulkan instance: %d", result);
            return info;
        }
        
        // Enumerate physical devices
        uint32_t device_count = 0;
        vkEnumeratePhysicalDevices(instance, &device_count, nullptr);
        
        if (device_count == 0) {
            RAC_LOG_WARNING("VulkanDetector", "No Vulkan devices found");
            vkDestroyInstance(instance, nullptr);
            return info;
        }
        
        RAC_LOG_INFO("VulkanDetector", "Found %u Vulkan device(s)", device_count);
        
        std::vector<VkPhysicalDevice> devices(device_count);
        vkEnumeratePhysicalDevices(instance, &device_count, devices.data());
        
        // Get properties of first GPU device
        VkPhysicalDeviceProperties props;
        vkGetPhysicalDeviceProperties(devices[0], &props);
        
        info.is_available = true;
        info.device_name = props.deviceName;
        info.api_version = props.apiVersion;
        info.device_id = 0;
        
        // Format driver version
        std::ostringstream driver_ver;
        driver_ver << VK_VERSION_MAJOR(props.driverVersion) << "."
                   << VK_VERSION_MINOR(props.driverVersion) << "."
                   << VK_VERSION_PATCH(props.driverVersion);
        info.driver_version = driver_ver.str();
        
        // Get memory properties
        VkPhysicalDeviceMemoryProperties mem_props;
        vkGetPhysicalDeviceMemoryProperties(devices[0], &mem_props);
        
        // Calculate total GPU memory (device-local heaps)
        for (uint32_t i = 0; i < mem_props.memoryHeapCount; i++) {
            if (mem_props.memoryHeaps[i].flags & VK_MEMORY_HEAP_DEVICE_LOCAL_BIT) {
                info.max_memory_mb += mem_props.memoryHeaps[i].size / (1024 * 1024);
            }
        }
        
        // Check for compute queue support
        uint32_t queue_family_count = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(devices[0], &queue_family_count, nullptr);
        
        std::vector<VkQueueFamilyProperties> queue_families(queue_family_count);
        vkGetPhysicalDeviceQueueFamilyProperties(devices[0], &queue_family_count, queue_families.data());
        
        for (const auto& queue_family : queue_families) {
            if (queue_family.queueFlags & VK_QUEUE_COMPUTE_BIT) {
                info.supports_compute = true;
                break;
            }
        }
        
        RAC_LOG_INFO("VulkanDetector", "GPU: %s", info.device_name.c_str());
        RAC_LOG_INFO("VulkanDetector", "Vulkan API: %s", get_version_string(info.api_version).c_str());
        RAC_LOG_INFO("VulkanDetector", "Driver: %s", info.driver_version.c_str());
        RAC_LOG_INFO("VulkanDetector", "VRAM: %zu MB", info.max_memory_mb);
        RAC_LOG_INFO("VulkanDetector", "Compute support: %s", info.supports_compute ? "Yes" : "No");
        
        vkDestroyInstance(instance, nullptr);
    } catch (const std::exception& e) {
        RAC_LOG_ERROR("VulkanDetector", "Exception during Vulkan detection: %s", e.what());
        info = VulkanDeviceInfo();  // Reset to default (not available)
    } catch (...) {
        RAC_LOG_ERROR("VulkanDetector", "Unknown exception during Vulkan detection");
        info = VulkanDeviceInfo();  // Reset to default (not available)
    }
#else
    RAC_LOG_WARNING("VulkanDetector", "Vulkan support not compiled in (GGML_USE_VULKAN not defined)");
#endif
    
    return info;
}

bool VulkanDetector::is_vulkan_supported() {
#ifdef GGML_USE_VULKAN
    return detect().is_available;
#else
    return false;
#endif
}

std::vector<VulkanDeviceInfo> VulkanDetector::list_devices() {
    std::vector<VulkanDeviceInfo> device_list;
    
#ifdef GGML_USE_VULKAN
    VkInstance instance = VK_NULL_HANDLE;
    VkInstanceCreateInfo create_info = {};
    create_info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    
    if (vkCreateInstance(&create_info, nullptr, &instance) != VK_SUCCESS) {
        return device_list;
    }
    
    uint32_t device_count = 0;
    vkEnumeratePhysicalDevices(instance, &device_count, nullptr);
    
    if (device_count > 0) {
        std::vector<VkPhysicalDevice> devices(device_count);
        vkEnumeratePhysicalDevices(instance, &device_count, devices.data());
        
        for (uint32_t i = 0; i < device_count; i++) {
            VulkanDeviceInfo info;
            
            VkPhysicalDeviceProperties props;
            vkGetPhysicalDeviceProperties(devices[i], &props);
            
            info.is_available = true;
            info.device_name = props.deviceName;
            info.api_version = props.apiVersion;
            info.device_id = i;
            
            std::ostringstream driver_ver;
            driver_ver << VK_VERSION_MAJOR(props.driverVersion) << "."
                       << VK_VERSION_MINOR(props.driverVersion) << "."
                       << VK_VERSION_PATCH(props.driverVersion);
            info.driver_version = driver_ver.str();
            
            VkPhysicalDeviceMemoryProperties mem_props;
            vkGetPhysicalDeviceMemoryProperties(devices[i], &mem_props);
            
            for (uint32_t j = 0; j < mem_props.memoryHeapCount; j++) {
                if (mem_props.memoryHeaps[j].flags & VK_MEMORY_HEAP_DEVICE_LOCAL_BIT) {
                    info.max_memory_mb += mem_props.memoryHeaps[j].size / (1024 * 1024);
                }
            }
            
            uint32_t queue_family_count = 0;
            vkGetPhysicalDeviceQueueFamilyProperties(devices[i], &queue_family_count, nullptr);
            
            std::vector<VkQueueFamilyProperties> queue_families(queue_family_count);
            vkGetPhysicalDeviceQueueFamilyProperties(devices[i], &queue_family_count, queue_families.data());
            
            for (const auto& queue_family : queue_families) {
                if (queue_family.queueFlags & VK_QUEUE_COMPUTE_BIT) {
                    info.supports_compute = true;
                    break;
                }
            }
            
            device_list.push_back(info);
        }
    }
    
    vkDestroyInstance(instance, nullptr);
#endif
    
    return device_list;
}

std::string VulkanDetector::get_version_string(uint32_t api_version) {
#ifdef GGML_USE_VULKAN
    std::ostringstream version;
    version << VK_VERSION_MAJOR(api_version) << "."
            << VK_VERSION_MINOR(api_version) << "."
            << VK_VERSION_PATCH(api_version);
    return version.str();
#else
    return "N/A";
#endif
}

}  // namespace runanywhere
