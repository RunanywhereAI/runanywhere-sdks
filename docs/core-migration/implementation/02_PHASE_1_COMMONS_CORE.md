# Phase 1: Commons Core Implementation

**Duration**: 3 weeks
**Objective**: Implement shared logic in C++ that will be used by all backends and platforms.

---

## ⚠️ API Strategy: New `rac_*` APIs, Existing `ra_*` Preserved

The APIs implemented in this phase (`rac_module_*`, `rac_event_*`) are **new orchestration APIs** using the `rac_` prefix. They sit **on top of** the existing `runanywhere-core` C API and do NOT replace it.

### What's New (rac_* prefix)
- Module registry (`rac_module_register`, `rac_module_list`)
- Event publisher (`rac_event_subscribe`, `rac_event_publish`)
- Platform adapter (`rac_set_platform_adapter`)
- Time utilities (`rac_get_current_time_ms`)
- Error handling with new range (`RAC_ERROR_*`)

### What Stays the Same (ra_* prefix, from runanywhere_bridge.h)
- Backend creation: `ra_create_backend()`, `ra_initialize()`
- Capability APIs: `ra_text_*`, `ra_stt_*`, `ra_tts_*`, `ra_vad_*`
- Memory management: `ra_free_string()`, `ra_free_audio()`, etc.

---

## Tasks Overview

| Task ID | Description | Effort | Dependencies |
|---------|-------------|--------|--------------|
| 1.1 | Implement Module Registry | 3 days | Phase 0 |
| 1.2 | Implement Service Provider Registry | 3 days | 1.1 |
| 1.3 | Implement Event Publisher | 2 days | 1.1 |
| 1.4 | Implement Time Utilities | 1 day | Phase 0 |
| 1.5 | Implement Platform Adapter | 2 days | Phase 0 |
| 1.6 | Implement Error Handling | 2 days | Phase 0 |
| 1.7 | Unit Tests | 3 days | All above |

---

## Task 1.1: Module Registry

Port the module registration concept to C++ with process-global singleton pattern.

### Implementation

