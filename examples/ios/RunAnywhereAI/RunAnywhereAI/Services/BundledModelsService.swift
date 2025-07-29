import Foundation

// MARK: - Bundled Models Service

class BundledModelsService {
    static let shared = BundledModelsService()

    private init() {}

    // Pre-defined sample models that come with the app
    var bundledModels: [ModelInfo] {
        var models: [ModelInfo] = []
        
        // DISABLED: OpenELM models are now downloaded dynamically from HuggingFace
        // This reduces app size and allows for model updates without app updates
        /*
        // Check if OpenELM model exists in bundle
        if let openELMPath = Bundle.main.path(forResource: "OpenELM-270M-Instruct-128-float32", ofType: "mlpackage") {
            models.append(ModelInfo(
                id: "openelm-270m-bundled-st",
                name: "OpenELM-270M-Instruct-128-float32",
                path: openELMPath,
                format: .mlPackage,
                size: "540 MB",
                framework: .swiftTransformers,
                quantization: "Float32",
                contextLength: 2048,
                isLocal: true,
                description: "Apple's OpenELM 270M instruction-tuned model optimized for on-device inference"
            ))
        }
        */
        
        // Add more bundled models here as needed
        
        return models
    }

    // Copy bundled models to app's documents directory
    func installBundledModels() async throws {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelsDirectory = documentsURL.appendingPathComponent("Models")

        // Create models directory if it doesn't exist
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        for model in bundledModels where model.isLocal {
            // Create framework-specific directory
            let frameworkDir = modelsDirectory.appendingPathComponent(model.framework.directoryName)
            try FileManager.default.createDirectory(at: frameworkDir, withIntermediateDirectories: true)
            
            // Determine the resource name and extension
            let resourceName: String
            let resourceExtension: String
            
            // For .mlpackage models, remove the extension from the name for resource lookup
            if model.format == .mlPackage && model.name.hasSuffix(".mlpackage") {
                resourceName = String(model.name.dropLast(10)) // Remove ".mlpackage"
                resourceExtension = "mlpackage"
            } else {
                // For other formats, use the model ID
                resourceName = model.id
                resourceExtension = model.format.fileExtension
            }
            
            // Check if the model exists in the app bundle
            if let bundleURL = Bundle.main.url(forResource: resourceName, withExtension: resourceExtension) {
                let destinationURL = frameworkDir.appendingPathComponent(model.name)
                
                // Skip if already installed
                if !FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.copyItem(at: bundleURL, to: destinationURL)
                    print("Copied bundled model '\(model.name)' to: \(destinationURL.path)")
                    
                    // Update model path
                    await ModelManager.shared.updateModelPath(modelId: model.id, path: destinationURL.path)
                } else {
                    print("Model '\(model.name)' already installed at: \(destinationURL.path)")
                }
            } else {
                // For bundled models, check if they exist in the Models directory
                let modelsDir = Bundle.main.bundleURL.appendingPathComponent("Models")
                let modelPath = modelsDir.appendingPathComponent(model.name)
                
                if FileManager.default.fileExists(atPath: modelPath.path) {
                    print("Found bundled model at: \(modelPath.path)")
                    // Model is already bundled, no need to copy
                    // Just update the model info with the bundle path
                    var updatedModel = model
                    updatedModel.path = modelPath.path
                    // Note: We're not copying to Documents because the model can be used directly from the bundle
                } else {
                    print("Warning: Bundled model '\(resourceName).\(resourceExtension)' not found in app bundle")
                    print("Searched paths:")
                    print("  - Resource: \(resourceName).\(resourceExtension)")
                    print("  - Models dir: \(modelPath.path)")
                }
            }
        }
    }

    // Install bundled models to Documents directory if needed
    func installBundledModelsToDocuments() async throws {
        // This method can be used if you need to copy bundled models to Documents
        // Currently not needed as we use models directly from the bundle
    }
}

// MARK: - Model Info Extensions

extension ModelInfo {
    init(id: String, name: String, format: ModelFormat, size: String,
         framework: LLMFramework, quantization: String? = nil, contextLength: Int? = nil,
         isLocal: Bool = false, downloadURL: URL? = nil, description: String? = nil,
         minimumMemory: Int64 = 2_000_000_000,
         recommendedMemory: Int64 = 4_000_000_000) {
        self.id = id
        self.name = name
        self.path = nil
        self.format = format
        self.size = size
        self.framework = framework
        self.quantization = quantization
        self.contextLength = contextLength
        self.isLocal = isLocal
        self.downloadURL = downloadURL
        self.downloadedFileName = nil
        self.modelType = .text
        self.sha256 = nil
        self.requiresUnzip = false
        self.requiresAuth = false
        self.authType = .none
        self.alternativeURLs = []
        self.notes = nil
        self.description = description ?? ""
        self.minimumMemory = minimumMemory
        self.recommendedMemory = recommendedMemory
    }
}

// MARK: - Model Format Extensions
