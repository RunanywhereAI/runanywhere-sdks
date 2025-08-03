import Foundation

/// GGUF/llama.cpp specific options for text generation
public struct GGUFOptions {
    /// Number of layers to offload to GPU
    public let gpuLayers: Int

    /// Use memory mapping
    public let useMemoryMap: Bool

    /// Batch size
    public let batchSize: Int

    /// Initialize GGUF options
    /// - Parameters:
    ///   - gpuLayers: Number of layers to offload to GPU (default: 0)
    ///   - useMemoryMap: Use memory mapping (default: true)
    ///   - batchSize: Batch size (default: 8)
    public init(
        gpuLayers: Int = 0,
        useMemoryMap: Bool = true,
        batchSize: Int = 8
    ) {
        self.gpuLayers = gpuLayers
        self.useMemoryMap = useMemoryMap
        self.batchSize = batchSize
    }
}
