# Authentication & Security Comparison

## Executive Summary

This document provides a comprehensive analysis of authentication and security implementations between the iOS Swift SDK (`sdk/runanywhere-swift/`) and the Kotlin Multiplatform (KMP) SDK (`sdk/runanywhere-kotlin/`). The analysis reveals strong architectural alignment between the platforms with some critical security gaps that require immediate attention.

## iOS Implementation

### Authentication Flow

The iOS SDK implements a robust authentication system using an actor-based approach for thread safety:

**Key Components:**
- `AuthenticationService` (actor) - Thread-safe authentication management
- `KeychainManager` (singleton) - Secure credential storage
- `APIClient` - HTTP client with authentication integration

**Authentication Process:**
1. **Initial Authentication**: Uses API key + device ID to obtain access/refresh tokens
2. **Token Storage**: Stores tokens securely in iOS Keychain
3. **Token Refresh**: Automatic refresh with 1-minute buffer (not implemented yet)
4. **Health Check**: Validates authentication state with backend

**File:** `/Users/sanchitmonga/development/ODLM/sdks.worktree/android_init/sdk/runanywhere-swift/Sources/RunAnywhere/Data/Network/Services/AuthenticationService.swift`

```swift
public actor AuthenticationService {
    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiresAt: Date?

    public func authenticate(apiKey: String) async throws -> AuthenticationResponse {
        // Device ID generation + API request
        // Token storage in keychain
    }

    public func getAccessToken() async throws -> String {
        // Token validation with 1-minute buffer
        // Automatic refresh if needed
    }
}
```

### Keychain Usage

The iOS implementation leverages the iOS Keychain for maximum security:

**Security Features:**
- **Service Name**: `com.runanywhere.sdk` (namespace isolation)
- **Accessibility**: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (device-only, unlock required)
- **Synchronization**: Disabled (`kSecAttrSynchronizable: false`)
- **Access Groups**: Configurable for app group sharing

**Stored Data:**
- API Key (`com.runanywhere.sdk.apiKey`)
- Base URL (`com.runanywhere.sdk.baseURL`)
- Environment (`com.runanywhere.sdk.environment`)
- Access Token (`com.runanywhere.sdk.accessToken`)
- Refresh Token (`com.runanywhere.sdk.refreshToken`)
- Device UUID (`com.runanywhere.sdk.device.uuid`)
- Device Fingerprint (`com.runanywhere.sdk.device.fingerprint`)

**File:** `/Users/sanchitmonga/development/ODLM/sdks.worktree/android_init/sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Security/KeychainManager.swift`

### Token Management

**Token Lifecycle:**
- **Expiration Handling**: 1-minute buffer before expiry
- **Refresh Strategy**: Placeholder for refresh endpoint (not implemented)
- **Storage**: Immediate keychain storage after authentication
- **Cleanup**: Secure deletion from keychain

### API Key Validation

**Validation Process:**
1. API key sent with device ID, SDK version, platform info
2. Server validates and returns JWT tokens
3. Access token used for subsequent API calls
4. Refresh token stored for future authentication

### Security Measures

**Device Identity:**
- **Persistent Device UUID**: Generated and stored in keychain
- **Device Fingerprint**: SHA-256 hash of device characteristics
- **Hardware Binding**: Device-specific authentication

**Error Handling:**
- Structured error types with recovery suggestions
- Secure logging (no sensitive data in logs)
- Keychain operation error handling

## KMP Implementation

### Common Implementation

The KMP SDK provides a platform-agnostic authentication service with iOS-compatible API:

**Architecture:**
- **Thread Safety**: Mutex-based synchronization (replaces iOS actor pattern)
- **Storage Abstraction**: `SecureStorage` interface for platform-specific implementations
- **API Compatibility**: Method signatures match iOS implementation exactly

**File:** `/Users/sanchitmonga/development/ODLM/sdks.worktree/android_init/sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/services/AuthenticationService.kt`

