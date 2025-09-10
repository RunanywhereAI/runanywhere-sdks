# Network Layer Comparison: iOS vs KMP SDKs

## Overview
This document provides a comprehensive analysis comparing the network layer implementations between the iOS Swift SDK and Kotlin Multiplatform (KMP) SDK. Both SDKs implement HTTP clients, API services, authentication, and error handling, but with different underlying technologies and architectural approaches.

## iOS Implementation

### Core Architecture
- **Primary HTTP Client**: Uses `URLSession` with `URLSessionConfiguration`
- **Download Service**: `AlamofireDownloadService` using Alamofire framework with advanced retry policies
- **Protocol-Based Design**: `NetworkService` protocol with default implementations
- **Actor-Based Concurrency**: `APIClient` implemented as an actor for thread safety
- **Logging Integration**: Uses Pulse framework for automatic network logging

### URLSession Configuration
```swift
let config = URLSessionConfiguration.default
config.timeoutIntervalForRequest = 30.0
config.httpAdditionalHeaders = [
    "Content-Type": "application/json",
    "X-SDK-Client": "RunAnywhereSDK",
    "X-SDK-Version": SDKConstants.version,
    "X-Platform": SDKConstants.platform
]
```

### API Client Structure
- **Base URL Management**: Single baseURL with endpoint path appending
- **Authentication Integration**: Token-based auth with automatic header injection
- **Error Handling**: Throws `SDKError` and `RepositoryError` with structured error messages
- **Response Validation**: Checks for 200 status codes, throws on HTTP errors
- **Thread Safety**: Actor isolation ensures safe concurrent access

### Request/Response Handling
- **Request Flow**:
  1. Build URLRequest with endpoint path
  2. Add authentication headers (Bearer token or API key)
  3. Execute via URLSession
  4. Validate HTTP response
  5. Return raw Data or throw structured errors

- **Response Processing**:
  - JSON encoding/decoding with ISO8601 date strategy
  - Generic type support through protocol extensions
  - Automatic error mapping from HTTP status codes

### Error Management
- **HTTP Status Code Mapping**:
  - 401/403 → Authentication errors
  - 404 → Endpoint not found
  - 500+ → Server errors
- **Structured Error Types**: `SDKError` and `RepositoryError` enums
- **Error Context**: Includes endpoint, method, and status code in error messages

### Retry Mechanisms (Alamofire Download Service)
```swift
let retryPolicy = RetryPolicy(
    retryLimit: UInt(configuration.retryCount),
    exponentialBackoffBase: 2,
    exponentialBackoffScale: configuration.retryDelay,
    retryableHTTPMethods: [.get, .post]
)
```
- **Exponential Backoff**: Base 2 with configurable scale
- **Configurable Retry Count**: Default 3 attempts
- **HTTP Method Filtering**: Only retries GET and POST requests
- **Automatic Integration**: Built into Alamofire session configuration

### Download Management
- **Progress Tracking**: AsyncStream-based progress reporting
- **Resume Support**: Built-in download resumption with resume data persistence
- **Custom Strategies**: Plugin-based download strategy system
- **Framework Integration**: Automatic adapter discovery for specialized download needs
- **File Management**: Integration with SimplifiedFileManager for destination handling

## KMP Implementation

### Core Architecture
- **HTTP Client Interface**: Platform-agnostic `HttpClient` interface
- **Platform-Specific Engines**:
  - **JVM/Android**: `OkHttpEngine` using OkHttp3
  - **Native**: `NativeHttpClient` (mock implementation)
- **Service Layer**: `APIClient` class implementing comprehensive HTTP operations
- **Configuration-Driven**: `NetworkConfiguration` with extensive customization options

### Platform-Specific HTTP Clients

#### JVM/Android (OkHttp)
```kotlin
internal class OkHttpEngine(
    private val config: NetworkConfiguration = NetworkConfiguration.production()
) : HttpClient
```
**Features:**
- Complete OkHttp3 integration with connection pooling
- SSL/TLS configuration with certificate pinning
- Proxy support (HTTP, SOCKS, Direct)
- Response caching with configurable cache directory
- Progress tracking for uploads/downloads
- Multipart form support
- Comprehensive logging with OkHttp interceptors