```cpp
// src/registry/module_registry.cpp

#include "rac_core.h"
#include <mutex>
#include <vector>
#include <algorithm>
#include <unordered_map>
#include <string>
#include <cstring>

namespace runanywhere {
namespace commons {

// =============================================================================
// Process-Global Module Registry
// =============================================================================
// This uses a function-local static pattern which is safe in C++11 and later.
// For shared library builds on Android, the rac_commons.so exports this function,
// and backend libraries link against it to access the same registry instance.

struct ModuleEntry {
    rac_module_info_t info;
    bool is_active;

    ~ModuleEntry() {
        free((void*)info.module_id);
        free((void*)info.module_name);
        free((void*)info.version);
    }
};

class ModuleRegistry {
public:
    // Process-global singleton (via exported symbol for shared libs)
    static ModuleRegistry& instance() {
        static ModuleRegistry registry;
        return registry;
    }

    rac_result_t register_module(const rac_module_info_t* module) {
        if (!module || !module->module_id) {
            return RAC_ERROR_NULL_POINTER;
        }

        std::lock_guard<std::mutex> lock(mutex_);

        // Check for duplicate
        std::string id(module->module_id);
        if (modules_.find(id) != modules_.end()) {
            return RAC_ERROR_ALREADY_INITIALIZED;
        }

        // Deep copy strings
        ModuleEntry entry;
        entry.info.module_id = strdup(module->module_id);
        entry.info.module_name = module->module_name ? strdup(module->module_name) : nullptr;
        entry.info.version = module->version ? strdup(module->version) : nullptr;
        entry.info.capabilities = module->capabilities;
        entry.info.priority = module->priority > 0 ? module->priority : 100;
        entry.is_active = true;

        modules_[id] = std::move(entry);
        return RAC_SUCCESS;
    }

    rac_result_t unregister_module(const char* module_id) {
        if (!module_id) {
            return RAC_ERROR_NULL_POINTER;
        }

        std::lock_guard<std::mutex> lock(mutex_);

        auto it = modules_.find(module_id);
        if (it == modules_.end()) {
            return RAC_ERROR_MODEL_NOT_FOUND;
        }

        modules_.erase(it);
        return RAC_SUCCESS;
    }

    bool is_registered(const char* module_id) {
        if (!module_id) return false;
        std::lock_guard<std::mutex> lock(mutex_);
        return modules_.find(module_id) != modules_.end();
    }

    rac_result_t list_modules(rac_module_info_t** out_modules, size_t* out_count) {
        if (!out_modules || !out_count) {
            return RAC_ERROR_NULL_POINTER;
        }

        std::lock_guard<std::mutex> lock(mutex_);

        *out_count = modules_.size();
        if (*out_count == 0) {
            *out_modules = nullptr;
            return RAC_SUCCESS;
        }

        *out_modules = (rac_module_info_t*)malloc(*out_count * sizeof(rac_module_info_t));
        if (!*out_modules) {
            return RAC_ERROR_OUT_OF_MEMORY;
        }

        size_t i = 0;
        for (const auto& pair : modules_) {
            // Shallow copy - caller must NOT free the strings
            (*out_modules)[i] = pair.second.info;
            i++;
        }

        return RAC_SUCCESS;
    }

    rac_result_t modules_for_capability(
        rac_capability_type_t capability,
        char*** out_ids,
        size_t* out_count
    ) {
        if (!out_ids || !out_count) {
            return RAC_ERROR_NULL_POINTER;
        }

        std::lock_guard<std::mutex> lock(mutex_);

        // Collect matching modules
        std::vector<std::pair<std::string, int32_t>> matches;
        for (const auto& pair : modules_) {
            if (pair.second.info.capabilities & (1 << capability)) {
                matches.emplace_back(pair.first, pair.second.info.priority);
            }
        }

        // Sort by priority (higher first)
        std::sort(matches.begin(), matches.end(),
            [](const auto& a, const auto& b) { return a.second > b.second; });

        *out_count = matches.size();
        if (*out_count == 0) {
            *out_ids = nullptr;
            return RAC_SUCCESS;
        }

        *out_ids = (char**)malloc(*out_count * sizeof(char*));
        if (!*out_ids) {
            return RAC_ERROR_OUT_OF_MEMORY;
        }

        for (size_t i = 0; i < matches.size(); i++) {
            (*out_ids)[i] = strdup(matches[i].first.c_str());
        }

        return RAC_SUCCESS;
    }

    void reset() {
        std::lock_guard<std::mutex> lock(mutex_);
        modules_.clear();
    }

private:
    ModuleRegistry() = default;
    ModuleRegistry(const ModuleRegistry&) = delete;
    ModuleRegistry& operator=(const ModuleRegistry&) = delete;

    std::mutex mutex_;
    std::unordered_map<std::string, ModuleEntry> modules_;
};

// Exported function for cross-library access (Android .so files)
__attribute__((visibility("default")))
ModuleRegistry& get_module_registry() {
    return ModuleRegistry::instance();
}

} // namespace commons
} // namespace runanywhere

// =============================================================================
// C API Implementation
// =============================================================================

extern "C" {

rac_result_t rac_module_register(const rac_module_info_t* module) {
    return runanywhere::commons::get_module_registry().register_module(module);
}

rac_result_t rac_module_unregister(const char* module_id) {
    return runanywhere::commons::get_module_registry().unregister_module(module_id);
}

bool rac_module_is_registered(const char* module_id) {
    return runanywhere::commons::get_module_registry().is_registered(module_id);
}

rac_result_t rac_module_list(rac_module_info_t** modules, size_t* count) {
    return runanywhere::commons::get_module_registry().list_modules(modules, count);
}

void rac_module_list_free(rac_module_info_t* modules, size_t count) {
    if (modules) {
        // Don't free strings - they're owned by the registry
        free(modules);
    }
}

rac_result_t rac_modules_for_capability(
    rac_capability_type_t capability,
    char*** module_ids,
    size_t* count
) {
    return runanywhere::commons::get_module_registry().modules_for_capability(
        capability, module_ids, count
    );
}

} // extern "C"
```

---

## Task 1.2: Service Provider Registry

The service registry allows backends to register capability providers.

### Header Addition (rac_core.h)