```kotlin
class AuthenticationService(
    private val secureStorage: SecureStorage,
    private val httpClient: HttpClient
) {
    private val mutex = Mutex() // Thread safety

    suspend fun authenticate(apiKey: String): AuthenticationResponse = mutex.withLock {
        // Identical logic to iOS implementation
    }

    suspend fun getAccessToken(): String = mutex.withLock {
        // Token validation with same 1-minute buffer
    }
}
```

### Credential Management

**Storage Keys**: Identical to iOS implementation for consistency
```kotlin
companion object {
    private const val KEY_ACCESS_TOKEN = "com.runanywhere.sdk.accessToken"
    private const val KEY_REFRESH_TOKEN = "com.runanywhere.sdk.refreshToken"
    private const val KEY_TOKEN_EXPIRES_AT = "com.runanywhere.sdk.tokenExpiresAt"
    // ... more keys matching iOS
}
```

**Storage Interface:**
```kotlin
interface SecureStorage {
    suspend fun setSecureString(key: String, value: String)
    suspend fun getSecureString(key: String): String?
    suspend fun removeSecure(key: String)
    suspend fun containsSecure(key: String): Boolean
    suspend fun clearSecure()
}
```

## Platform-Specific Implementations

### Android

**Implementation:** `AndroidSecureStorage` using `EncryptedSharedPreferences`

**Security Features:**
- **Master Key**: AES256_GCM key scheme
- **Key Encryption**: AES256_SIV scheme
- **Value Encryption**: AES256_GCM scheme
- **Storage**: Encrypted shared preferences file
- **Integration**: Android Jetpack Security library

**File:** `/Users/sanchitmonga/development/ODLM/sdks.worktree/android_init/sdk/runanywhere-kotlin/src/androidMain/kotlin/com/runanywhere/sdk/storage/AndroidSecureStorage.kt`

```kotlin
internal class AndroidSecureStorage(context: Context) : SecureStorage {
    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val sharedPreferences = EncryptedSharedPreferences.create(
        context,
        "runanywhere_secure_prefs",
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )
}
```

**Android Keystore Integration:**
- Uses Android Keystore for master key generation
- Hardware-backed security when available
- Fallback to software-based encryption

### JVM

**Implementation:** `JvmSecureStorage` using encrypted properties file

**Security Approach:**
- **Storage Location**: `~/.runanywhere/secure.properties`
- **Key Storage**: `~/.runanywhere/key.dat`
- **Encryption**: AES-256 encryption
- **Key Generation**: Random key generation with persistent storage

**File:** `/Users/sanchitmonga/development/ODLM/sdks.worktree/android_init/sdk/runanywhere-kotlin/src/jvmMain/kotlin/com/runanywhere/sdk/storage/JvmSecureStorage.kt`

```kotlin
internal class JvmSecureStorage : SecureStorage {
    private val storageFile = File(System.getProperty("user.home"), ".runanywhere/secure.properties")
    private val keyFile = File(System.getProperty("user.home"), ".runanywhere/key.dat")
    private val secretKey: SecretKey by lazy { getOrCreateKey() }

    private fun encrypt(value: String): String {
        val cipher = Cipher.getInstance("AES")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey)
        val encrypted = cipher.doFinal(value.toByteArray())
        return Base64.getEncoder().encodeToString(encrypted)
    }
}
```

## Gaps and Misalignments

### Critical Security Gaps

#### 1. **Token Refresh Implementation Missing**
- **iOS**: Refresh logic exists but not implemented (`TODO` comments)
- **KMP**: Same placeholder implementation
- **Impact**: Tokens cannot be refreshed, requiring full re-authentication
- **Risk Level**: HIGH

#### 2. **JVM Secure Storage Vulnerabilities**
**File Permissions:**
- Storage files created with default permissions (potentially world-readable)
- Key file stored in plain filesystem without additional protection
- No file system permission validation

**Key Management:**
- Single AES key stored in filesystem
- No key rotation mechanism
- No secure key derivation (should use PBKDF2/Scrypt)

#### 3. **Missing Biometric Authentication**
- **iOS**: No biometric authentication integration (Touch ID/Face ID)
- **Android**: No biometric prompt integration
- **Opportunity**: Enhanced security for sensitive operations

