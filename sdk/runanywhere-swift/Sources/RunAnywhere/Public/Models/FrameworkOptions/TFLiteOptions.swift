import Foundation

/// TensorFlow Lite specific options for text generation
public struct TFLiteOptions {
    /// Number of threads to use
    public let numThreads: Int

    /// Use GPU delegate
    public let useGPUDelegate: Bool

    /// Use Core ML delegate
    public let useCoreMLDelegate: Bool

    /// Initialize TensorFlow Lite options
    /// - Parameters:
    ///   - numThreads: Number of threads to use (default: 4)
    ///   - useGPUDelegate: Use GPU delegate (default: false)
    ///   - useCoreMLDelegate: Use Core ML delegate (default: true)
    public init(
        numThreads: Int = 4,
        useGPUDelegate: Bool = false,
        useCoreMLDelegate: Bool = true
    ) {
        self.numThreads = numThreads
        self.useGPUDelegate = useGPUDelegate
        self.useCoreMLDelegate = useCoreMLDelegate
    }
}