```c
// Add to include/rac_core.h

// =============================================================================
// SERVICE PROVIDER REGISTRY
// =============================================================================

/**
 * Callback to check if a provider can handle a model/configuration
 */
typedef bool (*rac_can_handle_fn)(const char* model_id, void* context);

/**
 * Callback to create a service instance
 */
typedef rac_result_t (*rac_create_service_fn)(
    const char* model_id,
    void* config,
    void** out_service,
    void* context
);

/**
 * Callback to destroy a service instance
 */
typedef void (*rac_destroy_service_fn)(void* service, void* context);

/**
 * Capability provider registration
 */
typedef struct {
    rac_capability_type_t capability_type;
    const char* provider_name;
    int32_t priority;  // Higher priority = preferred
    rac_can_handle_fn can_handle;
    rac_create_service_fn create;
    rac_destroy_service_fn destroy;
    void* context;
} rac_capability_provider_t;

/**
 * Register a capability provider.
 * Called by backend modules during initialization.
 */
RAC_API rac_result_t rac_service_register_provider(const rac_capability_provider_t* provider);

/**
 * Create a service for a capability.
 * Uses the highest-priority provider that can handle the model.
 */
RAC_API rac_result_t rac_service_create(
    rac_capability_type_t capability,
    const char* model_id,
    void* config,
    void** out_service
);

/**
 * Destroy a service.
 */
RAC_API rac_result_t rac_service_destroy(
    rac_capability_type_t capability,
    void* service
);
```

### Implementation

```cpp
// src/registry/service_registry.cpp

#include "rac_core.h"
#include <mutex>
#include <vector>
#include <algorithm>
#include <unordered_map>
#include <cstring>

namespace runanywhere {
namespace commons {

class ServiceRegistry {
public:
    static ServiceRegistry& instance() {
        static ServiceRegistry registry;
        return registry;
    }

    rac_result_t register_provider(const rac_capability_provider_t* provider) {
        if (!provider || !provider->provider_name) {
            return RAC_ERROR_NULL_POINTER;
        }

        std::lock_guard<std::mutex> lock(mutex_);

        ProviderEntry entry;
        entry.provider = *provider;
        entry.provider.provider_name = strdup(provider->provider_name);

        providers_[provider->capability_type].push_back(std::move(entry));

        // Sort by priority (higher first)
        std::sort(
            providers_[provider->capability_type].begin(),
            providers_[provider->capability_type].end(),
            [](const ProviderEntry& a, const ProviderEntry& b) {
                return a.provider.priority > b.provider.priority;
            }
        );

        return RAC_SUCCESS;
    }

    rac_result_t create_service(
        rac_capability_type_t capability,
        const char* model_id,
        void* config,
        void** out_service
    ) {
        if (!out_service) {
            return RAC_ERROR_NULL_POINTER;
        }

        std::lock_guard<std::mutex> lock(mutex_);

        auto it = providers_.find(capability);
        if (it == providers_.end() || it->second.empty()) {
            return RAC_ERROR_BACKEND_NOT_FOUND;
        }

        // Find first provider that can handle this model
        for (size_t i = 0; i < it->second.size(); ++i) {
            const auto& entry = it->second[i];
            if (entry.provider.can_handle(model_id, entry.provider.context)) {
                rac_result_t result = entry.provider.create(
                    model_id,
                    config,
                    out_service,
                    entry.provider.context
                );

                if (result == RAC_SUCCESS && *out_service) {
                    // Track which provider created this service
                    ServiceInstance instance;
                    instance.capability = capability;
                    instance.provider_index = i;
                    service_instances_[*out_service] = instance;
                }

                return result;
            }
        }

        return RAC_ERROR_BACKEND_NOT_FOUND;
    }

    rac_result_t destroy_service(rac_capability_type_t capability, void* service) {
        if (!service) {
            return RAC_ERROR_NULL_POINTER;
        }

        std::lock_guard<std::mutex> lock(mutex_);

        // Find which provider created this service
        auto instance_it = service_instances_.find(service);
        if (instance_it == service_instances_.end()) {
            return RAC_ERROR_INVALID_HANDLE;
        }

        ServiceInstance& instance = instance_it->second;

        // Verify capability matches
        if (instance.capability != capability) {
            return RAC_ERROR_INVALID_PARAM;
        }

        auto provider_it = providers_.find(capability);
        if (provider_it == providers_.end() ||
            instance.provider_index >= provider_it->second.size()) {
            return RAC_ERROR_BACKEND_NOT_FOUND;
        }

        // Call destroy on the correct provider
        const auto& entry = provider_it->second[instance.provider_index];
        entry.provider.destroy(service, entry.provider.context);

        // Remove from tracking
        service_instances_.erase(instance_it);

        return RAC_SUCCESS;
    }

    void reset() {
        std::lock_guard<std::mutex> lock(mutex_);
        providers_.clear();
        service_instances_.clear();
    }

private:
    struct ProviderEntry {
        rac_capability_provider_t provider;

        ~ProviderEntry() {
            free((void*)provider.provider_name);
        }
    };

    struct ServiceInstance {
        rac_capability_type_t capability;
        size_t provider_index;
    };

    ServiceRegistry() = default;
    std::mutex mutex_;
    std::unordered_map<rac_capability_type_t, std::vector<ProviderEntry>> providers_;
    std::unordered_map<void*, ServiceInstance> service_instances_;
};

} // namespace commons
} // namespace runanywhere

// C API
extern "C" {

rac_result_t rac_service_register_provider(const rac_capability_provider_t* provider) {
    return runanywhere::commons::ServiceRegistry::instance().register_provider(provider);
}

rac_result_t rac_service_create(
    rac_capability_type_t capability,
    const char* model_id,
    void* config,
    void** out_service
) {
    return runanywhere::commons::ServiceRegistry::instance().create_service(
        capability, model_id, config, out_service
    );
}

rac_result_t rac_service_destroy(rac_capability_type_t capability, void* service) {
    return runanywhere::commons::ServiceRegistry::instance().destroy_service(capability, service);
}

} // extern "C"
```