#### 4. **Network Security**
**Certificate Pinning:**
- No SSL certificate pinning implemented
- Vulnerable to man-in-the-middle attacks
- No custom trust store configuration

**TLS Configuration:**
- Default TLS settings used
- No minimum TLS version enforcement
- No cipher suite restrictions

### Storage Security Comparison

| Platform | Security Mechanism | Encryption | Key Management | Hardware Backing |
|----------|-------------------|------------|----------------|------------------|
| **iOS** | iOS Keychain | Hardware/Software | OS-managed | Yes (Secure Enclave) |
| **Android** | EncryptedSharedPrefs | AES256-GCM | Android Keystore | Yes (when available) |
| **JVM** | File-based | AES256 | Filesystem | No |

### Feature Disparities

#### 1. **Device Identity**
- **iOS**: Comprehensive device fingerprinting with hardware characteristics
- **KMP**: Basic device ID implementation
- **Gap**: Less robust device binding in KMP

#### 2. **Error Handling**
- **iOS**: Rich error types with localized messages
- **KMP**: Basic error handling with recovery suggestions
- **Alignment**: Good, but could be enhanced

#### 3. **Logging Security**
- **Both**: Proper sensitive data filtering
- **Consistency**: Good alignment

## Recommendations to Address Gaps

### Immediate Actions (Critical)

#### 1. **Implement Token Refresh Mechanism**
```kotlin
// Priority: CRITICAL
// Timeline: 1 week

suspend fun refreshAccessToken(): String {
    val refreshRequest = RefreshTokenRequest(
        refreshToken = currentRefreshToken,
        grantType = "refresh_token"
    )

    val response = httpClient.post(
        url = "${baseUrl}/v1/auth/refresh",
        body = json.encodeToString(refreshRequest)
    )

    // Update stored tokens
    storeTokensInSecureStorage(response)
    return response.accessToken
}
```

#### 2. **Secure JVM Storage Implementation**
```kotlin
// Priority: CRITICAL
// Timeline: 1 week

class JvmSecureStorage : SecureStorage {
    private fun createSecureKeyFile(): SecretKey {
        // Use PBKDF2 for key derivation
        val salt = generateRandomSalt()
        val password = getOrPromptPassword() // From environment or prompt

        val keySpec = PBEKeySpec(password, salt, 100000, 256)
        val factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
        return SecretKeySpec(factory.generateSecret(keySpec).encoded, "AES")
    }

    private fun secureFilePermissions() {
        // Set restrictive file permissions (owner only)
        Files.setPosixFilePermissions(storageFile.toPath(),
            setOf(PosixFilePermission.OWNER_READ, PosixFilePermission.OWNER_WRITE))
    }
}
```

### Short-term Improvements

#### 3. **Implement Certificate Pinning**
```swift
// iOS Implementation
class APIClient {
    private let pinnedCertificates: [SecCertificate] = loadPinnedCertificates()

    func setupCertificatePinning() {
        // Implement certificate validation
    }
}
```

```kotlin
// KMP Implementation
expect class CertificatePinner {
    fun addPin(hostname: String, certificate: ByteArray)
    fun validateCertificate(hostname: String, certificates: List<ByteArray>): Boolean
}
```

#### 4. **Add Biometric Authentication**
```kotlin
// Android Implementation
class BiometricAuthenticationService {
    suspend fun authenticateWithBiometric(): Boolean {
        return suspendCancellableCoroutine { continuation ->
            val biometricPrompt = BiometricPrompt.Builder(context)
                .setTitle("RunAnywhere Authentication")
                .setSubtitle("Use biometric to authenticate")
                .setNegativeButton("Cancel", executor) { _, _ ->
                    continuation.resume(false)
                }
                .build()

            biometricPrompt.authenticate(cryptoObject, cancellationSignal, executor, callback)
        }
    }
}
```

### Long-term Enhancements

#### 5. **Hardware Security Module Integration**
- **iOS**: Utilize Secure Enclave for key generation and storage
- **Android**: Leverage StrongBox Keymaster when available
- **JVM**: Integrate with PKCS#11 for HSM support

