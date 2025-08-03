import Foundation

/// MLX specific options for text generation
public struct MLXOptions {
    /// Use unified memory
    public let useUnifiedMemory: Bool

    /// Metal performance shaders
    public let useMPS: Bool

    /// Initialize MLX options
    /// - Parameters:
    ///   - useUnifiedMemory: Use unified memory (default: true)
    ///   - useMPS: Use Metal Performance Shaders (default: true)
    public init(
        useUnifiedMemory: Bool = true,
        useMPS: Bool = true
    ) {
        self.useUnifiedMemory = useUnifiedMemory
        self.useMPS = useMPS
    }
}