---

## Task 1.3: Event Publisher

### Header (rac_events.h)

```c
// include/rac_events.h
#ifndef RAC_EVENTS_H
#define RAC_EVENTS_H

#include "rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// EVENT CATEGORIES
// =============================================================================

typedef enum {
    RAC_EVENT_INITIALIZATION = 1,
    RAC_EVENT_MODEL = 2,
    RAC_EVENT_GENERATION = 3,
    RAC_EVENT_TRANSCRIPTION = 4,
    RAC_EVENT_SYNTHESIS = 5,
    RAC_EVENT_VAD = 6,
    RAC_EVENT_MEMORY = 7,
    RAC_EVENT_NETWORK = 8,
    RAC_EVENT_ERROR = 9
} rac_event_category_t;

// =============================================================================
// EVENT DESTINATION
// =============================================================================

typedef enum {
    RAC_EVENT_DEST_PUBLIC = 1,      // Visible to SDK consumers
    RAC_EVENT_DEST_ANALYTICS = 2,   // Sent to telemetry
    RAC_EVENT_DEST_BOTH = 3
} rac_event_destination_t;

// =============================================================================
// EVENT STRUCTURE
// =============================================================================

typedef struct {
    rac_event_category_t category;
    const char* type;              // e.g., "model.loaded", "generation.started"
    const char* payload_json;      // JSON payload
    rac_event_destination_t destination;
    uint64_t timestamp_ms;         // 0 = auto-populate with current time
    const char* session_id;        // Optional correlation ID
} rac_event_t;

// =============================================================================
// EVENT CALLBACK
// =============================================================================

typedef void (*rac_event_callback_t)(const rac_event_t* event, void* context);

// =============================================================================
// EVENT API
// =============================================================================

/**
 * Subscribe to events of a specific category.
 *
 * @param category Event category to subscribe to
 * @param callback Function called when event is published
 * @param context User data passed to callback
 * @param out_subscription_id Output: subscription ID for unsubscribe
 * @return RAC_SUCCESS on success
 */
RAC_API rac_result_t rac_event_subscribe(
    rac_event_category_t category,
    rac_event_callback_t callback,
    void* context,
    uint32_t* out_subscription_id
);

/**
 * Subscribe to all events.
 */
RAC_API rac_result_t rac_event_subscribe_all(
    rac_event_callback_t callback,
    void* context,
    uint32_t* out_subscription_id
);

/**
 * Unsubscribe from events.
 *
 * @param subscription_id ID returned from subscribe
 * @return RAC_SUCCESS on success
 */
RAC_API rac_result_t rac_event_unsubscribe(uint32_t subscription_id);

/**
 * Publish an event.
 * If timestamp_ms is 0, it will be auto-populated with the current time.
 *
 * @param event Event to publish
 * @return RAC_SUCCESS on success
 */
RAC_API rac_result_t rac_event_publish(const rac_event_t* event);

#ifdef __cplusplus
}
#endif

#endif // RAC_EVENTS_H
```

