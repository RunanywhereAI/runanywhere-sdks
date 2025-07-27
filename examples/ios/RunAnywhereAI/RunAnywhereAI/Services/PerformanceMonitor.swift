//
//  PerformanceMonitor.swift
//  RunAnywhereAI
//
//  Created on 7/26/25.
//

import Foundation
import UIKit
import os.log

struct PerformanceTrackingMetrics {
    let totalTime: TimeInterval
    let timeToFirstToken: TimeInterval
    let tokensPerSecond: Double
    let tokenCount: Int
    let memoryUsed: Int
}

class PerformanceMonitor {
    private var startTime: CFAbsoluteTime = 0
    private var firstTokenTime: CFAbsoluteTime = 0
    private var tokenCount = 0
    private let logger = Logger.shared
    
    func startMeasurement() {
        startTime = CFAbsoluteTimeGetCurrent()
        firstTokenTime = 0
        tokenCount = 0
        logger.log("Started performance measurement", level: .debug, category: "Performance")
    }
    
    func recordFirstToken() {
        if firstTokenTime == 0 {
            firstTokenTime = CFAbsoluteTimeGetCurrent()
            let ttft = firstTokenTime - startTime
            logger.log("Time to first token: \(String(format: "%.3f", ttft))s", level: .info, category: "Performance")
        }
    }
    
    func recordToken() {
        tokenCount += 1
        if firstTokenTime == 0 {
            recordFirstToken()
        }
    }
    
    func endMeasurement() -> PerformanceTrackingMetrics {
        let endTime = CFAbsoluteTimeGetCurrent()
        let totalTime = endTime - startTime
        let timeToFirstToken = firstTokenTime > 0 ? firstTokenTime - startTime : 0
        let tokensPerSecond = tokenCount > 0 ? Double(tokenCount) / totalTime : 0
        
        let metrics = PerformanceTrackingMetrics(
            totalTime: totalTime,
            timeToFirstToken: timeToFirstToken,
            tokensPerSecond: tokensPerSecond,
            tokenCount: tokenCount,
            memoryUsed: getCurrentMemoryUsage()
        )
        
        logger.log("""
            Performance metrics:
            - Total time: \(String(format: "%.2f", metrics.totalTime))s
            - Time to first token: \(String(format: "%.3f", metrics.timeToFirstToken))s
            - Tokens/sec: \(String(format: "%.1f", metrics.tokensPerSecond))
            - Token count: \(metrics.tokenCount)
            - Memory used: \(ByteCountFormatter.string(fromByteCount: Int64(metrics.memoryUsed), countStyle: .memory))
            """, level: .info, category: "Performance")
        
        return metrics
    }
    
    private func getCurrentMemoryUsage() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        return result == KERN_SUCCESS ? Int(info.resident_size) : 0
    }
}

// Memory optimizer
class MemoryOptimizer {
    static let shared = MemoryOptimizer()
    private let logger = Logger.shared
    
    private init() {
        setupMemoryWarningObserver()
    }
    
    private func setupMemoryWarningObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    @objc private func handleMemoryWarning() {
        logger.log("Received memory warning", level: .warning, category: "Memory")
        clearCaches()
    }
    
    func clearCaches() {
        // Clear URL cache
        URLCache.shared.removeAllCachedResponses()
        
        // Post notification for services to clear their caches
        NotificationCenter.default.post(
            name: .clearModelCaches,
            object: nil
        )
        
        logger.log("Cleared caches due to memory pressure", level: .info, category: "Memory")
    }
    
    func getAvailableMemory() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let totalMemory = ProcessInfo.processInfo.physicalMemory
            let usedMemory = info.resident_size
            return Int64(totalMemory) - Int64(usedMemory)
        }
        
        return 0
    }
}

extension Notification.Name {
    static let clearModelCaches = Notification.Name("clearModelCaches")
}
