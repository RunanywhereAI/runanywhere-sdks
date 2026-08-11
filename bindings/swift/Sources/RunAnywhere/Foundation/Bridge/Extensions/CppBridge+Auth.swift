//
//  CppBridge+Auth.swift
//  RunAnywhere SDK
//
//  Authentication bridge extension for C++ interop.
//

import CRACommons

// MARK: - Auth State Bridge

extension CppBridge {

    /// Auth state bridge. Network auth/refresh orchestration is driven by
    /// `CppBridge.SdkInit.phase2()` / `retryHTTP()` in commons.
    public enum Auth {

        private static let logger = SDKLogger(category: "CppBridge.Auth")

        /// Clear authentication state (in-memory + Keychain)
        ///
        /// Delegates to rac_auth_clear which wipes the in-memory auth state
        /// and (because CppBridge.State.initialize wired up the Keychain
        /// secure-storage vtable) also deletes the persisted tokens.
        public static func clearAuth() throws {
            try SDKException.throwIfError(rac_auth_clear())
            logger.info("Authentication cleared")
        }

        /// Check if currently authenticated
        public static var isAuthenticated: Bool {
            rac_auth_is_authenticated()
        }
    }
}