### Implementation

```cpp
// src/events/event_publisher.cpp

#include "rac_events.h"
#include "rac_types.h"
#include <mutex>
#include <vector>
#include <atomic>
#include <algorithm>

namespace runanywhere {
namespace commons {

class EventPublisher {
public:
    static EventPublisher& instance() {
        static EventPublisher publisher;
        return publisher;
    }

    rac_result_t subscribe(
        rac_event_category_t category,
        rac_event_callback_t callback,
        void* context,
        uint32_t* out_id
    ) {
        if (!callback || !out_id) {
            return RAC_ERROR_NULL_POINTER;
        }

        std::lock_guard<std::mutex> lock(mutex_);

        Subscription sub;
        sub.id = next_id_++;
        sub.category = category;
        sub.callback = callback;
        sub.context = context;
        sub.all_categories = false;

        subscriptions_.push_back(sub);
        *out_id = sub.id;

        return RAC_SUCCESS;
    }

    rac_result_t subscribe_all(
        rac_event_callback_t callback,
        void* context,
        uint32_t* out_id
    ) {
        if (!callback || !out_id) {
            return RAC_ERROR_NULL_POINTER;
        }

        std::lock_guard<std::mutex> lock(mutex_);

        Subscription sub;
        sub.id = next_id_++;
        sub.category = (rac_event_category_t)0;
        sub.callback = callback;
        sub.context = context;
        sub.all_categories = true;

        subscriptions_.push_back(sub);
        *out_id = sub.id;

        return RAC_SUCCESS;
    }

    rac_result_t unsubscribe(uint32_t id) {
        std::lock_guard<std::mutex> lock(mutex_);

        auto it = std::find_if(
            subscriptions_.begin(),
            subscriptions_.end(),
            [id](const Subscription& s) { return s.id == id; }
        );

        if (it == subscriptions_.end()) {
            return RAC_ERROR_INVALID_PARAM;
        }

        subscriptions_.erase(it);
        return RAC_SUCCESS;
    }

    rac_result_t publish(const rac_event_t* event) {
        if (!event) {
            return RAC_ERROR_NULL_POINTER;
        }

        // Copy event and auto-populate timestamp if needed
        rac_event_t published_event = *event;
        if (published_event.timestamp_ms == 0) {
            published_event.timestamp_ms = rac_get_current_time_ms();
        }

        // Take snapshot of subscriptions to avoid holding lock during callbacks
        std::vector<Subscription> subs_copy;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            subs_copy = subscriptions_;
        }

        // Notify subscribers
        for (const auto& sub : subs_copy) {
            if (sub.all_categories || sub.category == event->category) {
                // Only send to public subscribers if destination includes public
                if (event->destination & RAC_EVENT_DEST_PUBLIC) {
                    sub.callback(&published_event, sub.context);
                }
            }
        }

        return RAC_SUCCESS;
    }

    void reset() {
        std::lock_guard<std::mutex> lock(mutex_);
        subscriptions_.clear();
    }

private:
    struct Subscription {
        uint32_t id;
        rac_event_category_t category;
        rac_event_callback_t callback;
        void* context;
        bool all_categories;
    };

    EventPublisher() : next_id_(1) {}
    std::mutex mutex_;
    std::vector<Subscription> subscriptions_;
    std::atomic<uint32_t> next_id_;
};

} // namespace commons
} // namespace runanywhere

// C API
extern "C" {

rac_result_t rac_event_subscribe(
    rac_event_category_t category,
    rac_event_callback_t callback,
    void* context,
    uint32_t* out_subscription_id
) {
    return runanywhere::commons::EventPublisher::instance().subscribe(
        category, callback, context, out_subscription_id
    );
}

rac_result_t rac_event_subscribe_all(
    rac_event_callback_t callback,
    void* context,
    uint32_t* out_subscription_id
) {
    return runanywhere::commons::EventPublisher::instance().subscribe_all(
        callback, context, out_subscription_id
    );
}

rac_result_t rac_event_unsubscribe(uint32_t subscription_id) {
    return runanywhere::commons::EventPublisher::instance().unsubscribe(subscription_id);
}

rac_result_t rac_event_publish(const rac_event_t* event) {
    return runanywhere::commons::EventPublisher::instance().publish(event);
}

} // extern "C"
```

