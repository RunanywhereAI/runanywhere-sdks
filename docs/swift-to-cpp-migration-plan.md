# RunAnywhere SDK: Swift to C++ Migration

## Current Status: Phase 1-2 Complete, Phase 3 In Progress

### Phase 1: Features Layer Migration ✅ COMPLETE (December 2024)

Migrated all capability business logic (LLM, STT, TTS, VAD, VoiceAgent) to C++.

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| **Swift Files** | 149 | 139 | -10 files |
| **Swift Lines** | 23,503 | 20,756 | **-2,747 lines (-12%)** |
| **Capabilities Layer** | 1,963 lines | 0 | **DELETED** |

---

### Phase 2a: Telemetry Layer Migration ✅ COMPLETE (December 2024)

Migrated telemetry event building, JSON serialization, and batching to C++.

#### New C++ Files Created

| File | Location | Description |
|------|----------|-------------|
| `rac_telemetry_types.h` | `include/rac/infrastructure/telemetry/` | Telemetry payload struct (50+ fields) |
| `rac_telemetry_manager.h` | `include/rac/infrastructure/telemetry/` | Telemetry manager API |
| `telemetry_types.cpp` | `src/infrastructure/telemetry/` | Type utilities |
| `telemetry_json.cpp` | `src/infrastructure/telemetry/` | JSON serialization (env-aware) |
| `telemetry_manager.cpp` | `src/infrastructure/telemetry/` | Event queuing, batching, HTTP callback |

#### Swift Bridge Architecture (Unified)

All C++ bridges are now unified into a single `CppBridge.swift` module:

| Bridge | Namespace | Description |
|--------|-----------|-------------|
| Environment | `CppBridge.Environment` | C++ ↔ Swift environment conversion, validation |
| Endpoints | `CppBridge.Endpoints` | All API endpoint paths |
| Events | `CppBridge.Events` | Analytics event callback registration |
| Telemetry | `CppBridge.Telemetry` | Event queuing, HTTP callback |
| Device | `CppBridge.Device` | Device registration JSON building |
| **State** | `CppBridge.State` | **Centralized SDK state management** |
| **DevConfig** | `CppBridge.DevConfig` | **Development config (Supabase, build token)** |
| **Auth** | `CppBridge.Auth` | **Auth request JSON building, error parsing** |

**Usage:**
```swift
// Initialize all bridges at once
CppBridge.initialize(environment: .production, apiClient: client)

// Access specific functionality
CppBridge.Environment.requiresAuth(.production)
CppBridge.Endpoints.telemetry(for: .production)
CppBridge.Telemetry.flush()
try await CppBridge.Device.register()
```

#### Integration Points

1. **CppEventBridge** now forwards analytics events to **CppTelemetryBridge**
2. **CppTelemetryBridge** calls C++ `rac_telemetry_manager_track_analytics()`
3. C++ builds JSON and groups by modality (llm/stt/tts/model/system)
4. C++ calls back to Swift with JSON + endpoint for HTTP POST
5. Swift makes URLSession HTTP call

#### Architecture

```
C++ Analytics Event                           Swift HTTP Layer
────────────────────                          ─────────────────
rac_analytics_event_emit()                    CppTelemetryBridge
        │                                              │
        ▼                                              │
CppEventBridge (Swift callback)                        │
        │                                              │
        ├─────────────────────────────────────────────►│
        │  trackAnalyticsEvent(type, data)             │
        ▼                                              │
rac_telemetry_manager_track_analytics()                │
        │                                              │
        ▼                                              │
Queue events, build JSON, group by modality            │
        │                                              │
        ▼                                              │
HTTP callback to Swift ───────────────────────────────►│
        (json, endpoint, requiresAuth)                 │
                                                       ▼
                                              apiClient.postRaw()
```

---

### Phase 2c: Centralized State Management ✅ COMPLETE (December 2024)

Implemented centralized SDK state management in C++ with `CppBridge.State`.

#### New C++ Files Created

| File | Location | Description |
|------|----------|-------------|
| `rac_sdk_state.h` | `include/rac/core/` | State manager API (auth, device, env) |
| `sdk_state.cpp` | `src/core/` | C++ singleton implementation |

#### State Architecture

