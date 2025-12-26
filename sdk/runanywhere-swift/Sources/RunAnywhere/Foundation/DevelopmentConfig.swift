//
//  DevelopmentConfig.swift
//  RunAnywhere SDK
//
//  Configuration values for development mode.
//  This file contains placeholder values for building.
//  Real values are injected during release builds.
//
//  NOTE: This file should be in .gitignore for production releases
//  with actual credentials.
//

import Foundation

/// Development configuration with placeholder values
/// Replace with real values for development/testing
public enum DevelopmentConfig {
    /// Supabase project URL
    public static let supabaseURL = "https://placeholder.supabase.co"

    /// Supabase anonymous key
    public static let supabaseAnonKey = "placeholder_anon_key"

    /// Build token for SDK validation
    public static let buildToken = "placeholder_build_token"

    /// Sentry DSN for crash reporting (optional)
    public static let sentryDSN = "placeholder_sentry_dsn"
}
