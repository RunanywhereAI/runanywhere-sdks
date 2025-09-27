# Network Layer Implementation Plan - JVM First Approach
**Date**: September 14, 2025
**Updated**: Based on comparison documents and existing implementations
**Objective**: Implement comprehensive network layer for Kotlin Multiplatform SDK with API key initialization and device registration, prioritizing JVM platform

## Executive Summary
Implement a robust network layer for the Kotlin Multiplatform SDK that mirrors the iOS SDK's functionality while leveraging Kotlin's strengths. The implementation follows a **JVM-first approach** to establish working functionality quickly, with architecture designed for easy multiplatform expansion. All business logic will be in `commonMain` with platform-specific implementations in `jvmMain` initially.

## Key Architecture Decisions (Based on Comparison Analysis)
1. **commonMain First**: All interfaces, models, and business logic in `commonMain`
2. **JVM Priority**: Focus on `jvmMain` implementation using OkHttp (already partially implemented)
3. **iOS Parity**: Follow iOS implementation as source of truth for API contracts
4. **Existing Code Base**: Leverage existing `OkHttpEngine` and `APIClient` implementations
5. **Authentication Focus**: Prioritize token management and device registration over advanced features

## Phase 1: Core Network Infrastructure (Day 1)
**Focus**: Enhance existing network layer in `commonMain` and `jvmMain`

### 1.1 Network Service Architecture
- [ ] **Update existing `NetworkService` interface** in `commonMain` to match iOS exactly:
  ```kotlin
  // Already exists, needs alignment with iOS
  interface NetworkService {
      suspend fun postRaw(endpoint: APIEndpoint, payload: ByteArray, requiresAuth: Boolean = true): ByteArray
      suspend fun getRaw(endpoint: APIEndpoint, requiresAuth: Boolean = true): ByteArray
      suspend fun post<T: Any, R: Any>(endpoint: APIEndpoint, payload: T, requiresAuth: Boolean = true): R
      suspend fun get<R: Any>(endpoint: APIEndpoint, requiresAuth: Boolean = true): R
  }
  ```
- [ ] **Align `APIEndpoint` enum** with iOS naming (change from SNAKE_CASE to camelCase):
  ```kotlin
  enum class APIEndpoint(val path: String) {
      authenticate("/api/v1/auth/sdk/authenticate"),
      refreshToken("/api/v1/auth/sdk/refresh"),
      registerDevice("/api/v1/devices/register"),
      healthCheck("/api/v1/health"),
      configuration("/api/v1/configuration"),
      telemetry("/api/v1/telemetry"),
      models("/api/v1/models"),
      history("/api/v1/history"),
      preferences("/api/v1/preferences")
  }
  ```
- [ ] **Enhance existing `NetworkServiceFactory`** to use environment detection

### 1.2 JVM Implementation Enhancement
- [ ] **Enhance existing `OkHttpEngine`** in `jvmMain`:
  - Already has comprehensive configuration support
  - Add missing authentication header injection
  - Implement device registration endpoint support
  - Ensure 30-second timeout is configured
- [ ] **Update `APIClient`** to use enhanced OkHttpEngine:
  - Leverage existing retry logic with exponential backoff
  - Add token refresh mechanism
  - Implement one-time device registration check

### 1.3 Mock Network Service (Lower Priority)
- [ ] Create `MockNetworkService` in `commonMain` for testing:
  - Match iOS mock implementation structure
  - Return hardcoded successful responses
  - Will be implemented after core functionality works

## Phase 2: Authentication System (Day 2)