C++ now owns all runtime state. Swift handles:
- **Persistence**: Keychain storage via callbacks
- **HTTP Transport**: URLSession for API calls
- **Platform Data**: DeviceInfo, DeviceIdentity

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    C++ STATE MANAGER (Single Source of Truth)                │
│                                                                              │
│  SDKState (Meyer's Singleton)                                               │
│  ├── auth: { access_token, refresh_token, expires_at, user_id, org_id }    │
│  ├── device: { device_id, is_registered }                                   │
│  ├── environment: { env, api_key, base_url }                               │
│  └── callbacks: { persist_callback, load_callback, auth_changed_callback }  │
│                                                                              │
│  Thread-safe: std::mutex + lock_guard                                       │
└───────────────────────────────┬─────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Swift Adapter (CppBridge.State)                      │
│                                                                              │
│  - initialize(env, apiKey, baseURL, deviceId)                               │
│  - setAuth(accessToken, refreshToken, expiresAt, userId, orgId, deviceId)   │
│  - isAuthenticated, accessToken, userId, organizationId                     │
│  - setDeviceRegistered(bool), isDeviceRegistered                            │
│  - Keychain persistence callbacks                                            │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Integration Points

1. **RunAnywhere.swift**: Calls `CppBridge.State.initialize()` during SDK init
2. **AuthenticationService.swift**: Calls `CppBridge.State.setAuth()` after HTTP auth
3. **DeviceRegistrationService.swift**: Queries `CppBridge.State.isDeviceRegistered`
4. **Public API**: `RunAnywhere.isAuthenticated` queries C++ state

#### C++ API

```c
// Initialization
rac_result_t rac_state_initialize(env, api_key, base_url, device_id);
void rac_state_shutdown(void);
void rac_state_reset(void);

// Auth state
rac_result_t rac_state_set_auth(const rac_auth_data_t* auth);
const char* rac_state_get_access_token(void);
bool rac_state_is_authenticated(void);
bool rac_state_token_needs_refresh(void);
void rac_state_clear_auth(void);

// Device state
void rac_state_set_device_registered(bool);
bool rac_state_is_device_registered(void);

// Persistence callbacks
void rac_state_set_persistence_callbacks(persist, load, user_data);
void rac_state_on_auth_changed(callback, user_data);
```

---

## Phase 2b: Data Layer Migration ✅ COMPLETE (December 2024)

### Goal
Move all network/API business logic to C++, making Swift a thin HTTP transport bridge.

### Current Data Layer (Swift)

**After Cleanup: 5 files, ~470 lines in `Data/Network/`**

| File | Lines | Description | Status |
|------|-------|-------------|--------|
| `AuthenticationService.swift` | 231 | HTTP + Keychain (uses `CppBridge.State`) | ✅ Simplified |
| `APIClient.swift` | 135 | HTTP execution via URLSession | 📌 Keep (platform API) |
| `NetworkService.swift` | 61 | Protocol for DI | 📌 Keep (Swift protocol) |
| `AuthenticationResponse.swift` | 44 | Codable response model | 📌 Keep (JSON decode) |
| `HealthCheckResponse.swift` | 21 | Codable response model | 📌 Keep (JSON decode) |
| `HealthStatus.swift` | 9 | Health enum | 📌 Keep (used by response) |

### Files Deleted

| File | Lines | Reason |
|------|-------|--------|
| ~~`APIResponse.swift`~~ | 186 | Error parsing via `CppBridge.Auth.parseAPIError()` |
| ~~`DevelopmentNetworkConfig.swift`~~ | 82 | Config via `CppBridge.DevConfig` |
| ~~`AuthenticationRequest.swift`~~ | 23 | JSON via `CppBridge.Auth.buildAuthenticateRequestJSON()` |
| ~~`RefreshTokenRequest.swift`~~ | 17 | JSON via `CppBridge.Auth.buildRefreshRequestJSON()` |
| ~~`DevelopmentConfig.swift`~~ | 45 | Secrets in C++ `rac_dev_config.h` |
| ~~`APIEndpoint.swift`~~ | 84 | Endpoints in C++ (Phase 2a) |

**Total Deleted: 437 lines (-48%)**

**Related Infrastructure Files:**

| File | Lines | Description | Migration Status |
|------|-------|-------------|------------------|
| `TelemetryEventPayload.swift` | 637 | Telemetry payload (all fields) | ⚠️ **DEPRECATED** (C++ now builds JSON) |
| `DeviceRegistrationRequest.swift` | 131 | Device reg request | ✅ **C++ can build JSON** via `CppDeviceBridge` |
| `DeviceRegistrationResponse.swift` | 39 | Device reg response | **MOVE** → C++ |
| `RemoteTelemetryDataSource.swift` | 93 | Telemetry HTTP sending | ✅ **DEPRECATED** (C++ via callback) |
| `SDKEnvironment.swift` | 97 | Environment enum + validation | ✅ **Uses C++** validation |
| `SDKInitParams` | ~160 | Init params + validation | ✅ **Uses C++** validation |

### C++ Components Created (Phase 2a + 2b + 2c)

| C++ Component | Description |
|---------------|-------------|
| `rac_environment.h` | Environment enum, validation functions |
| `rac_endpoints.h` | All endpoint paths, environment-based selection |
| `rac_telemetry_types.h` | Full telemetry payload struct (50+ fields) |
| `rac_telemetry_manager.h` | Event queuing, batching, JSON building, HTTP callback |
| `rac_sdk_state.h` | Centralized SDK state (auth, device, env) |
| `rac_api_types.h` | Auth request/response types, JSON serialization |
| `rac_auth_manager.h` | Auth state management, token refresh logic |
| **`rac_dev_config.h`** | **Development config (Supabase URL, key, build token)** |

### Swift Bridge Components (Unified in `CppBridge.swift`)

| Bridge | Purpose |
|--------|---------|
| `CppBridge.Environment` | Swift ↔ C++ environment conversion |
| `CppBridge.Telemetry` | HTTP callback implementation |
| `CppBridge.Device` | Device registration JSON building |
| `CppBridge.State` | Centralized state queries/mutations |
| **`CppBridge.DevConfig`** | **Dev config from C++ (cross-platform)** |
| **`CppBridge.Auth`** | **Auth JSON building, error parsing** |

---

### What CAN Be Moved to C++

#### 1. Environment Configuration
- `SDKEnvironment` enum (development, staging, production)
- Environment-specific settings (requiresAuth, logLevel, etc.)
- URL/API key validation logic

#### 2. Data Models (Requests/Responses)
- All request structs (AuthenticationRequest, RefreshTokenRequest, DeviceRegistrationRequest)
- All response structs (AuthenticationResponse, HealthCheckResponse, etc.)
- TelemetryEventPayload fields (not Swift Codable logic)
- APIErrorInfo parsing logic

#### 3. Endpoint Definitions
- All endpoint paths as string constants
- Environment-based endpoint selection logic

#### 4. Business Logic
- Token expiry checking
- Token refresh decision logic
- Request body JSON building
- Response JSON parsing
- Error extraction and categorization

#### 5. State Management
- Current access token
- Refresh token
- Token expiry timestamp
- Authentication state (isAuthenticated)

---

### What MUST Stay in Swift

#### 1. Platform HTTP Client
- `URLSession` - Apple's networking API
- `URLRequest` construction
- HTTP response handling

#### 2. Secure Storage
- `KeychainManager` - Apple Security framework
- Token persistence
- SDK params persistence

#### 3. Platform-Specific Data
- `DeviceInfo.current` - UIDevice, ProcessInfo
- `DeviceIdentity.persistentUUID` - Keychain UUID

#### 4. Date Handling
- `ISO8601DateFormatter` for API dates
- `Date()` for timestamps

---

### Target Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         SWIFT LAYER (Thin Bridge)                           │
│                                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────────┐ │
│  │  APIClient.swift │  │ KeychainManager │  │ DeviceInfo/DeviceIdentity  │ │
│  │  (URLSession)    │  │ (Security.fw)   │  │ (UIDevice, ProcessInfo)    │ │
│  └────────┬────────┘  └────────┬────────┘  └──────────────┬──────────────┘ │
│           │                    │                          │                 │
└───────────┼────────────────────┼──────────────────────────┼─────────────────┘
            │                    │                          │
            ▼                    ▼                          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         C++ LAYER (Business Logic)                          │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  rac_http_client.h  (HTTP abstraction with callbacks)               │   │
│  │  - rac_http_request_t (method, url, headers, body)                  │   │
│  │  - rac_http_response_t (status, headers, body)                      │   │
│  │  - rac_http_execute_callback (platform implements)                  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  rac_environment.h  (Environment configuration)                     │   │
│  │  - RAC_ENV_DEVELOPMENT, RAC_ENV_STAGING, RAC_ENV_PRODUCTION         │   │
│  │  - rac_env_requires_auth(), rac_env_log_level()                     │   │
│  │  - rac_env_validate_url(), rac_env_validate_api_key()               │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  rac_auth_manager.h  (Authentication state machine)                 │   │
│  │  - rac_auth_state_t (tokens, expiry, device_id)                     │   │
│  │  - rac_auth_authenticate() → builds request, parses response        │   │
│  │  - rac_auth_refresh_token() → builds request, parses response       │   │
│  │  - rac_auth_get_token() → returns token or triggers refresh         │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  rac_api_types.h  (Request/Response models)                         │   │
│  │  - rac_auth_request_t, rac_auth_response_t                          │   │
│  │  - rac_device_reg_request_t, rac_device_reg_response_t              │   │
│  │  - rac_telemetry_event_t, rac_telemetry_batch_t                     │   │
│  │  - rac_health_response_t                                            │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  rac_endpoints.h  (API endpoint paths)                              │   │
│  │  - RAC_ENDPOINT_AUTHENTICATE, RAC_ENDPOINT_REFRESH                  │   │
│  │  - RAC_ENDPOINT_HEALTH, RAC_ENDPOINT_TELEMETRY                      │   │
│  │  - rac_endpoint_for_env() → selects dev/prod endpoint               │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

### Implementation Plan

#### Step 1: Create C++ Environment Configuration
**New files in `runanywhere-commons/include/rac/infrastructure/network/`:**

```c
// rac_environment.h
typedef enum {
    RAC_ENV_DEVELOPMENT = 0,
    RAC_ENV_STAGING = 1,
    RAC_ENV_PRODUCTION = 2
} rac_environment_t;

typedef struct {
    rac_environment_t environment;
    const char* api_key;
    const char* base_url;
    const char* device_id;  // Set by platform
} rac_sdk_config_t;

// Environment queries
bool rac_env_requires_auth(rac_environment_t env);
bool rac_env_requires_backend_url(rac_environment_t env);
rac_log_level_t rac_env_default_log_level(rac_environment_t env);

// Validation
rac_error_t rac_validate_api_key(const char* api_key, rac_environment_t env);
rac_error_t rac_validate_base_url(const char* url, rac_environment_t env);
```

#### Step 2: Create C++ API Types
```c
// rac_api_types.h
typedef struct {
    const char* api_key;
    const char* device_id;
    const char* platform;
    const char* sdk_version;
} rac_auth_request_t;

typedef struct {
    const char* access_token;
    const char* refresh_token;
    const char* device_id;
    const char* user_id;        // nullable
    const char* organization_id;
    int32_t expires_in;
} rac_auth_response_t;

typedef struct {
    const char* device_id;
    const char* refresh_token;
} rac_refresh_token_request_t;

// JSON serialization
char* rac_auth_request_to_json(const rac_auth_request_t* request);
rac_error_t rac_auth_response_from_json(const char* json, rac_auth_response_t* out);
```

#### Step 3: Create C++ HTTP Abstraction
```c
// rac_http_client.h
typedef enum {
    RAC_HTTP_GET,
    RAC_HTTP_POST,
    RAC_HTTP_PUT,
    RAC_HTTP_DELETE
} rac_http_method_t;

typedef struct {
    rac_http_method_t method;
    const char* url;
    const char* body;           // JSON string
    const char** header_keys;   // NULL-terminated
    const char** header_values; // NULL-terminated
} rac_http_request_t;

typedef struct {
    int32_t status_code;
    const char* body;           // JSON string
    const char* error_message;  // If failed
} rac_http_response_t;

// Callback type for platform to implement
typedef void (*rac_http_callback_t)(
    const rac_http_response_t* response,
    void* user_data
);

// Platform registers its HTTP executor
typedef void (*rac_http_executor_t)(
    const rac_http_request_t* request,
    rac_http_callback_t callback,
    void* user_data
);

void rac_http_set_executor(rac_http_executor_t executor);
```

#### Step 4: Create C++ Auth Manager
```c
// rac_auth_manager.h
typedef struct {
    char* access_token;
    char* refresh_token;
    char* device_id;
    char* user_id;
    char* organization_id;
    int64_t token_expires_at;  // Unix timestamp
    bool is_authenticated;
} rac_auth_state_t;

// Initialize auth manager
rac_error_t rac_auth_init(const rac_sdk_config_t* config);

// Build auth request (returns JSON, platform sends HTTP)
char* rac_auth_build_authenticate_request(const rac_sdk_config_t* config);

// Parse auth response (from HTTP body)
rac_error_t rac_auth_parse_authenticate_response(const char* json);

// Token management
const char* rac_auth_get_access_token(void);  // Returns NULL if expired
bool rac_auth_needs_refresh(void);
char* rac_auth_build_refresh_request(void);
rac_error_t rac_auth_parse_refresh_response(const char* json);

// State queries
bool rac_auth_is_authenticated(void);
const char* rac_auth_get_device_id(void);
const char* rac_auth_get_user_id(void);
const char* rac_auth_get_organization_id(void);
```

#### Step 5: Create C++ Endpoints
```c
// rac_endpoints.h
#define RAC_ENDPOINT_AUTHENTICATE     "/api/v1/auth/sdk/authenticate"
#define RAC_ENDPOINT_REFRESH          "/api/v1/auth/sdk/refresh"
#define RAC_ENDPOINT_HEALTH           "/v1/health"
#define RAC_ENDPOINT_DEVICE_REGISTER  "/api/v1/devices/register"
#define RAC_ENDPOINT_TELEMETRY        "/api/v1/sdk/telemetry"

// Development endpoints (Supabase)
#define RAC_ENDPOINT_DEV_DEVICE_REG   "/rest/v1/device_registrations"
#define RAC_ENDPOINT_DEV_TELEMETRY    "/rest/v1/telemetry_events"

// Get endpoint for environment
const char* rac_endpoint_device_registration(rac_environment_t env);
const char* rac_endpoint_telemetry(rac_environment_t env);
```

#### Step 6: Refactor Swift to Thin Bridge

**`APIClient.swift` becomes:**
```swift
public actor APIClient {
    func execute(_ cppRequest: UnsafePointer<rac_http_request_t>) async throws -> Data {
        // Convert C++ request to URLRequest
        let url = URL(string: String(cString: cppRequest.pointee.url))!
        var request = URLRequest(url: url)
        request.httpMethod = cppRequest.pointee.method == RAC_HTTP_POST ? "POST" : "GET"
        if let body = cppRequest.pointee.body {
            request.httpBody = String(cString: body).data(using: .utf8)
        }
        // Add headers...

        let (data, response) = try await URLSession.shared.data(for: request)
        return data
    }
}
```

**`AuthenticationService.swift` becomes:**
```swift
public actor AuthenticationService {
    func authenticate() async throws {
        // 1. C++ builds the request
        let requestJson = String(cString: rac_auth_build_authenticate_request(&config))

        // 2. Swift makes HTTP call
        let responseData = try await apiClient.post(endpoint, requestJson.data(using: .utf8)!)

        // 3. C++ parses the response
        let result = rac_auth_parse_authenticate_response(responseJson)

        // 4. Swift stores tokens in Keychain (platform-specific)
        try KeychainManager.shared.store(rac_auth_get_access_token()!, for: tokenKey)
    }
}
```

---

### Expected Results

| Metric | Current | After Phase 2 | Change |
|--------|---------|---------------|--------|
| Swift Data Layer | ~900 lines | ~300 lines | **-600 lines (-67%)** |
| C++ Business Logic | 0 | ~800 lines | New canonical source |
| Cross-Platform | Swift only | Swift, Kotlin, Flutter | **Shared logic** |

### Files Deleted (Phase 2b)

| File | Lines | Reason | Status |
|------|-------|--------|--------|
| `APIResponse.swift` | 186 | Error parsing via C++ `CppBridge.Auth.parseAPIError()` | ✅ **DELETED** |
| ~~`APIEndpoint.swift`~~ | ~~84~~ | ~~Endpoints in C++~~ | ✅ **DELETED** (Phase 2a) |
| `DevelopmentNetworkConfig.swift` | 82 | Config via `CppBridge.DevConfig` | ✅ **DELETED** |
| `DevelopmentConfig.swift` | 45 | Secrets moved to C++ `rac_dev_config.h` | ✅ **DELETED** |
| `AuthenticationRequest.swift` | 23 | JSON built via `CppBridge.Auth.buildAuthenticateRequestJSON()` | ✅ **DELETED** |
| `RefreshTokenRequest.swift` | 17 | JSON built via `CppBridge.Auth.buildRefreshRequestJSON()` | ✅ **DELETED** |
| `AuthenticationResponse.swift` | 43 | **KEEP** - Codable for JSON decode | 📌 Keep |
| `HealthCheckResponse.swift` | 20 | **KEEP** - Codable for JSON decode | 📌 Keep |
| `HealthStatus.swift` | 8 | **KEEP** - Used by response | 📌 Keep |

---

---

## Phase 3: Unified Service Architecture 🟡 IN PROGRESS (December 2024)

### Vision

**C++ is the single source of truth** for all service interfaces, registration logic, and backend implementations. Platform SDKs (Swift, Kotlin, Flutter) are thin adapters that:
1. Expose C++ services through platform-native APIs
2. Handle platform-specific concerns (async/await, Codable, Keychain)
3. Register modules using a controlled Swift module structure

### Completed

1. ✅ **Deleted `ServiceRegistry.swift`** (280 lines) → C++ handles service registration
2. ✅ **Deleted `ModuleDiscovery.swift`** (108 lines) → Modules auto-register via their `autoRegister` property
3. ✅ **Simplified LlamaCPPRuntime** → Merged `LlamaCPPRuntime.swift` + `LlamaCPPServiceProvider.swift` into `LlamaCPP.swift` (~100 lines)
4. ✅ **Simplified ONNXRuntime** → Merged `ONNXRuntime.swift` + `ONNXServiceProvider.swift` into `ONNX.swift` (~130 lines)
5. ✅ **Updated SystemTTS** → Registers with C++ registry via `CppBridge.Services.registerPlatformService()`
6. ✅ **Updated FoundationModels** → Registers with C++ registry via `CppBridge.Services.registerPlatformService()`
7. ✅ **Added `CppBridge.Services`** → Query registered modules/providers from C++
8. ✅ **Platform Service Registration** → Swift callbacks enable platform-only services (SystemTTS, AppleAI) to register with C++ registry

### Service Discovery Architecture

**All services register with C++**, including platform-only ones via Swift callbacks:

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    C++ SERVICE REGISTRY (Single Source of Truth)                 │
│                                                                                  │
│  Providers (sorted by priority):                                                 │
│  ├── LlamaCPP        (C++ impl) priority=100 → rac_backend_llamacpp_register()  │
│  ├── ONNXSTTService  (C++ impl) priority=100 → rac_backend_onnx_register()      │
│  ├── ONNXTTSService  (C++ impl) priority=100 → rac_backend_onnx_register()      │
│  ├── AppleAI         (Swift callback) priority=50 → Foundation Models           │
│  └── SystemTTS       (Swift callback) priority=10 → AVSpeechSynthesizer         │
│                                                                                  │
│  Query API:                                                                      │
│  - rac_service_list_providers(capability) → Names of providers                  │
│  - rac_module_list() → All registered modules                                   │
└─────────────────────────────────────────────────────────────────────────────────┘

Swift Query:
  CppBridge.Services.listProviders(for: .llm) → ["LlamaCPP", "Apple Foundation Models"]
  CppBridge.Services.listProviders(for: .tts) → ["ONNXTTSService", "System TTS"]
  CppBridge.Services.listModules() → [{id: "llamacpp", ...}, {id: "onnx", ...}, ...]
```

**Platform services** (SystemTTS, AppleAI) use callback-based registration:
```swift
// In SystemTTSModule.swift
CppBridge.Services.registerPlatformService(
    name: moduleName,
    capability: .tts,
    priority: 10,
    canHandle: { voiceId in canHandle(voiceId: voiceId) },
    create: { try await createService() }
)

// Module is also registered in C++ for discovery
rac_module_register(&moduleInfo)
```

### Kept (Required)

1. 📌 **Protocol files** (`LLMService.swift`, `STTService.swift`, etc.) → Service classes conform to these
2. 📌 **`RunAnywhereModule` protocol** → Controlled Swift module structure
3. 📌 **Service classes** (`LlamaCPPService.swift`, `ONNXSTTService.swift`, etc.) → Already thin C++ wrappers

### Files Deleted (Phase 3)

| File | Lines | Reason |
|------|-------|--------|
| `ServiceRegistry.swift` | 280 | C++ `rac_service_register_provider()` |
| `ModuleDiscovery.swift` | 108 | Auto-registration via `autoRegister` property |
| `LlamaCPPRuntime.swift` | 96 | Merged into `LlamaCPP.swift` |
| `LlamaCPPServiceProvider.swift` | 114 | Merged into `LlamaCPP.swift` |
| `ONNXRuntime.swift` | 74 | Merged into `ONNX.swift` |
| `ONNXServiceProvider.swift` | 201 | Merged into `ONNX.swift` |
| **Total** | **~873** | **Simplified** |

---

### Remaining Goals

1. ✅ **Independent backend libraries created** - `runanywhere-llamacpp/` and `runanywhere-onnx/` inside `runanywhere-commons/`
2. 🔵 Remove Swift protocols once C++ interfaces are complete
3. 🔵 Further simplify service classes

---

### Target Architecture (IMPLEMENTED ✅)

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              REPOSITORY STRUCTURE                                │
│                                                                                  │
│  sdks/sdk/runanywhere-commons/         # ALL C++ CODE FOR ALL SDKs              │
│  │                                                                              │
│  ├── include/rac/                      # Core C++ headers                       │
│  │   ├── core/                         # Types, registry, lifecycle             │
│  │   │   ├── rac_service_registry.h   # Service registration                   │
│  │   │   ├── rac_module_registry.h    # Module registration                    │
│  │   │   └── rac_types.h              # Common types                           │
│  │   └── features/                                                              │
│  │       ├── llm/rac_llm_service.h    # LLM service interface                  │
│  │       ├── stt/rac_stt_service.h    # STT service interface                  │
│  │       ├── tts/rac_tts_service.h    # TTS service interface                  │
│  │       └── vad/rac_vad_service.h    # VAD service interface                  │
│  │                                                                              │
│  ├── backends/                         # Embedded backends (for simple builds)  │
│  │   ├── llamacpp/                    # LlamaCPP (embedded)                    │
│  │   ├── onnx/                        # ONNX (embedded)                        │
│  │   └── whispercpp/                  # WhisperCPP (embedded)                  │
│  │                                                                              │
│  ├── runanywhere-llamacpp/            # INDEPENDENT LlamaCPP library ✅         │
│  │   ├── CMakeLists.txt               # Standalone CMake project               │
│  │   ├── include/rac_llm_llamacpp.h   # LlamaCPP-specific API                  │
│  │   └── src/                         # Implementation                          │
│  │                                                                              │
│  ├── runanywhere-onnx/                # INDEPENDENT ONNX library ✅             │
│  │   ├── CMakeLists.txt               # Standalone CMake project               │
│  │   ├── include/                     # STT, TTS, VAD headers                  │
│  │   └── src/                         # Implementation                          │
│  │                                                                              │
│  └── src/                              # Core implementation                    │
│  │   │   └── src/                                                               │
│  │   │       ├── llamacpp_service.cpp  # Implements rac_llm_service.h interface │
│  │   │       └── llamacpp_register.cpp # Registers with rac_service_registry    │
│  │   │                                                                          │
│  │   ├── runanywhere-onnx/             # INDEPENDENT ONNX backend               │
│  │   │   ├── CMakeLists.txt            # Links against runanywhere-commons      │
│  │   │   ├── include/                                                           │
│  │   │   │   ├── rac_stt_onnx.h        # ONNX STT API                           │
│  │   │   │   ├── rac_tts_onnx.h        # ONNX TTS API                           │
│  │   │   │   └── rac_vad_onnx.h        # ONNX VAD API                           │
│  │   │   └── src/                                                               │
│  │   │       ├── onnx_stt_service.cpp  # Implements rac_stt_service.h           │
│  │   │       ├── onnx_tts_service.cpp  # Implements rac_tts_service.h           │
│  │   │       ├── onnx_vad_service.cpp  # Implements rac_vad_service.h           │
│  │   │       └── onnx_register.cpp     # Registers all ONNX services            │
│  │   │                                                                          │
│  │   ├── runanywhere-whispercpp/       # INDEPENDENT WhisperCPP backend         │
│  │   │   └── ...                                                                │
│  │   │                                                                          │
│  │   └── runanywhere-swift/            # Swift SDK                              │
│  │       └── Sources/                                                           │
│  │           ├── RunAnywhere/          # Main SDK                               │
│  │           │   ├── Core/                                                      │
│  │           │   │   └── Module/                                                │
│  │           │   │       └── RunAnywhereModule.swift  # KEEP: Module protocol   │
│  │           │   └── Foundation/                                                │
│  │           │       └── CapabilityManager.swift     # Calls C++ directly       │
│  │           │                                                                  │
│  │           ├── LlamaCPPRuntime/      # Thin Swift module                      │
│  │           │   ├── LlamaCPP.swift    # Module conformance + C++ bridge        │
│  │           │   └── include/          # LlamaCPPBackend.h bridge header        │
│  │           │                                                                  │
│  │           └── ONNXRuntime/          # Thin Swift module                      │
│  │               ├── ONNX.swift        # Module conformance + C++ bridge        │
│  │               └── include/          # ONNXBackend.h bridge header            │
│  │                                                                              │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

### C++ Service Interface Pattern

All service interfaces are defined in C++ headers. Platform backends implement these interfaces.

```c
// runanywhere-commons/include/rac/features/llm/rac_llm_service.h
// This is THE CANONICAL interface for ALL LLM services

/**
 * LLM Service Interface (like Swift's LLMService protocol)
 *
 * All LLM backends (LlamaCPP, ONNX, custom) MUST implement this interface.
 */

// Service lifecycle
RAC_API rac_result_t rac_llm_create(const char* model_path, rac_handle_t* out_handle);
RAC_API rac_result_t rac_llm_initialize(rac_handle_t handle, const char* model_path);
RAC_API void rac_llm_destroy(rac_handle_t handle);

// Generation
RAC_API rac_result_t rac_llm_generate(rac_handle_t handle, const char* prompt,
                                      const rac_llm_options_t* options,
                                      rac_llm_result_t* out_result);
RAC_API rac_result_t rac_llm_generate_stream(rac_handle_t handle, const char* prompt,
                                             const rac_llm_options_t* options,
                                             rac_llm_stream_callback_fn callback,
                                             void* user_data);

// State queries
RAC_API rac_result_t rac_llm_get_info(rac_handle_t handle, rac_llm_info_t* out_info);
RAC_API rac_result_t rac_llm_cancel(rac_handle_t handle);
RAC_API rac_result_t rac_llm_cleanup(rac_handle_t handle);
```

---

### C++ Service Registration

```c
// runanywhere-commons/include/rac/core/rac_service_registry.h (already exists in rac_core.h)

/**
 * Service Provider Registration
 *
 * Backends register themselves with the central registry.
 * The registry finds the best provider for a request.
 */

typedef struct rac_service_provider {
    const char* name;                    // "LlamaCPPService"
    rac_capability_t capability;         // RAC_CAPABILITY_TEXT_GENERATION
    int32_t priority;                    // 100 (higher = preferred)
    rac_service_can_handle_fn can_handle;// Check if can handle request
    rac_service_create_fn create;        // Factory function
    void* user_data;
} rac_service_provider_t;

// Register a provider
RAC_API rac_result_t rac_service_register_provider(const rac_service_provider_t* provider);

// Create service (finds best provider)
RAC_API rac_result_t rac_service_create(rac_capability_t capability,
                                        const rac_service_request_t* request,
                                        rac_handle_t* out_handle);
```

---

### Independent Backend Libraries

#### runanywhere-llamacpp (CMakeLists.txt)

```cmake
# runanywhere-llamacpp/CMakeLists.txt
cmake_minimum_required(VERSION 3.16)
project(runanywhere-llamacpp VERSION 1.0.0 LANGUAGES CXX)

# Find runanywhere-commons (required)
find_package(runanywhere-commons REQUIRED)

# Find llama.cpp (required)
find_package(llama REQUIRED)

# Create library
add_library(runanywhere-llamacpp
    src/llamacpp_service.cpp
    src/llamacpp_register.cpp
)

target_include_directories(runanywhere-llamacpp
    PUBLIC include
    PRIVATE ${llama_INCLUDE_DIRS}
)

target_link_libraries(runanywhere-llamacpp
    PUBLIC runanywhere-commons::core   # Links against commons
    PRIVATE llama                       # Links against llama.cpp
)

# Export for Swift/Kotlin consumption
install(TARGETS runanywhere-llamacpp
    EXPORT runanywhere-llamacpp-targets
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    INCLUDES DESTINATION include
)
```

#### Backend Registration Pattern

```cpp
// runanywhere-llamacpp/src/llamacpp_register.cpp

#include "rac/core/rac_core.h"
#include "rac_llm_llamacpp.h"

namespace {

rac_bool_t llamacpp_can_handle(const rac_service_request_t* request, void*) {
    if (!request || !request->identifier) return RAC_TRUE;  // Default provider

    // Check for .gguf extension
    const char* path = request->identifier;
    size_t len = strlen(path);
    if (len >= 5 && strcmp(path + len - 5, ".gguf") == 0) {
        return RAC_TRUE;
    }
    return RAC_FALSE;
}

rac_handle_t llamacpp_create(const rac_service_request_t* request, void*) {
    rac_handle_t handle = nullptr;
    rac_llm_llamacpp_create(request->identifier, nullptr, &handle);
    return handle;
}

}  // namespace

extern "C" rac_result_t rac_backend_llamacpp_register(void) {
    // Register module
    rac_module_info_t module = {
        .id = "llamacpp",
        .name = "LlamaCPP",
        .version = "1.0.0",
        .capabilities = (rac_capability_t[]){RAC_CAPABILITY_TEXT_GENERATION},
        .num_capabilities = 1
    };
    rac_module_register(&module);

    // Register service provider
    rac_service_provider_t provider = {
        .name = "LlamaCPPService",
        .capability = RAC_CAPABILITY_TEXT_GENERATION,
        .priority = 100,
        .can_handle = llamacpp_can_handle,
        .create = llamacpp_create
    };
    return rac_service_register_provider(&provider);
}
```

---

### Swift Module Pattern (Simplified)

Keep `RunAnywhereModule` protocol for controlled module structure, but remove `ServiceRegistry`.

```swift
// RunAnywhere/Core/Module/RunAnywhereModule.swift (KEEP - Simplified)

/// Protocol for SDK modules that provide AI capabilities.
/// Modules call C++ registration functions.
public protocol RunAnywhereModule {
    /// Unique identifier (e.g., "llamacpp")
    static var moduleId: String { get }

    /// Human-readable name
    static var moduleName: String { get }

    /// Capabilities this module provides
    static var capabilities: Set<SDKComponent> { get }

    /// Register this module with C++ registry
    @MainActor
    static func register()
}
```

#### Thin Swift Backend Wrapper

```swift
// LlamaCPPRuntime/LlamaCPP.swift (SIMPLIFIED - ~50 lines)

import CRACommons
import RunAnywhere

/// LlamaCPP module - thin wrapper that calls C++ registration
public enum LlamaCPP: RunAnywhereModule {
    public static let moduleId = "llamacpp"
    public static let moduleName = "LlamaCPP"
    public static let capabilities: Set<SDKComponent> = [.llm]

    /// Register with C++ registry
    @MainActor
    public static func register() {
        // Call C++ registration function directly
        let result = rac_backend_llamacpp_register()
        if result != RAC_SUCCESS {
            SDKLogger.shared.error("Failed to register LlamaCPP: \(result)")
        }
    }
}

// Auto-discovery support
extension LlamaCPP {
    public static let autoRegister: Void = {
        Task { @MainActor in
            LlamaCPP.register()
        }
    }()
}
```

---

### Files to Delete from Swift

| File | Lines | Reason |
|------|-------|--------|
| `ServiceRegistry.swift` | 280 | C++ `rac_service_register_provider()` |
| `LLMService.swift` | 100 | C++ `rac_llm_service.h` |
| `STTService.swift` | 47 | C++ `rac_stt_service.h` |
| `TTSService.swift` | 51 | C++ `rac_tts_service.h` |
| `VADService.swift` | 83 | C++ `rac_vad_service.h` |
| `ModuleDiscovery.swift` | 108 | C++ `rac_module_register()` |
| `LlamaCPPService.swift` | 329 | C++ `rac_llm_llamacpp.cpp` |
| `LlamaCPPServiceProvider.swift` | 114 | C++ registration |
| `ONNXSTTService.swift` | 332 | C++ `rac_stt_onnx.cpp` |
| `ONNXTTSService.swift` | 228 | C++ `rac_tts_onnx.cpp` |
| `ONNXServiceProvider.swift` | 201 | C++ registration |
| **Total** | **~1,873** | **Moved to C++** |

---

### Files to Keep in Swift

| File | Lines | Reason |
|------|-------|--------|
| `RunAnywhereModule.swift` | 84 | Module protocol (calls C++) |
| `LlamaCPP.swift` | ~50 | Thin wrapper (calls `rac_backend_llamacpp_register`) |
| `ONNX.swift` | ~60 | Thin wrapper (calls `rac_backend_onnx_register`) |
| `CapabilityManager.swift` | 312 | Manages C++ handles |
| `SystemTTSService.swift` | 179 | Apple `AVSpeechSynthesizer` (platform-only) |
| `AudioCaptureManager.swift` | 262 | Apple `AVAudioEngine` (platform-only) |
| `AudioPlaybackManager.swift` | 260 | Apple audio (platform-only) |

---

### Implementation Steps

#### Step 1: Create Independent C++ Backend Projects

```bash
# Create directory structure
mkdir -p sdks/sdk/runanywhere-llamacpp/{include,src}
mkdir -p sdks/sdk/runanywhere-onnx/{include,src}
mkdir -p sdks/sdk/runanywhere-whispercpp/{include,src}
```

**Move from `runanywhere-commons/backends/` to independent libraries:**
- `backends/llamacpp/` → `runanywhere-llamacpp/`
- `backends/onnx/` → `runanywhere-onnx/`
- `backends/whispercpp/` → `runanywhere-whispercpp/`

#### Step 2: Update C++ Service Interfaces

Ensure `rac_llm_service.h`, `rac_stt_service.h`, `rac_tts_service.h`, `rac_vad_service.h` are complete and serve as the **canonical interface**.

#### Step 3: Update Backend Registration

Each backend registers itself with `rac_service_register_provider()` instead of having Swift do registration.

#### Step 4: Create Swift Bridge Headers

```c
// LlamaCPPRuntime/include/LlamaCPPBackend.h
#ifndef LLAMACPP_BACKEND_H
#define LLAMACPP_BACKEND_H

#include <rac/core/rac_core.h>
#include <rac/features/llm/rac_llm_llamacpp.h>

// Re-export for Swift
RAC_API rac_result_t rac_backend_llamacpp_register(void);
RAC_API rac_result_t rac_backend_llamacpp_unregister(void);

#endif
```

#### Step 5: Simplify Swift Modules

Replace `LlamaCPPService.swift` (329 lines) + `LlamaCPPServiceProvider.swift` (114 lines) with `LlamaCPP.swift` (~50 lines).

#### Step 6: Delete Swift Protocols and ServiceRegistry

Once C++ registration is working, delete:
- `ServiceRegistry.swift`
- `LLMService.swift`
- `STTService.swift`
- `TTSService.swift`
- `VADService.swift`
- `ModuleDiscovery.swift`

---

### Expected Results

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| **Swift Service Layer** | ~1,873 lines | ~300 lines | **-1,573 lines (-84%)** |
| **C++ Backend Libraries** | Inside commons | Independent | **Modular** |
| **Cross-Platform** | Swift only | C++ canonical | **Shared** |

---

### Architecture After Phase 3

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              SWIFT LAYER (Thin)                                  │
│                                                                                  │
│  ┌───────────────────┐  ┌───────────────────┐  ┌─────────────────────────────┐  │
│  │ LlamaCPP.swift    │  │ ONNX.swift        │  │ SystemTTS.swift             │  │
│  │ (~50 lines)       │  │ (~60 lines)       │  │ (179 lines - Apple only)    │  │
│  │ Calls C++ register│  │ Calls C++ register│  │ AVSpeechSynthesizer         │  │
│  └─────────┬─────────┘  └─────────┬─────────┘  └─────────────────────────────┘  │
│            │                      │                                              │
│            ▼                      ▼                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                    CapabilityManager.swift                               │    │
│  │                    - Manages C++ handles                                 │    │
│  │                    - Calls rac_*_component_* functions                   │    │
│  └───────────────────────────────────┬─────────────────────────────────────┘    │
│                                      │                                           │
└──────────────────────────────────────┼───────────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         C++ LAYER (Source of Truth)                              │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                     runanywhere-commons (Core)                           │    │
│  │                                                                          │    │
│  │  ├── rac_service_registry.h    # Central registry                       │    │
│  │  ├── rac_llm_service.h         # LLM interface (THE protocol)           │    │
│  │  ├── rac_stt_service.h         # STT interface                          │    │
│  │  ├── rac_tts_service.h         # TTS interface                          │    │
│  │  ├── rac_vad_service.h         # VAD interface                          │    │
│  │  └── rac_llm_component.h       # Component (uses services)              │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                       │                                          │
│         ┌─────────────────────────────┼─────────────────────────────┐           │
│         │                             │                             │           │
│         ▼                             ▼                             ▼           │
│  ┌─────────────────┐       ┌─────────────────┐       ┌─────────────────┐        │
│  │ runanywhere-    │       │ runanywhere-    │       │ runanywhere-    │        │
│  │ llamacpp        │       │ onnx            │       │ whispercpp      │        │
│  │                 │       │                 │       │                 │        │
│  │ Implements:     │       │ Implements:     │       │ Implements:     │        │
│  │ rac_llm_service │       │ rac_stt_service │       │ rac_stt_service │        │
│  │                 │       │ rac_tts_service │       │                 │        │
│  │ Links: commons  │       │ rac_vad_service │       │ Links: commons  │        │
│  │        llama.cpp│       │                 │       │        whisper  │        │
│  └─────────────────┘       │ Links: commons  │       └─────────────────┘        │
│                            │        onnx     │                                   │
│                            └─────────────────┘                                   │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Previously Completed (Phase 1)

### Files Deleted

#### Capability Files (~1,963 lines)
| File | Lines | Reason |
|------|-------|--------|
| `LLMCapability.swift` | 500 | CapabilityManager provides direct C++ access |
| `STTCapability.swift` | 409 | CapabilityManager provides direct C++ access |
| `TTSCapability.swift` | 421 | CapabilityManager provides direct C++ access |
| `VADCapability.swift` | 268 | CapabilityManager provides direct C++ access |
| `VoiceAgentCapability.swift` | 365 | CapabilityManager provides direct C++ access |

#### Core Abstraction Files (~705 lines)
| File | Lines | Reason |
|------|-------|--------|
| `ManagedLifecycle.swift` | 329 | Unused - capabilities deleted |
| `ModelLifecycleManager.swift` | 187 | Unused - capabilities deleted |
| `ModelLoadableCapability.swift` | 88 | Protocol only used by deleted capabilities |
| `CoreAnalyticsTypes.swift` | 81 | Analytics now handled by C++ events |
| `ResourceTypes.swift` | 20 | Unused - referenced only by deleted files |

### Files Kept (Required for SDK Function)

#### ServiceRegistry & Protocols (~560 lines)
| File | Lines | Reason |
|------|-------|--------|
| `ServiceRegistry.swift` | 279 | Central registry for service providers |
| `LLMService.swift` | 100 | Protocol for LLM backends |
| `STTService.swift` | 47 | Protocol for STT backends |
| `TTSService.swift` | 51 | Protocol for TTS backends |
| `VADService.swift` | 83 | Protocol for VAD backends |

#### Platform Adapters (~701 lines)
| File | Lines | API Used |
|------|-------|----------|
| `AudioCaptureManager.swift` | 262 | AVAudioEngine, AVAudioSession |
| `AudioPlaybackManager.swift` | 260 | AVAudioPlayer |
| `SystemTTSService.swift` | 179 | AVSpeechSynthesizer |

---

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         PUBLIC API LAYER                                     │
│  RunAnywhere+TextGeneration.swift, RunAnywhere+STT.swift, etc.              │
│  - Direct C++ calls via CapabilityManager                                    │
│  - No intermediate capability layer                                          │
└─────────────────────────────────────┬───────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         CAPABILITY MANAGER (Actor)                           │
│  Foundation/CapabilityManager.swift                                          │
│  - Manages all C++ capability handles (llm, stt, tts, vad, voiceAgent)      │
│  - Thread-safe singleton                                                     │
│  - Direct wrappers for rac_*_component_* functions                          │
└─────────────────────────────────────┬───────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         C++ LAYER (runanywhere-commons)                      │
│  - All business logic (Features + Data)                                      │
│  - Analytics event emission via rac_analytics_event_emit()                  │
│  - State machines, validation, model management                             │
│  - HTTP request building, response parsing (Phase 2)                        │
│  - Authentication state management (Phase 2)                                 │
└─────────────────────────────────────┬───────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         PLATFORM BRIDGES                                     │
│  - CppEventBridge.swift (C++ events → Swift EventPublisher)                 │
│  - URLSession HTTP executor (Phase 2)                                        │
│  - KeychainManager for secure storage                                        │
└─────────────────────────────────────────────────────────────────────────────┘
```
