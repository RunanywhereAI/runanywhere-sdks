import Foundation

/// Container for framework-specific options
public struct FrameworkOptions {
    /// Core ML specific options
    public let coreMLOptions: CoreMLOptions?

    /// TensorFlow Lite specific options
    public let tfliteOptions: TFLiteOptions?

    /// MLX specific options
    public let mlxOptions: MLXOptions?

    /// GGUF/llama.cpp specific options
    public let ggufOptions: GGUFOptions?

    /// Initialize framework options
    /// - Parameters:
    ///   - coreMLOptions: Core ML specific options
    ///   - tfliteOptions: TensorFlow Lite specific options
    ///   - mlxOptions: MLX specific options
    ///   - ggufOptions: GGUF specific options
    public init(
        coreMLOptions: CoreMLOptions? = nil,
        tfliteOptions: TFLiteOptions? = nil,
        mlxOptions: MLXOptions? = nil,
        ggufOptions: GGUFOptions? = nil
    ) {
        self.coreMLOptions = coreMLOptions
        self.tfliteOptions = tfliteOptions
        self.mlxOptions = mlxOptions
        self.ggufOptions = ggufOptions
    }
}