#### 6. **Advanced Threat Detection**
```kotlin
class SecurityMonitor {
    fun detectRootedDevice(): Boolean
    fun detectDebugging(): Boolean
    fun detectEmulator(): Boolean
    fun validateAppIntegrity(): Boolean
}
```

#### 7. **Multi-Factor Authentication**
```kotlin
interface MFAProvider {
    suspend fun sendOTP(phoneNumber: String): Boolean
    suspend fun verifyOTP(code: String): Boolean
    suspend fun generateTOTP(secret: String): String
}
```

## Security Best Practices Analysis

### Current Implementations

#### ✅ **Well Implemented**
- Thread-safe authentication services
- Proper token lifecycle management
- Platform-appropriate secure storage
- Device identity binding
- Structured error handling
- Sensitive data logging protection

#### ⚠️ **Partially Implemented**
- Encryption at rest (good on iOS/Android, weak on JVM)
- Network security (basic HTTPS, no pinning)
- Token management (storage good, refresh missing)

#### ❌ **Missing**
- Biometric authentication
- Certificate pinning
- Hardware security module integration
- Token refresh mechanism
- Advanced threat detection

### Security Maturity Assessment

| Security Domain | iOS | Android | JVM | Overall |
|----------------|-----|---------|-----|---------|
| **Credential Storage** | 🟢 Excellent | 🟢 Excellent | 🟡 Needs Work | 🟡 Good |
| **Authentication Flow** | 🟢 Excellent | 🟢 Excellent | 🟢 Excellent | 🟢 Excellent |
| **Token Management** | 🟡 Good | 🟡 Good | 🟡 Good | 🟡 Good |
| **Network Security** | 🟡 Basic | 🟡 Basic | 🟡 Basic | 🟡 Basic |
| **Device Binding** | 🟢 Excellent | 🟢 Good | 🟡 Basic | 🟡 Good |
| **Threat Detection** | 🔴 Missing | 🔴 Missing | 🔴 Missing | 🔴 Missing |

### Recommended Security Architecture

```
┌─────────────────────────────────────────────┐
│                Application                  │
├─────────────────────────────────────────────┤
│          Authentication Service             │
│  ┌─────────────┐ ┌─────────────┐           │
│  │   Token     │ │  Biometric  │           │
│  │  Manager    │ │   Auth      │           │
│  └─────────────┘ └─────────────┘           │
├─────────────────────────────────────────────┤
│            Secure Storage Layer             │
│  ┌─────────────┐ ┌─────────────┐           │
│  │  Keychain   │ │   Android   │           │
│  │   (iOS)     │ │  Keystore   │           │
│  └─────────────┘ └─────────────┘           │
├─────────────────────────────────────────────┤
│            Network Security                 │
│  ┌─────────────┐ ┌─────────────┐           │
│  │Certificate  │ │     TLS     │           │
│  │  Pinning    │ │ 1.3 + HSTS  │           │
│  └─────────────┘ └─────────────┘           │
├─────────────────────────────────────────────┤
│            Threat Detection                 │
│  ┌─────────────┐ ┌─────────────┐           │
│  │   Device    │ │    App      │           │
│  │  Integrity  │ │  Integrity  │           │
│  └─────────────┘ └─────────────┘           │
└─────────────────────────────────────────────┘
```

## Conclusion

The authentication and security implementations show strong architectural alignment between iOS and KMP platforms, with the KMP implementation successfully maintaining API compatibility with iOS while providing appropriate platform-specific security mechanisms.

**Key Strengths:**
- Consistent authentication flow across platforms
- Proper use of platform security features (Keychain, Android Keystore)
- Thread-safe implementations
- Good error handling and logging practices

**Critical Issues:**
- Missing token refresh implementation across all platforms
- Vulnerable JVM secure storage implementation
- Lack of advanced security features (biometric auth, certificate pinning)

**Priority Actions:**
1. **Immediate**: Implement token refresh mechanism
2. **Immediate**: Secure JVM storage with proper key management
3. **Short-term**: Add certificate pinning and biometric authentication
4. **Long-term**: Implement comprehensive threat detection and HSM integration

The security foundation is solid, but these improvements are essential for production deployment, particularly in enterprise environments requiring enhanced security posture.