#### Native Platform
- **Current State**: Mock implementation returning static responses
- **Production Need**: Requires platform-specific HTTP client implementation
- **Missing Features**: No actual network requests, all responses are mocked

### API Client Structure
- **Comprehensive Configuration**: Timeout, retry, TLS, proxy, caching options
- **Interceptor Support**: Request and response interceptor interfaces
- **Authentication Integration**: Bearer token and API key authentication
- **Network Connectivity**: Platform-specific network checking
- **Retry Logic**: Built-in exponential backoff with jitter

### Request/Response Handling
- **Request Builder Pattern**:
  ```kotlin
  private suspend fun executeWithRetry(
      method: String,
      endpoint: String,
      payload: ByteArray?,
      requiresAuth: Boolean,
      httpCall: suspend (NetworkRequest) -> HttpResponse
  ): ByteArray
  ```

- **Response Processing**:
  - Kotlinx.serialization for JSON handling
  - Generic extension functions (`postJson`, `getJson`, `putJson`)
  - ByteArray-based core operations with string conversion helpers

### Error Management
- **Structured Error Types**: `SDKError` sealed class hierarchy
- **HTTP Status Mapping**:
  ```kotlin
  when (statusCode) {
      401 -> SDKError.InvalidAPIKey("Authentication failed")
      403 -> SDKError.InvalidAPIKey("Access forbidden")
      404 -> SDKError.NetworkError("Endpoint not found")
      408 -> SDKError.NetworkError("Request timeout")
      429 -> SDKError.NetworkError("Rate limit exceeded")
      in 500..599 -> SDKError.NetworkError("Server error $statusCode")
  }
  ```
- **Exception-Based Flow**: Uses suspend functions with exception throwing
- **Context-Rich Errors**: Includes endpoint, method, and attempt information

### Retry Mechanisms
```kotlin
private suspend fun executeWithRetry(...): ByteArray {
    var attempt = 0
    while (attempt < maxRetryAttempts) {
        try {
            // Execute request
            if (networkResponse.isSuccessful) {
                return networkResponse.body
            } else {
                if (shouldRetry(networkResponse.statusCode, attempt)) {
                    val delayMs = calculateBackoffDelay(attempt)
                    delay(delayMs)
                    continue
                }
                throw error
            }
        } catch (e: Exception) {
            // Retry logic with exponential backoff
        }
    }
}
```

**Features:**
- **Exponential Backoff**: Configurable base delay and multiplier
- **Jitter**: Randomization to prevent thundering herd
- **Smart Retry Logic**: Only retries appropriate status codes (408, 429, 5xx)
- **Exception Filtering**: Doesn't retry authentication or client errors
- **Configurable Attempts**: Default 3 attempts with customization

### Network Configuration
- **Comprehensive Options**: 50+ configuration parameters
- **Environment Profiles**: Production, development, testing configurations
- **Builder Pattern**: Fluent configuration building
- **Validation**: Built-in configuration validation with error reporting
- **Platform Adaptation**: Configuration translates to platform-specific implementations

### Common Implementation (NetworkService Interface)
```kotlin
interface NetworkService {
    suspend fun postRaw(endpoint: APIEndpoint, payload: ByteArray, requiresAuth: Boolean = true): ByteArray
    suspend fun getRaw(endpoint: APIEndpoint, requiresAuth: Boolean = true): ByteArray
}
```

## Gaps and Misalignments

### API Endpoint Differences
**iOS APIEndpoint (enum with computed property):**
```swift
enum APIEndpoint {
    case authenticate
    case healthCheck

    var path: String {
        switch self {
        case .authenticate: return "/v1/auth/token"
        case .healthCheck: return "/v1/health"
        }
    }
}
```

**KMP APIEndpoint (enum with constructor parameter):**
```kotlin
enum class APIEndpoint(val url: String) {
    AUTHENTICATE("/v1/auth/token"),
    HEALTH_CHECK("/v1/health")
}
```

**Gap**: Different naming conventions (camelCase vs SNAKE_CASE) and implementation approaches, but functionally equivalent.

### Error Handling Disparities