---

## Task 1.4: Time Utilities

### Implementation (rac_get_current_time_ms)

```cpp
// src/core/rac_time.cpp

#include "rac_types.h"
#include <chrono>

extern "C" {

uint64_t rac_get_current_time_ms(void) {
    auto now = std::chrono::system_clock::now();
    auto duration = now.time_since_epoch();
    return std::chrono::duration_cast<std::chrono::milliseconds>(duration).count();
}

} // extern "C"
```

---

## Task 1.5: Platform Adapter

### Implementation

```cpp
// src/core/rac_core.cpp

#include "rac_core.h"
#include "rac_platform_adapter.h"
#include <mutex>
#include <cstring>

namespace runanywhere {
namespace commons {

// Global state
static std::mutex g_init_mutex;
static bool g_initialized = false;
static rac_config_t g_config;
static rac_platform_adapter_t g_platform_adapter;
static bool g_platform_adapter_set = false;

// Version string
static const char* VERSION_STRING = "1.0.0";

} // namespace commons
} // namespace runanywhere

extern "C" {

// =============================================================================
// VERSION
// =============================================================================

const char* rac_get_version(void) {
    return runanywhere::commons::VERSION_STRING;
}

uint32_t rac_get_api_version(void) {
    return (RAC_API_VERSION_MAJOR << 16) |
           (RAC_API_VERSION_MINOR << 8) |
           RAC_API_VERSION_PATCH;
}

// =============================================================================
// CONFIGURATION
// =============================================================================

void rac_config_init(rac_config_t* config) {
    if (!config) return;

    memset(config, 0, sizeof(rac_config_t));
    config->struct_size = sizeof(rac_config_t);
    config->environment = RAC_ENV_DEVELOPMENT;
    config->enable_telemetry = false;
}

// =============================================================================
// INITIALIZATION
// =============================================================================

rac_result_t rac_init(const rac_config_t* config) {
    std::lock_guard<std::mutex> lock(runanywhere::commons::g_init_mutex);

    if (runanywhere::commons::g_initialized) {
        return RAC_ERROR_ALREADY_INITIALIZED;
    }

    // Copy configuration
    if (config) {
        runanywhere::commons::g_config = *config;
    } else {
        rac_config_init(&runanywhere::commons::g_config);
    }

    runanywhere::commons::g_initialized = true;
    return RAC_SUCCESS;
}

rac_result_t rac_shutdown(void) {
    std::lock_guard<std::mutex> lock(runanywhere::commons::g_init_mutex);

    if (!runanywhere::commons::g_initialized) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    // Reset registries
    // Note: In actual implementation, call reset() on registries

    runanywhere::commons::g_initialized = false;
    runanywhere::commons::g_platform_adapter_set = false;

    return RAC_SUCCESS;
}

bool rac_is_initialized(void) {
    std::lock_guard<std::mutex> lock(runanywhere::commons::g_init_mutex);
    return runanywhere::commons::g_initialized;
}

// =============================================================================
// PLATFORM ADAPTER
// =============================================================================

rac_result_t rac_set_platform_adapter(const rac_platform_adapter_t* adapter) {
    if (!adapter) {
        return RAC_ERROR_NULL_POINTER;
    }

    std::lock_guard<std::mutex> lock(runanywhere::commons::g_init_mutex);

    runanywhere::commons::g_platform_adapter = *adapter;
    runanywhere::commons::g_platform_adapter_set = true;

    return RAC_SUCCESS;
}

const rac_platform_adapter_t* rac_get_platform_adapter(void) {
    std::lock_guard<std::mutex> lock(runanywhere::commons::g_init_mutex);

    if (!runanywhere::commons::g_platform_adapter_set) {
        return nullptr;
    }

    return &runanywhere::commons::g_platform_adapter;
}

} // extern "C"
```

