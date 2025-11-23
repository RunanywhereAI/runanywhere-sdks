import Foundation

/// Build token for development mode device registration
///
/// ⚠️ THIS FILE IS FOR LOCAL DEVELOPMENT ONLY
/// ⚠️ DO NOT COMMIT THIS FILE TO GIT
///
/// Generated: Local development build
/// Purpose: Debug/development token for testing
///
/// Security Model:
/// - This file is in .gitignore (not committed to main branch)
/// - Real tokens are ONLY in release tags (for SPM distribution)
/// - Token is used ONLY when SDK is in .development mode
/// - Backend validates token via POST /api/v1/devices/register/dev
///
/// Token Properties:
/// - Format: Simple debug token for local testing
/// - This is NOT a production token
/// - For development/testing purposes only
enum BuildToken {
    /// Development mode build token
    /// Generated for: Local development and testing
    static let token = "runanywhere_debug_token"
}
