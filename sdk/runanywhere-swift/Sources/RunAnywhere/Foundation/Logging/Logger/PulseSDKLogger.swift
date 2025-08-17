//
//  PulseSDKLogger.swift
//  RunAnywhere SDK
//
//  Pulse-based logging implementation
//

import Foundation
import Pulse
import os

/// Pulse-based SDK logger implementation
internal final class PulseSDKLogger {

    // MARK: - Properties

    private let category: String
    private let pulseLogger: LoggerStore

    // MARK: - Initialization

    init(category: String) {
        self.category = category
        self.pulseLogger = LoggerStore.shared
    }

    // MARK: - Logging Methods

    /// Log a debug message
    func debug(_ message: String, metadata: [String: Any]? = nil) {
        log(level: .debug, message: message, metadata: metadata)
    }

    /// Log an info message
    func info(_ message: String, metadata: [String: Any]? = nil) {
        log(level: .info, message: message, metadata: metadata)
    }

    /// Log a warning message
    func warning(_ message: String, metadata: [String: Any]? = nil) {
        log(level: .warning, message: message, metadata: metadata)
    }

    /// Log an error message
    func error(_ message: String, metadata: [String: Any]? = nil) {
        log(level: .error, message: message, metadata: metadata)
    }

    /// Log a fault message
    func fault(_ message: String, metadata: [String: Any]? = nil) {
        log(level: .fault, message: message, metadata: metadata)
    }

    /// Log a message with a specific level
    func log(level: LogLevel, _ message: String, metadata: [String: Any]? = nil) {
        log(level: level, message: message, error: nil, metadata: metadata)
    }

    /// Log a message with error and metadata
    func log(level: LogLevel, message: String, error: Error? = nil, metadata: [String: Any]? = nil) {
        var pulseMetadata: [String: LoggerStore.MetadataValue] = [:]

        // Add category
        pulseMetadata["category"] = .string(category)

        // Convert metadata to Pulse format
        if let metadata = metadata {
            for (key, value) in metadata {
                pulseMetadata[key] = convertToMetadataValue(value)
            }
        }

        // Add error information
        if let error = error {
            pulseMetadata["error"] = .string(error.localizedDescription)
            pulseMetadata["errorType"] = .string(String(describing: type(of: error)))

            // Add underlying error if available
            if let nsError = error as NSError? {
                pulseMetadata["errorCode"] = .string(String(nsError.code))
                pulseMetadata["errorDomain"] = .string(nsError.domain)

                if !nsError.userInfo.isEmpty {
                    var userInfoDict: [String: LoggerStore.MetadataValue] = [:]
                    for (key, value) in nsError.userInfo {
                        if let stringValue = value as? String {
                            userInfoDict[key] = .string(stringValue)
                        }
                    }
                    if !userInfoDict.isEmpty {
                        pulseMetadata["errorUserInfo"] = .stringConvertible(userInfoDict)
                    }
                }
            }
        }

        // Convert LogLevel to Pulse level
        let pulseLevel: LoggerStore.Level = {
            switch level {
            case .debug: return .debug
            case .info: return .info
            case .warning: return .warning
            case .error: return .error
            case .fault: return .critical
            }
        }()

        // Log to Pulse
        pulseLogger.storeMessage(
            label: category,
            level: pulseLevel,
            message: message,
            metadata: pulseMetadata.isEmpty ? nil : pulseMetadata
        )

        // Also send to LoggingManager for remote logging (if enabled)
        LoggingManager.shared.log(
            level: level,
            category: category,
            message: message,
            metadata: metadata
        )
    }

    // MARK: - Generation Logging

    /// Log generation start
    func logGenerationStart(_ options: RunAnywhereGenerationOptions, metadata: [String: Any]? = nil) {
        var enrichedMetadata = metadata ?? [:]
        enrichedMetadata["generationOptions"] = [
            "maxTokens": options.maxTokens,
            "temperature": options.temperature,
            // systemPrompt not available in RunAnywhereGenerationOptions
            "tokenBudget": options.tokenBudget?.maxTokens ?? 0
        ]
        enrichedMetadata["event"] = "generation_start"

        log(level: .info, message: "Generation started", metadata: enrichedMetadata)
    }

    /// Log generation completion
    func logGenerationComplete(_ result: GenerationResult, metadata: [String: Any]? = nil) {
        var enrichedMetadata = metadata ?? [:]
        enrichedMetadata["generationResult"] = [
            "executionTarget": result.executionTarget.rawValue,
            "tokensUsed": result.tokensUsed,
            "savedAmount": result.savedAmount,
            "modelUsed": result.modelUsed,
            "latencyMs": result.latencyMs,
            "memoryUsed": result.memoryUsed,
            "framework": result.framework?.rawValue ?? "none"
        ]
        enrichedMetadata["event"] = "generation_complete"

        log(level: .info, message: "Generation completed", metadata: enrichedMetadata)
    }

    // MARK: - Private Helpers

    private func convertToMetadataValue(_ value: Any) -> LoggerStore.MetadataValue {
        switch value {
        case let string as String:
            return .string(string)
        case let int as Int:
            return .string(String(int))
        case let double as Double:
            return .string(String(double))
        case let bool as Bool:
            return .string(String(bool))
        case let url as URL:
            return .string(url.absoluteString)
        case let data as Data:
            return .string(data.base64EncodedString())
        case let array as [Any]:
            let stringArray = array.map { String(describing: $0) }
            return .stringConvertible(stringArray)
        case let dict as [String: Any]:
            var convertedDict: [String: String] = [:]
            for (key, value) in dict {
                convertedDict[key] = String(describing: value)
            }
            return .stringConvertible(convertedDict)
        default:
            return .string(String(describing: value))
        }
    }
}