---

## Task 1.6: Error Handling

### Implementation

```cpp
// src/core/rac_error.cpp

#include "rac_error.h"
#include <cstring>
#include <thread>
#include <unordered_map>
#include <mutex>

namespace runanywhere {
namespace commons {

// Thread-local error details
thread_local char g_error_details[1024] = {0};

// Error messages
static const char* get_error_message(rac_result_t code) {
    switch (code) {
        case RAC_SUCCESS: return "Success";

        // Initialization errors
        case RAC_ERROR_NOT_INITIALIZED: return "Commons not initialized";
        case RAC_ERROR_ALREADY_INITIALIZED: return "Already initialized";
        case RAC_ERROR_INVALID_CONFIG: return "Invalid configuration";
        case RAC_ERROR_PLATFORM_ADAPTER: return "Platform adapter error";

        // Parameter errors
        case RAC_ERROR_INVALID_PARAM: return "Invalid parameter";
        case RAC_ERROR_NULL_POINTER: return "Null pointer";
        case RAC_ERROR_INVALID_HANDLE: return "Invalid handle";
        case RAC_ERROR_BUFFER_TOO_SMALL: return "Buffer too small";

        // Model errors
        case RAC_ERROR_MODEL_NOT_FOUND: return "Model not found";
        case RAC_ERROR_MODEL_NOT_LOADED: return "Model not loaded";
        case RAC_ERROR_MODEL_LOAD_FAILED: return "Model load failed";
        case RAC_ERROR_MODEL_ALREADY_LOADED: return "Model already loaded";
        case RAC_ERROR_MODEL_INCOMPATIBLE: return "Model incompatible";

        // Component errors
        case RAC_ERROR_COMPONENT_NOT_READY: return "Component not ready";
        case RAC_ERROR_COMPONENT_BUSY: return "Component busy";
        case RAC_ERROR_COMPONENT_FAILED: return "Component failed";
        case RAC_ERROR_NOT_SUPPORTED: return "Operation not supported";

        // Network errors
        case RAC_ERROR_NETWORK_UNAVAILABLE: return "Network unavailable";
        case RAC_ERROR_NETWORK_TIMEOUT: return "Network timeout";
        case RAC_ERROR_NETWORK_FAILED: return "Network failed";

        // Memory errors
        case RAC_ERROR_OUT_OF_MEMORY: return "Out of memory";
        case RAC_ERROR_MEMORY_PRESSURE: return "Memory pressure";

        // File errors
        case RAC_ERROR_FILE_NOT_FOUND: return "File not found";
        case RAC_ERROR_FILE_READ_FAILED: return "File read failed";
        case RAC_ERROR_FILE_WRITE_FAILED: return "File write failed";
        case RAC_ERROR_CHECKSUM_MISMATCH: return "Checksum mismatch";

        // Backend errors
        case RAC_ERROR_BACKEND_NOT_FOUND: return "Backend not found";
        case RAC_ERROR_BACKEND_LOAD_FAILED: return "Backend load failed";
        case RAC_ERROR_BACKEND_NOT_REGISTERED: return "Backend not registered";

        // Cancellation
        case RAC_ERROR_CANCELLED: return "Operation cancelled";

        default: return "Unknown error";
    }
}

} // namespace commons
} // namespace runanywhere

extern "C" {

const char* rac_error_message(rac_result_t code) {
    return runanywhere::commons::get_error_message(code);
}

const char* rac_get_last_error_details(void) {
    if (runanywhere::commons::g_error_details[0] == '\0') {
        return nullptr;
    }
    return runanywhere::commons::g_error_details;
}

void rac_set_last_error_details(const char* details) {
    if (details) {
        strncpy(runanywhere::commons::g_error_details, details,
                sizeof(runanywhere::commons::g_error_details) - 1);
        runanywhere::commons::g_error_details[sizeof(runanywhere::commons::g_error_details) - 1] = '\0';
    } else {
        runanywhere::commons::g_error_details[0] = '\0';
    }
}

// =============================================================================
// MEMORY MANAGEMENT
// =============================================================================

void rac_free(void* ptr) {
    free(ptr);
}

char* rac_strdup(const char* str) {
    if (!str) return nullptr;
    return strdup(str);
}

} // extern "C"
```

