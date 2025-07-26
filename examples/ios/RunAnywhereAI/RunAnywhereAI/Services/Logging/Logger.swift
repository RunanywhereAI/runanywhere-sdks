//
//  Logger.swift
//  RunAnywhereAI
//
//  Created on 7/26/25.
//

import Foundation
import os.log

/// Centralized logging system for LLM frameworks
final class Logger {
    static let shared = Logger()
    
    private let subsystem = Bundle.main.bundleIdentifier ?? "com.runanywhere.ai"
    private var loggers: [String: OSLog] = [:]
    private let queue = DispatchQueue(label: "com.runanywhere.logger", attributes: .concurrent)
    
    /// Log destinations
    private var destinations: [LogDestination] = [ConsoleLogDestination()]
    
    /// Current log level filter
    var minimumLogLevel: LogLevel = .info
    
    /// Enable performance logging
    var performanceLoggingEnabled = true
    
    private init() {
        setupDefaultLoggers()
    }
    
    // MARK: - Setup
    
    private func setupDefaultLoggers() {
        // Create loggers for each framework
        for framework in LLMFramework.allCases {
            let logger = OSLog(subsystem: subsystem, category: framework.rawValue)
            loggers[framework.rawValue] = logger
        }
        
        // System loggers
        loggers["system"] = OSLog(subsystem: subsystem, category: "system")
        loggers["performance"] = OSLog(subsystem: subsystem, category: "performance")
        loggers["memory"] = OSLog(subsystem: subsystem, category: "memory")
        loggers["network"] = OSLog(subsystem: subsystem, category: "network")
    }
    
    // MARK: - Logging Methods
    
    func log(
        _ message: String,
        level: LogLevel = .info,
        category: String = "system",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard level >= minimumLogLevel else { return }
        
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message,
            file: URL(fileURLWithPath: file).lastPathComponent,
            function: function,
            line: line
        )
        
        queue.async { [weak self] in
            self?.writeLog(entry)
        }
    }
    
    func logFramework(
        _ framework: LLMFramework,
        _ message: String,
        level: LogLevel = .info,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(
            message,
            level: level,
            category: framework.rawValue,
            file: file,
            function: function,
            line: line
        )
    }
    
    func logError(
        _ error: Error,
        framework: LLMFramework? = nil,
        additionalInfo: [String: Any]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        var message = "Error: \(error.localizedDescription)"
        
        if let info = additionalInfo {
            message += " | Info: \(info)"
        }
        
        let category = framework?.rawValue ?? "system"
        log(message, level: .error, category: category, file: file, function: function, line: line)
    }
    
    func logPerformance(
        _ metric: String,
        value: Double,
        unit: String = "ms",
        framework: LLMFramework? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard performanceLoggingEnabled else { return }
        
        let message = "\(metric): \(String(format: "%.2f", value)) \(unit)"
        let category = framework?.rawValue ?? "performance"
        
        log(message, level: .debug, category: category, file: file, function: function, line: line)
    }
    
    // MARK: - Log Writing
    
    private func writeLog(_ entry: LogEntry) {
        // Write to OSLog
        if let logger = loggers[entry.category] {
            let type: OSLogType
            switch entry.level {
            case .verbose, .debug:
                type = .debug
            case .info:
                type = .info
            case .warning:
                type = .default
            case .error:
                type = .error
            case .critical:
                type = .fault
            }
            
            os_log("%{public}@", log: logger, type: type, entry.formattedMessage)
        }
        
        // Write to additional destinations
        destinations.forEach { destination in
            destination.write(entry)
        }
    }
    
    // MARK: - Log Destinations
    
    func addDestination(_ destination: LogDestination) {
        queue.async(flags: .barrier) { [weak self] in
            self?.destinations.append(destination)
        }
    }
    
    func removeDestination(_ destination: LogDestination) {
        queue.async(flags: .barrier) { [weak self] in
            self?.destinations.removeAll { $0 === destination }
        }
    }
    
    // MARK: - Convenience Methods
    
    func verbose(_ message: String, category: String = "system", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .verbose, category: category, file: file, function: function, line: line)
    }
    
    func debug(_ message: String, category: String = "system", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, category: category, file: file, function: function, line: line)
    }
    
    func info(_ message: String, category: String = "system", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, category: category, file: file, function: function, line: line)
    }
    
    func warning(_ message: String, category: String = "system", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, category: category, file: file, function: function, line: line)
    }
    
    func error(_ message: String, category: String = "system", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, category: category, file: file, function: function, line: line)
    }
    
    func critical(_ message: String, category: String = "system", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .critical, category: category, file: file, function: function, line: line)
    }
}

// MARK: - Log Entry

struct LogEntry {
    let timestamp: Date
    let level: LogLevel
    let category: String
    let message: String
    let file: String
    let function: String
    let line: Int
    
    var formattedMessage: String {
        "[\(file):\(line)] \(function) - \(message)"
    }
    
    var fullMessage: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let timestamp = formatter.string(from: timestamp)
        
        return "\(timestamp) [\(level.rawValue.uppercased())] [\(category)] \(formattedMessage)"
    }
}

// MARK: - Log Destination Protocol

protocol LogDestination: AnyObject {
    func write(_ entry: LogEntry)
}

// MARK: - Console Log Destination

class ConsoleLogDestination: LogDestination {
    func write(_ entry: LogEntry) {
        print(entry.fullMessage)
    }
}

// MARK: - File Log Destination

class FileLogDestination: LogDestination {
    private let fileURL: URL
    private let maxFileSize: Int64 = 10 * 1024 * 1024 // 10MB
    private let queue = DispatchQueue(label: "com.runanywhere.file.logger")
    
    init?(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let dir = dir else { return nil }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "llm-\(formatter.string(from: Date())).log"
        
        self.fileURL = dir.appendingPathComponent(filename)
        
        // Create file if it doesn't exist
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
    }
    
    func write(_ entry: LogEntry) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                // Check file size and rotate if needed
                let attributes = try FileManager.default.attributesOfItem(atPath: self.fileURL.path)
                if let fileSize = attributes[.size] as? Int64, fileSize > self.maxFileSize {
                    self.rotateLog()
                }
                
                // Write log entry
                let data = (entry.fullMessage + "\n").data(using: .utf8) ?? Data()
                if let fileHandle = try? FileHandle(forWritingTo: self.fileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } catch {
                print("Failed to write log: \(error)")
            }
        }
    }
    
    private func rotateLog() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = formatter.string(from: Date())
        
        let rotatedURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("llm-\(timestamp).log")
        
        try? FileManager.default.moveItem(at: fileURL, to: rotatedURL)
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
    }
}

// MARK: - Performance Logger

extension Logger {
    func startPerformanceTracking(_ operation: String) -> PerformanceTracker {
        PerformanceTracker(operation: operation, logger: self)
    }
}

class PerformanceTracker {
    private let operation: String
    private let startTime: CFAbsoluteTime
    private weak var logger: Logger?
    
    init(operation: String, logger: Logger) {
        self.operation = operation
        self.startTime = CFAbsoluteTimeGetCurrent()
        self.logger = logger
        
        logger.debug("Started: \(operation)", category: "performance")
    }
    
    func end(framework: LLMFramework? = nil) {
        let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000 // Convert to ms
        logger?.logPerformance(operation, value: duration, framework: framework)
    }
}