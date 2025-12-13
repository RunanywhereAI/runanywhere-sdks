import Foundation

/// Protocol for modules that can auto-register themselves
/// External modules can implement this to self-register with ModuleRegistry
///
/// Example:
/// ```swift
/// public struct WhisperModule: AutoRegisteringModule {
///     public static func register() {
///         ModuleRegistry.shared.registerSTT(WhisperSTTProvider())
///     }
/// }
/// ```
public protocol AutoRegisteringModule {
    static func register()
}
