
// MARK: TensorFlow Lite Models (Updated from test results)
private var _tfliteModels: [ModelInfo] = [
    // ✅ Official Google AI Edge samples - Direct download, no auth
    ModelInfo(
        id: "bert-classifier-tflite",
        name: "bert_classifier.tflite",
        path: nil,
        format: .tflite,
        size: "100MB",
        framework: .tensorFlowLite,
        quantization: "FP32",
        contextLength: 512,
        isLocal: false,
        downloadURL: URL(string: "https://storage.googleapis.com/ai-edge/interpreter-samples/text_classification/ios/bert_classifier.tflite"),
        downloadedFileName: "bert_classifier.tflite",
        modelType: .text,
        sha256: nil,
        requiresUnzip: false,
        requiresAuth: false,
        authType: .none,
        alternativeURLs: [],
        notes: "BERT model for text classification from official Google AI Edge samples",
        description: "Official BERT classifier model optimized for mobile text classification tasks",
        minimumMemory: 200_000_000,
        recommendedMemory: 400_000_000,
        additionalFiles: [
            ModelFile(
                name: "bert_vocab.txt",
                url: URL(string: "https://raw.githubusercontent.com/google-ai-edge/interpreter-samples/main/examples/text_classification/ios/TextClassification/bert_vocab.txt")!,
                type: .vocabulary,
                required: true
            )
        ]
    ),
    
    ModelInfo(
        id: "average-word-classifier-tflite", 
        name: "average_word_classifier.tflite",
        path: nil,
        format: .tflite,
        size: "25MB",
        framework: .tensorFlowLite,
        quantization: "FP32",
        contextLength: 256,
        isLocal: false,
        downloadURL: URL(string: "https://storage.googleapis.com/ai-edge/interpreter-samples/text_classification/ios/average_word_classifier.tflite"),
        downloadedFileName: "average_word_classifier.tflite",
        modelType: .text,
        sha256: nil,
        requiresUnzip: false,
        requiresAuth: false,
        authType: .none,
        alternativeURLs: [],
        notes: "Average word classifier from official Google AI Edge samples",
        description: "Lightweight text classifier using average word embeddings",
        minimumMemory: 50_000_000,
        recommendedMemory: 100_000_000,
        additionalFiles: [
            ModelFile(
                name: "average_vocab.txt",
                url: URL(string: "https://raw.githubusercontent.com/google-ai-edge/interpreter-samples/main/examples/text_classification/ios/TextClassification/average_vocab.txt")!,
                type: .vocabulary,
                required: true
            )
        ]
    ),
    
    // 🔒 Kaggle-hosted LLM models - Require authentication
    ModelInfo(
        id: "gemma-2b-int4-gpu-tflite",
        name: "gemma-2b-it-gpu-int4.tar.gz",
        path: nil,
        format: .tflite,
        size: "1.3GB",
        framework: .tensorFlowLite,
        quantization: "INT4",
        contextLength: 8192,
        isLocal: false,
        downloadURL: URL(string: "https://www.kaggle.com/models/google/gemma/tfLite/gemma-2b-it-gpu-int4/3/download"),
        downloadedFileName: "gemma-2b-it-gpu-int4.tar.gz",
        modelType: .text,
        sha256: nil,
        requiresUnzip: true,
        requiresAuth: true,
        authType: .kaggle,
        alternativeURLs: [],
        notes: "Requires Kaggle authentication. GPU-optimized with INT4 quantization for efficient mobile inference.",
        description: "Google Gemma 2B instruction-tuned model with GPU optimization and INT4 quantization",
        minimumMemory: 2_000_000_000,
        recommendedMemory: 3_000_000_000
    ),
    
    ModelInfo(
        id: "gemma-2b-int8-cpu-tflite",
        name: "gemma-2b-it-cpu-int8.tar.gz", 
        path: nil,
        format: .tflite,
        size: "1.7GB",
        framework: .tensorFlowLite,
        quantization: "INT8",
        contextLength: 8192,
        isLocal: false,
        downloadURL: URL(string: "https://www.kaggle.com/models/google/gemma/tfLite/gemma-2b-it-cpu-int8/3/download"),
        downloadedFileName: "gemma-2b-it-cpu-int8.tar.gz",
        modelType: .text,
        sha256: nil,
        requiresUnzip: true,
        requiresAuth: true,
        authType: .kaggle,
        alternativeURLs: [],
        notes: "Requires Kaggle authentication. CPU-optimized with INT8 quantization for better accuracy.",
        description: "Google Gemma 2B instruction-tuned model with CPU optimization and INT8 quantization",
        minimumMemory: 2_500_000_000,
        recommendedMemory: 4_000_000_000
    ),
    
    ModelInfo(
        id: "phi-2-int8-tflite",
        name: "phi-2-int8.tar.gz",
        path: nil,
        format: .tflite,
        size: "2.7GB",
        framework: .tensorFlowLite,
        quantization: "INT8", 
        contextLength: 2048,
        isLocal: false,
        downloadURL: URL(string: "https://www.kaggle.com/models/microsoft/phi/tfLite/phi-2-int8/1/download"),
        downloadedFileName: "phi-2-int8.tar.gz",
        modelType: .text,
        sha256: nil,
        requiresUnzip: true,
        requiresAuth: true,
        authType: .kaggle,
        alternativeURLs: [],
        notes: "Requires Kaggle authentication. Microsoft Phi-2 model optimized for mobile inference.",
        description: "Microsoft Phi-2 2.7B parameter model with INT8 quantization for mobile deployment",
        minimumMemory: 3_000_000_000,
        recommendedMemory: 4_000_000_000
    )
]
