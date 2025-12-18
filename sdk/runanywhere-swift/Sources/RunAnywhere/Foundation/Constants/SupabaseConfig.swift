//
//  SupabaseConfig.swift
//  RunAnywhere SDK
//
//  Supabase configuration for development device analytics
//  Internal - automatically configured based on environment
//

import Foundation

/// Supabase configuration for development device analytics
/// Internal - automatically configured based on environment
internal struct SupabaseConfig: Sendable {
    /// Supabase project URL
    let projectURL: URL

    /// Supabase anon/public API key (safe to expose in client apps)
    let anonKey: String

    /// Get Supabase configuration for the given environment
    /// - Parameter environment: The SDK environment
    /// - Returns: Supabase configuration if applicable for this environment
    static func configuration(for environment: SDKEnvironment) -> SupabaseConfig? {
        switch environment {
        case .development:
            // Development mode: Use RunAnywhere's public Supabase for dev analytics
            // Note: Anon key is safe to include in client code - data access is controlled by RLS policies
            guard let projectURL = URL(string: "https://fhtgjtxuoikwwouxqzrn.supabase.co") else {
                // This should never fail for a valid hardcoded URL, but we handle it safely
                assertionFailure("Invalid Supabase project URL configuration")
                return nil
            }
            // swiftlint:disable:next line_length
            let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZodGdqdHh1b2lrd3dvdXhxenJuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjExOTkwNzIsImV4cCI6MjA3Njc3NTA3Mn0.aIssX-t8CIqt8zoctNhMS8fm3wtH-DzsQiy9FunqD9E"
            return SupabaseConfig(projectURL: projectURL, anonKey: anonKey)
        case .staging, .production:
            // Production/Staging: No Supabase, use traditional backend
            return nil
        }
    }
}
