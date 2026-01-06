#ifndef RUNANYWHERE_BACKEND_H
#define RUNANYWHERE_BACKEND_H

#include "capability.h"
#include "diarization.h"
#include "embeddings.h"
#include "stt.h"
#include "text_generation.h"
#include "tts.h"
#include "vad.h"

#include <memory>
#include <mutex>
#include <unordered_map>
#include <unordered_set>

namespace runanywhere {

// Backend information
struct BackendInfo {
    std::string name;  // "onnx", "llamacpp", "coreml", etc.
    std::string version;
    std::string description;
    std::vector<CapabilityType> supported_capabilities;
    nlohmann::json metadata;
};

// Base Backend class - all backends inherit from this
class Backend {
   public:
    virtual ~Backend() = default;

    // Get backend info
    virtual BackendInfo get_info() const = 0;

    // Initialize the backend with configuration
    virtual bool initialize(const nlohmann::json& config = {}) = 0;

    // Check if backend is initialized
    virtual bool is_initialized() const = 0;

    // Cleanup all resources
    virtual void cleanup() = 0;

    // --- Capability Management ---

    // Check if backend supports a capability
    bool supports(CapabilityType type) const {
        std::lock_guard<std::mutex> lock(mutex_);
        return capabilities_.find(type) != capabilities_.end();
    }

    // Get all supported capabilities
    std::vector<CapabilityType> get_supported_capabilities() const {
        std::lock_guard<std::mutex> lock(mutex_);
        std::vector<CapabilityType> result;
        for (const auto& [type, _] : capabilities_) {
            result.push_back(type);
        }
        return result;
    }

    // Get a capability by type (returns nullptr if not supported)
    // NOTE: Uses static_cast instead of dynamic_cast to avoid RTTI issues
    // across shared library boundaries (e.g., Android .so files).
    // This is safe because we know the exact type from the CapabilityType enum.
    template <typename T>
    T* get_capability() {
        static_assert(std::is_base_of<ICapability, T>::value, "T must derive from ICapability");
        std::lock_guard<std::mutex> lock(mutex_);

        // Determine capability type from T
        CapabilityType type;
        if constexpr (std::is_same_v<T, ITextGeneration>) {
            type = CapabilityType::TEXT_GENERATION;
        } else if constexpr (std::is_same_v<T, IEmbeddings>) {
            type = CapabilityType::EMBEDDINGS;
        } else if constexpr (std::is_same_v<T, ISTT>) {
            type = CapabilityType::STT;
        } else if constexpr (std::is_same_v<T, ITTS>) {
            type = CapabilityType::TTS;
        } else if constexpr (std::is_same_v<T, IVAD>) {
            type = CapabilityType::VAD;
        } else if constexpr (std::is_same_v<T, IDiarization>) {
            type = CapabilityType::DIARIZATION;
        } else {
            return nullptr;
        }

        auto it = capabilities_.find(type);
        if (it != capabilities_.end()) {
            // Use static_cast - safe because capability type is enforced by the enum key
            return static_cast<T*>(it->second.get());
        }
        return nullptr;
    }

    // Get capability by type enum
    ICapability* get_capability(CapabilityType type) {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = capabilities_.find(type);
        if (it != capabilities_.end()) {
            return it->second.get();
        }
        return nullptr;
    }

    // --- Device & Memory ---

    // Get device type being used
    virtual ra_device_type get_device_type() const = 0;

    // Get memory usage in bytes
    virtual size_t get_memory_usage() const = 0;

   protected:
    // Register a capability (called by derived backends)
    void register_capability(CapabilityType type, std::unique_ptr<ICapability> capability) {
        std::lock_guard<std::mutex> lock(mutex_);
        capabilities_[type] = std::move(capability);
    }

    // Unregister a capability
    void unregister_capability(CapabilityType type) {
        std::lock_guard<std::mutex> lock(mutex_);
        capabilities_.erase(type);
    }

    // Clear all capabilities
    void clear_capabilities() {
        std::lock_guard<std::mutex> lock(mutex_);
        capabilities_.clear();
    }

   private:
    mutable std::mutex mutex_;
    std::unordered_map<CapabilityType, std::unique_ptr<ICapability>> capabilities_;
};

// Backend factory function type
using BackendFactory = std::unique_ptr<Backend> (*)();

// Backend Registry - manages all available backends
// Uses a global pointer pattern to ensure single instance across shared libraries
class BackendRegistry {
   public:
    static BackendRegistry& instance() {
        static BackendRegistry registry;
        return registry;
    }

    // Register a backend factory
    void register_backend(const std::string& name, BackendFactory factory) {
        std::lock_guard<std::mutex> lock(mutex_);
        factories_[name] = factory;
    }

    // Create a backend instance by name
    std::unique_ptr<Backend> create(const std::string& name) {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = factories_.find(name);
        if (it != factories_.end()) {
            return it->second();
        }
        return nullptr;
    }

    // Get all registered backend names
    std::vector<std::string> get_available_backends() const {
        std::lock_guard<std::mutex> lock(mutex_);
        std::vector<std::string> names;
        for (const auto& [name, _] : factories_) {
            names.push_back(name);
        }
        return names;
    }

    // Check if a backend is registered
    bool has_backend(const std::string& name) const {
        std::lock_guard<std::mutex> lock(mutex_);
        return factories_.find(name) != factories_.end();
    }

   private:
    BackendRegistry() = default;
    BackendRegistry(const BackendRegistry&) = delete;
    BackendRegistry& operator=(const BackendRegistry&) = delete;

    mutable std::mutex mutex_;
    std::unordered_map<std::string, BackendFactory> factories_;
};

// Helper macro to register a backend
#define REGISTER_BACKEND(name, BackendClass)                                                      \
    namespace {                                                                                   \
    static bool _registered_##BackendClass = []() {                                               \
        BackendRegistry::instance().register_backend(                                             \
            name, []() -> std::unique_ptr<Backend> { return std::make_unique<BackendClass>(); }); \
        return true;                                                                              \
    }();                                                                                          \
    }

}  // namespace runanywhere

#endif  // RUNANYWHERE_BACKEND_H