### 2.1 Authentication Models
- [ ] **Update existing models** in `commonMain/kotlin/com/runanywhere/sdk/data/models/`:
  ```kotlin
  // Match iOS implementation exactly from PR #49
  data class AuthenticationRequest(
      val apiKey: String,
      val deviceId: String,
      val sdkVersion: String,
      val platform: String,
      val platformVersion: String? = null,
      val appIdentifier: String? = null
  )

  data class AuthenticationResponse(
      val accessToken: String,
      val refreshToken: String,
      val expiresIn: Int,
      val tokenType: String,
      val deviceId: String,
      val organizationId: String,
      val userId: String? = null,
      val tokenExpiresAt: Long? = null
  )

  data class RefreshTokenRequest(
      val refreshToken: String,
      val grantType: String = "refresh_token"
  )

  data class RefreshTokenResponse(
      val accessToken: String,
      val refreshToken: String,
      val expiresIn: Int,
      val tokenType: String
  )
  ```

### 2.2 Authentication Service Enhancement
- [ ] **Enhance existing `AuthenticationService`** (already in `commonMain`):
  - Already has iOS-compatible interface
  - Add missing token refresh implementation (currently TODO)
  - Implement device ID and organization ID getters
  - Add health check method
- [ ] **JVM SecureStorage Implementation**:
  - Fix existing `JvmSecureStorage` security issues identified in comparison
  - Use PBKDF2 for key derivation instead of plain AES
  - Set proper file permissions (owner-only)
  - Store in `~/.runanywhere/secure/` with restricted access

### 2.3 Token Management
- [ ] **Implement token refresh** (critical gap from comparison):
  ```kotlin
  suspend fun refreshAccessToken(): String {
      val refreshToken = secureStorage.getSecureString(KEY_REFRESH_TOKEN)
          ?: throw SDKError.NotAuthenticated("No refresh token available")

      val request = RefreshTokenRequest(refreshToken)
      val response = apiClient.post<RefreshTokenRequest, RefreshTokenResponse>(
          APIEndpoint.refreshToken,
          request,
          requiresAuth = false
      )

      // Store new tokens
      storeTokens(response)
      return response.accessToken
  }
  ```
- [ ] Add 1-minute buffer for token expiration (match iOS)
- [ ] Implement retry with token refresh on 401

## Phase 3: Device Registration (Day 3)

### 3.1 Device Identity Management
- [ ] **Create `PersistentDeviceIdentity`** in `commonMain`:
  ```kotlin
  class PersistentDeviceIdentity(private val secureStorage: SecureStorage) {
      suspend fun getDeviceId(): String {
          // Check storage first
          secureStorage.getSecureString(KEY_DEVICE_UUID)?.let { return it }

          // Generate new UUID
          val deviceId = generateDeviceId()
          secureStorage.setSecureString(KEY_DEVICE_UUID, deviceId)
          return deviceId
      }
  }
  ```
- [ ] **JVM-specific implementation** in `jvmMain`:
  - Use combination of MAC address + hostname + user.home hash
  - Store in secure storage for persistence