#### iOS Error Flow
- Uses Swift's `throws` mechanism with structured error types
- `SDKError` and `RepositoryError` provide domain-specific error categorization
- Error messages include contextual information (endpoint, method, status code)

#### KMP Error Flow
- Uses Kotlin's exception mechanism with sealed class hierarchy
- `SDKError` sealed class with specific error types
- Similar contextual information but different error propagation patterns

**Gap**: Error handling approaches are architecturally different but provide equivalent functionality.

### Feature Disparities

#### Download Management
**iOS Advantages:**
- Full Alamofire integration with resume support
- Custom download strategy system
- Progress tracking with AsyncStreams
- Automatic adapter discovery
- File system integration

**KMP Limitations:**
- Basic download functionality in `HttpClient` interface
- No built-in resume support
- Progress callback through function parameters
- No download strategy system
- Platform-specific file handling via `expect`/`actual`

#### Authentication Service Integration
**iOS:**
```swift
public actor AuthenticationService {
    private let apiClient: APIClient

    public func getAccessToken() async throws -> String {
        // Token validation and refresh logic
    }
}
```

**KMP:**
```kotlin
class DefaultAuthenticationService(
    private val apiClient: APIClient,
    private val secureStorage: SecureStorage
) : AuthenticationService {

    override suspend fun getAccessToken(): String {
        // Token validation and refresh logic
    }
}
```

**Gap**: Both implement similar functionality but iOS uses actor isolation while KMP uses traditional class-based approach with external secure storage.

### Network Client Abstraction Level

#### iOS
- **High-level**: Primary focus on `URLSession` with protocol-based abstraction
- **Framework Integration**: Leverages Alamofire for advanced features
- **Logging**: Automatic integration with Pulse framework
- **Thread Safety**: Actor-based concurrency model

#### KMP
- **Low-level Control**: Platform-specific HTTP client implementations
- **Configuration-Heavy**: Extensive configuration options expose underlying HTTP client features
- **Manual Integration**: Explicit setup of logging, caching, SSL features
- **Coroutine-Based**: Uses structured concurrency with coroutines

### Platform-Specific Implementations

#### Native Platform Support
**iOS**: Full URLSession implementation works across all Apple platforms
**KMP**:
- ✅ **JVM/Android**: Complete OkHttp implementation
- ❌ **Native**: Mock implementation only - major gap for production use

#### Interceptor Systems
**iOS**: Uses Alamofire's interceptor system built into session configuration
**KMP**: Custom interceptor interfaces with manual application in request/response chain

#### SSL/TLS Configuration
**iOS**: Relies on URLSession's default SSL handling with minimal custom configuration
**KMP**: Comprehensive SSL configuration including:
- Certificate pinning with SHA-256 pin support
- TLS version specification (1.2, 1.3)
- Custom hostname verification
- Proxy authentication support

## Recommendations to Address Gaps

### 1. Client Standardization

#### Standardize API Endpoint Naming
```kotlin
// Current KMP
enum class APIEndpoint(val url: String) {
    AUTHENTICATE("/v1/auth/token"),
    HEALTH_CHECK("/v1/health")
}

// Recommended: Align with iOS naming
enum class APIEndpoint(val path: String) {
    authenticate("/v1/auth/token"),
    healthCheck("/v1/health")
}
```

#### Unify Request/Response Models
Ensure authentication and response models use consistent field names and types across platforms.

### 2. Error Handling Alignment

#### Standardize Error Types
Create equivalent error hierarchies that map consistently between platforms:

```kotlin
// KMP
sealed class SDKError : Exception() {
    data class AuthenticationFailed(override val message: String) : SDKError()
    data class InvalidAPIKey(override val message: String) : SDKError()
    data class NetworkError(override val message: String) : SDKError()
    data class NotInitialized(override val message: String) : SDKError()
}
```

```swift
// iOS - Already well-structured
enum SDKError: Error {
    case authenticationFailed(String)
    case invalidAPIKey(String)
    case networkError(String)
    case notInitialized
}
```

### 3. Download System Parity

#### Implement KMP Download Manager
Create a comprehensive download system matching iOS capabilities:

```kotlin
interface DownloadManager {
    suspend fun downloadModel(model: ModelInfo): DownloadTask
    fun cancelDownload(taskId: String)
    fun activeDownloads(): List<DownloadTask>
    fun registerStrategy(strategy: DownloadStrategy)
}

data class DownloadTask(
    val id: String,
    val modelId: String,
    val progress: Flow<DownloadProgress>,
    val result: Deferred<URL>
)
```

#### Add Resume Support
Extend the HTTP client interface and OkHttp implementation to support download resumption:

```kotlin
interface HttpClient {
    suspend fun downloadResumable(
        url: String,
        resumeData: ByteArray? = null,
        onProgress: ((Long, Long) -> Unit)? = null
    ): Pair<ByteArray, ByteArray?> // content, resumeData
}
```

### 4. Native Platform Implementation

#### Replace Mock Native Client
Implement actual HTTP client for native platforms using platform-specific libraries:

```kotlin
// nativeMain/kotlin/.../NativeHttpClient.kt
internal class NativeHttpClient : HttpClient {
    // Use platform-specific HTTP implementation:
    // - macOS/iOS: NSURLSession via cinterop
    // - Linux: libcurl via cinterop
    // - Windows: WinHTTP via cinterop
}
```

### 5. Logging Standardization

#### Unified Logging Approach
Standardize network logging across platforms:

```kotlin
// KMP
interface NetworkLogger {
    fun logRequest(method: String, url: String, headers: Map<String, String>, body: ByteArray?)
    fun logResponse(statusCode: Int, headers: Map<String, List<String>>, body: ByteArray, duration: Long)
    fun logError(error: Throwable, context: String)
}
```

```swift
// iOS - leverage existing Pulse integration
// Ensure consistent log levels and formats
```

### 6. Configuration Consistency

#### Network Configuration Parity
Ensure KMP's comprehensive `NetworkConfiguration` has equivalent iOS counterpart, or simplify KMP configuration to match iOS approach:

```swift
// iOS - Add comprehensive configuration if needed
public struct NetworkConfiguration {
    let timeout: TimeInterval
    let retryCount: Int
    let enableLogging: Bool
    // Add other essential options
}
```

### 7. Authentication Service Standardization

#### Consistent Interface
Standardize authentication service interfaces:

```kotlin
// KMP - Already good
interface AuthenticationService {
    suspend fun authenticate(apiKey: String): AuthenticationResponse
    suspend fun getAccessToken(): String
    suspend fun refreshToken(): String
    fun isAuthenticated(): Boolean
    suspend fun clearAuthentication()
    suspend fun healthCheck(): HealthCheckResponse
}
```

```swift
// iOS - Already matches well
protocol AuthenticationService {
    func authenticate(apiKey: String) async throws -> AuthenticationResponse
    func getAccessToken() async throws -> String
    func refreshToken() async throws -> String
    func isAuthenticated() -> Bool
    func clearAuthentication() async throws
    func healthCheck() async throws -> HealthCheckResponse
}
```

## Conclusion

Both iOS and KMP networking implementations are well-architected but with different strengths:

**iOS Strengths:**
- Clean protocol-based design with actor safety
- Excellent integration with platform frameworks (Alamofire, Pulse)
- Comprehensive download management system
- Consistent across all Apple platforms

**KMP Strengths:**
- Highly configurable and feature-rich
- Platform-optimized implementations (excellent OkHttp integration)
- Comprehensive SSL/TLS and proxy support
- Detailed retry and backoff mechanisms

**Major Gaps to Address:**
1. **Native platform implementation** - Critical gap requiring actual HTTP client
2. **Download system parity** - KMP needs comprehensive download management
3. **Resume support** - Essential for large file downloads
4. **Configuration consistency** - Either simplify KMP or enhance iOS configuration

**Priority Recommendations:**
1. **High Priority**: Implement native platform HTTP client
2. **High Priority**: Create comprehensive download manager for KMP
3. **Medium Priority**: Standardize error handling and logging
4. **Low Priority**: Align naming conventions and configuration approaches

The networking layers provide solid foundations but require focused effort on native platform support and download system parity to achieve true cross-platform equivalence.