---

## Task 1.7: Unit Tests

### Test Cases

```cpp
// tests/test_module_registry.cpp

#include <gtest/gtest.h>
#include "rac_core.h"

class ModuleRegistryTest : public ::testing::Test {
protected:
    void SetUp() override {
        rac_init(nullptr);
    }

    void TearDown() override {
        rac_shutdown();
    }
};

TEST_F(ModuleRegistryTest, RegisterModule) {
    rac_module_info_t module = {
        .module_id = "test",
        .module_name = "Test Module",
        .version = "1.0.0",
        .capabilities = (1 << RAC_CAPABILITY_TEXT_GENERATION),
        .priority = 100
    };

    EXPECT_EQ(RAC_SUCCESS, rac_module_register(&module));

    // Verify it's registered
    rac_module_info_t* modules;
    size_t count;
    EXPECT_EQ(RAC_SUCCESS, rac_module_list(&modules, &count));
    EXPECT_EQ(1, count);
    EXPECT_STREQ("test", modules[0].module_id);

    rac_module_list_free(modules, count);

    // Cleanup
    EXPECT_EQ(RAC_SUCCESS, rac_module_unregister("test"));
}

TEST_F(ModuleRegistryTest, DuplicateRegistrationFails) {
    rac_module_info_t module = {
        .module_id = "test",
        .module_name = "Test Module"
    };

    EXPECT_EQ(RAC_SUCCESS, rac_module_register(&module));
    EXPECT_EQ(RAC_ERROR_ALREADY_INITIALIZED, rac_module_register(&module));

    rac_module_unregister("test");
}

TEST_F(ModuleRegistryTest, ModulesForCapability) {
    rac_module_info_t llm_module = {
        .module_id = "llamacpp",
        .module_name = "LlamaCPP",
        .capabilities = (1 << RAC_CAPABILITY_TEXT_GENERATION),
        .priority = 100
    };

    rac_module_info_t stt_module = {
        .module_id = "onnx",
        .module_name = "ONNX",
        .capabilities = (1 << RAC_CAPABILITY_STT) | (1 << RAC_CAPABILITY_TTS),
        .priority = 100
    };

    EXPECT_EQ(RAC_SUCCESS, rac_module_register(&llm_module));
    EXPECT_EQ(RAC_SUCCESS, rac_module_register(&stt_module));

    char** module_ids;
    size_t count;

    // Query TEXT_GENERATION
    EXPECT_EQ(RAC_SUCCESS, rac_modules_for_capability(RAC_CAPABILITY_TEXT_GENERATION, &module_ids, &count));
    EXPECT_EQ(1, count);
    EXPECT_STREQ("llamacpp", module_ids[0]);
    rac_free(module_ids[0]);
    rac_free(module_ids);

    // Query STT
    EXPECT_EQ(RAC_SUCCESS, rac_modules_for_capability(RAC_CAPABILITY_STT, &module_ids, &count));
    EXPECT_EQ(1, count);
    EXPECT_STREQ("onnx", module_ids[0]);
    rac_free(module_ids[0]);
    rac_free(module_ids);

    rac_module_unregister("llamacpp");
    rac_module_unregister("onnx");
}
```

---

## Definition of Done

- [ ] Module Registry: registration, unregistration, listing works with `rac_` prefix
- [ ] Service Registry: provider registration, service creation with correct provider tracking
- [ ] Event Publisher: subscription, unsubscription, publishing with auto-timestamp
- [ ] Time Utilities: `rac_get_current_time_ms()` implemented
- [ ] Platform Adapter: interface defined, HTTP returns `RAC_ERROR_NOT_SUPPORTED`
- [ ] Error Handling: all error codes in `-100` to `-999` range
- [ ] Unit tests pass with >80% coverage
- [ ] All symbols use `rac_` prefix (no `ra_` collisions)

---

*Phase 1 Duration: 3 weeks*