### 3.2 Device Information Collection
- [ ] **Create `DeviceRegistrationInfo`** matching iOS (from PR #49):
  ```kotlin
  data class DeviceRegistrationInfo(
      val architecture: String,
      val chipName: String? = null,
      val coreCount: Int,
      val deviceModel: String,
      val hasNeuralEngine: Boolean = false,
      val platform: String,
      val totalMemory: Long,
      val osVersion: String,
      val formFactor: String,
      val deviceId: String,
      val sdkVersion: String,
      val appIdentifier: String? = null,
      val batteryLevel: Float? = null,
      val thermalState: String? = null
  )
  ```
- [ ] **JVM Device Info Collector**:
  ```kotlin
  // jvmMain
  actual fun collectDeviceInfo(): DeviceRegistrationInfo {
      return DeviceRegistrationInfo(
          architecture = System.getProperty("os.arch"),
          coreCount = Runtime.getRuntime().availableProcessors(),
          deviceModel = InetAddress.getLocalHost().hostName,
          platform = "JVM",
          totalMemory = Runtime.getRuntime().maxMemory(),
          osVersion = System.getProperty("os.version"),
          formFactor = "desktop",
          deviceId = persistentDeviceIdentity.getDeviceId(),
          sdkVersion = SDKConstants.version
      )
  }
  ```

### 3.3 Device Registration Flow
- [ ] **Implement one-time registration**:
  ```kotlin
  class DeviceRegistrationService(
      private val apiClient: APIClient,
      private val secureStorage: SecureStorage
  ) {
      suspend fun registerDeviceIfNeeded() {
          // Check if already registered
          if (secureStorage.getSecureString(KEY_DEVICE_REGISTERED) == "true") {
              return
          }

          val deviceInfo = collectDeviceInfo()
          val response = apiClient.post(
              APIEndpoint.registerDevice,
              deviceInfo,
              requiresAuth = true
          )

          // Mark as registered
          secureStorage.setSecureString(KEY_DEVICE_REGISTERED, "true")
          secureStorage.setSecureString(KEY_DEVICE_ID, response.deviceId)
      }
  }
  ```

## Phase 4: SDK Initialization (Day 4)

### 4.1 SDK Entry Point Enhancement
- [ ] **Update existing `RunAnywhere` object** in `jvmMain`:
  ```kotlin
  actual object RunAnywhere {
      actual suspend fun initialize(
          apiKey: String,
          environment: Environment = Environment.PRODUCTION,
          configuration: SDKConfiguration? = null
      ): InitializationResult {
          // 1. Validate API key
          require(apiKey.isNotBlank()) { "API key cannot be blank" }

          // 2. Setup services
          val secureStorage = JvmSecureStorage()
          val httpClient = OkHttpEngine(NetworkConfiguration.forEnvironment(environment))
          val apiClient = APIClient(httpClient, configuration)
          val authService = AuthenticationService(apiClient, secureStorage)

          // 3. Authenticate
          val authResponse = authService.authenticate(apiKey)

          // 4. Register device
          val deviceService = DeviceRegistrationService(apiClient, secureStorage)
          deviceService.registerDeviceIfNeeded()

          // 5. Initialize service container
          ServiceContainer.shared.initialize(PlatformContext())

          return InitializationResult.Success
      }
  }
  ```

### 4.2 Configuration Management
- [ ] **Use existing `ConfigurationService`**:
  - Already implemented in `commonMain`
  - Add remote config fetching via `/api/v1/configuration`
  - Cache configuration in secure storage
  - Use existing `ConfigurationData` model

### 4.3 Initialization States
- [ ] **Leverage existing `ComponentState`** enum:
  - Already has state tracking in `BaseComponent`
  - Extend for SDK-level initialization tracking
  - Use existing `EventBus` for state change notifications

## Phase 5: Error Handling & Testing (Day 5)

### 5.1 Error Types
- [ ] **Enhance existing `SDKError`** sealed class:
  ```kotlin
  // Already exists, add network-specific errors
  sealed class SDKError : Exception() {
      // Existing errors
      data class InvalidAPIKey(override val message: String) : SDKError()
      data class NetworkError(override val message: String, val statusCode: Int? = null) : SDKError()

      // Add new errors
      data class TokenExpired(override val message: String) : SDKError()
      data class DeviceRegistrationFailed(override val message: String) : SDKError()
      data class RateLimitExceeded(val retryAfter: Long?) : SDKError()
  }
  ```

### 5.2 Testing
- [ ] **Unit tests for JVM implementation**:
  - Test authentication flow
  - Test device registration
  - Test token refresh
  - Test error handling
- [ ] **Integration tests**:
  - Full initialization flow
  - Network error scenarios
  - Token expiration handling

### 5.3 Documentation
- [ ] Update README with initialization example
- [ ] Document API key requirements
- [ ] Add troubleshooting guide

## Future Phases (After JVM Works)

### Phase 6: Android Support
- Implement `AndroidAPIClient` using existing OkHttp base
- Add `AndroidSecureStorage` (already implemented)
- Test on Android devices

### Phase 7: Native Platform Support
- Replace mock `NativeHttpClient` with real implementation
- Implement native secure storage
- Add iOS bridge if needed

### Phase 8: Advanced Features
- Download service with resume support
- Certificate pinning
- Biometric authentication
- Advanced threat detection

## Technical Stack

### Current Dependencies (Already in Project)
```kotlin
// Existing in build.gradle.kts
dependencies {
    // Network - Already using OkHttp directly
    jvmImplementation("com.squareup.okhttp3:okhttp:4.12.0")
    jvmImplementation("com.squareup.okhttp3:logging-interceptor:4.12.0")

    // Serialization - Already configured
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")

    // Coroutines - Already configured
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.9.0")

    // Security - Needs addition for JVM
    jvmImplementation("org.bouncycastle:bcprov-jdk15on:1.70") // For PBKDF2
}
```

### Required Additions
```kotlin
// Only need to add:
jvmImplementation("org.bouncycastle:bcprov-jdk15on:1.70") // For secure key derivation
```

## Success Criteria (JVM Focus)

1. **Functional Requirements - JVM**
   - ✅ SDK initializes with API key on JVM
   - ✅ Device registers automatically (once) on JVM
   - ✅ Tokens persist securely with proper encryption
   - ✅ Automatic token refresh works
   - ✅ JVM platform fully functional

2. **Security Requirements - JVM**
   - ✅ Fix JVM secure storage vulnerabilities (PBKDF2, file permissions)
   - ✅ Tokens encrypted with proper key derivation
   - ✅ No sensitive data in logs
   - ✅ Device ID persistence across restarts

3. **Code Quality**
   - ✅ All business logic in `commonMain`
   - ✅ Platform code only in `jvmMain`
   - ✅ Matches iOS API contracts
   - ✅ Comprehensive error handling

## Identified Gaps to Address (From Comparison)

| Gap | Priority | Solution |
|------|----------|----------|
| Missing token refresh | **CRITICAL** | Implement in Day 2 |
| JVM storage vulnerabilities | **CRITICAL** | Fix with PBKDF2 and file permissions |
| Endpoint naming mismatch | HIGH | Align with iOS camelCase |
| No device registration | HIGH | Implement in Day 3 |
| Missing retry mechanism | MEDIUM | Already exists in OkHttpEngine |

## Timeline (JVM Focused)

- **Day 1**: Network infrastructure alignment
- **Day 2**: Authentication with token refresh
- **Day 3**: Device registration
- **Day 4**: SDK initialization flow
- **Day 5**: Testing and documentation

**Total: 5 days for JVM implementation**

## Next Steps

1. Review and approve this updated JVM-first plan
2. Fix critical security issues in `JvmSecureStorage`
3. Align `APIEndpoint` naming with iOS
4. Implement token refresh mechanism
5. Add device registration flow
6. Test complete initialization on JVM

## Implementation Order (Priority)

1. **Fix `JvmSecureStorage`** (security critical)
2. **Implement token refresh** (functionality critical)
3. **Add device registration**
4. **Complete initialization flow**
5. **Add comprehensive tests**

## Implementation Notes

- **iOS as Source of Truth**: Follow iOS implementation exactly for API contracts
- **Leverage Existing Code**: Build on existing `OkHttpEngine`, `APIClient`, `AuthenticationService`
- **commonMain First**: All business logic, interfaces, models in `commonMain`
- **JVM Focus**: Get JVM working first, then expand to other platforms
- **Security Priority**: Fix JVM storage vulnerabilities immediately
- **Clear Naming**: Use `Jvm` prefix for platform implementations

## Files to Modify/Create

### commonMain
- ✏️ `APIEndpoint.kt` - Align naming with iOS
- ✏️ `AuthenticationService.kt` - Add token refresh
- ✅ `NetworkService.kt` - Already exists, may need minor updates
- 🆕 `DeviceRegistrationService.kt` - New service for device registration
- 🆕 `PersistentDeviceIdentity.kt` - Device ID management

### jvmMain
- ✏️ `JvmSecureStorage.kt` - Fix security issues
- ✏️ `OkHttpEngine.kt` - Add auth headers
- ✏️ `RunAnywhere.kt` - Complete initialization flow
- 🆕 `JvmDeviceInfoCollector.kt` - Collect device information
