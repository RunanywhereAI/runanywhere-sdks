//
//  LLMService+Logging.swift
//  RunAnywhereAI
//
//  Created on 7/26/25.
//

import Foundation

// MARK: - LLM Service Logging Extension

extension LLMService {
    
    /// Get framework from service name
    var framework: LLMFramework? {
        switch name.lowercased() {
        case "foundation models":
            return .foundationModels
        case "core ml", "coreml":
            return .coreML
        case "mlx":
            return .mlx
        case "mlc", "mlc-llm":
            return .mlc
        case "onnx", "onnx runtime":
            return .onnxRuntime
        case "executorch":
            return .execuTorch
        case "llama.cpp", "llamacpp":
            return .llamaCpp
        case "tensorflow lite", "tflite", "litert":
            return .tensorFlowLite
        case "picollm":
            return .picoLLM
        case "swift transformers":
            return .swiftTransformers
        case "mock":
            return .mock
        default:
            return nil
        }
    }
    
    /// Log a message for this service
    func log(
        _ message: String,
        level: LogLevel = .info,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        if let framework = framework {
            Logger.shared.logFramework(
                framework,
                message,
                level: level,
                file: file,
                function: function,
                line: line
            )
        } else {
            Logger.shared.log(
                message,
                level: level,
                category: name,
                file: file,
                function: function,
                line: line
            )
        }
    }
    
    /// Log verbose message
    func logVerbose(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .verbose, file: file, function: function, line: line)
    }
    
    /// Log debug message
    func logDebug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, file: file, function: function, line: line)
    }
    
    /// Log info message
    func logInfo(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }
    
    /// Log warning message
    func logWarning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, file: file, function: function, line: line)
    }
    
    /// Log error message
    func logError(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, file: file, function: function, line: line)
    }
    
    /// Log critical message
    func logCritical(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .critical, file: file, function: function, line: line)
    }
    
    /// Log an error with context
    func logError(
        _ error: Error,
        additionalInfo: [String: Any]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        Logger.shared.logError(
            error,
            framework: framework,
            additionalInfo: additionalInfo,
            file: file,
            function: function,
            line: line
        )
    }
    
    /// Log performance metric
    func logPerformance(
        _ metric: String,
        value: Double,
        unit: String = "ms",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        Logger.shared.logPerformance(
            metric,
            value: value,
            unit: unit,
            framework: framework,
            file: file,
            function: function,
            line: line
        )
    }
    
    /// Start performance tracking
    func startTracking(_ operation: String) -> PerformanceTracker {
        Logger.shared.startPerformanceTracking("\(name): \(operation)")
    }
}

// MARK: - Structured Logging

extension LLMService {
    
    /// Log model loading event
    func logModelLoading(path: String, format: ModelFormat) {
        logInfo("Loading model: \(path) (format: \(format.rawValue))")
    }
    
    /// Log model loaded event
    func logModelLoaded(info: ModelInfo, duration: TimeInterval) {
        logInfo("Model loaded: \(info.name) in \(String(format: "%.2f", duration))s")
        logPerformance("Model loading", value: duration * 1000)
    }
    
    /// Log generation start
    func logGenerationStart(promptLength: Int, options: GenerationOptions) {
        logDebug("Starting generation: prompt_length=\(promptLength), max_tokens=\(options.maxTokens), temperature=\(options.temperature)")
    }
    
    /// Log generation complete
    func logGenerationComplete(tokensGenerated: Int, duration: TimeInterval, tokensPerSecond: Double) {
        logInfo("Generation complete: \(tokensGenerated) tokens in \(String(format: "%.2f", duration))s (\(String(format: "%.1f", tokensPerSecond)) tokens/s)")
        logPerformance("Generation", value: duration * 1000)
        logPerformance("Tokens per second", value: tokensPerSecond, unit: "tokens/s")
    }
    
    /// Log memory usage
    func logMemoryUsage(_ stats: MemoryStats) {
        logDebug("Memory usage: \(stats.formattedTotal) (model: \(ByteCountFormatter.string(fromByteCount: stats.modelMemory, countStyle: .memory)), context: \(ByteCountFormatter.string(fromByteCount: stats.contextMemory, countStyle: .memory)))")
        
        if stats.memoryPressure != .normal {
            logWarning("Memory pressure: \(stats.memoryPressure.rawValue)")
        }
    }
    
    /// Log configuration applied
    func logConfiguration(_ config: [String: Any]) {
        logDebug("Configuration applied: \(config)")
    }
    
    /// Log health check result
    func logHealthCheck(_ result: HealthCheckResult) {
        if result.isHealthy {
            logInfo("Health check passed: framework=\(result.frameworkVersion), model_loaded=\(result.modelLoaded)")
        } else {
            logWarning("Health check failed: \(result.lastError?.localizedDescription ?? "Unknown error")")
        }
    }
}

// MARK: - Logging Utilities

/// Structured log context
struct LogContext {
    let framework: LLMFramework
    let operation: String
    let parameters: [String: Any]
    
    func log(_ message: String, level: LogLevel = .info) {
        var fullMessage = "[\(operation)] \(message)"
        if !parameters.isEmpty {
            fullMessage += " | \(parameters)"
        }
        Logger.shared.logFramework(framework, fullMessage, level: level)
    }
}