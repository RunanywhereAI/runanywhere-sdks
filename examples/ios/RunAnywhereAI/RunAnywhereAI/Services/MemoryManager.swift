//
//  MemoryManager.swift
//  RunAnywhereAI
//

import Foundation
import os.log
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Memory Manager

@MainActor
class MemoryManager: ObservableObject {
    @MainActor static let shared = MemoryManager()
    
    @Published var totalMemory: Int64 = 0
    @Published var availableMemory: Int64 = 0
    @Published var usedMemory: Int64 = 0
    @Published var memoryPressure: MemoryPressureLevel = .normal
    
    private let logger = Logger(subsystem: "com.runanywhere", category: "MemoryManager")
    private var memoryWarningObserver: NSObjectProtocol?
    private let updateQueue = DispatchQueue(label: "com.runanywhere.memory.update")
    private var updateTimer: Timer?
    
    enum MemoryPressureLevel {
        case normal
        case warning
        case critical
        
        var color: String {
            switch self {
            case .normal: return "green"
            case .warning: return "yellow"
            case .critical: return "red"
            }
        }
        
        var description: String {
            switch self {
            case .normal: return "Normal"
            case .warning: return "Memory Warning"
            case .critical: return "Critical - Free up memory"
            }
        }
    }
    
    private init() {
        setupMemoryMonitoring()
        updateMemoryStats()
    }
    
    deinit {
        updateTimer?.invalidate()
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Setup
    
    private func setupMemoryMonitoring() {
        // Monitor memory warnings
        #if canImport(UIKit)
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
        #endif
        
        // Start periodic memory updates
        updateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMemoryStats()
            }
        }
        
        // Get total physical memory
        totalMemory = Int64(ProcessInfo.processInfo.physicalMemory)
    }
    
    // MARK: - Memory Monitoring
    
    private func updateMemoryStats() {
        updateQueue.async { [weak self] in
            guard let self = self else { return }
            
            let used = self.getUsedMemory()
            let available = self.totalMemory - used
            let pressure = self.calculateMemoryPressure(availableMemory: available)
            
            DispatchQueue.main.async {
                self.usedMemory = used
                self.availableMemory = available
                self.memoryPressure = pressure
            }
        }
    }
    
    private func getUsedMemory() -> Int64 {
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
        
        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
    
    private func calculateMemoryPressure(availableMemory: Int64) -> MemoryPressureLevel {
        let percentUsed = Double(usedMemory) / Double(totalMemory)
        
        if availableMemory < 500_000_000 || percentUsed > 0.9 { // < 500MB or > 90% used
            return .critical
        } else if availableMemory < 1_000_000_000 || percentUsed > 0.8 { // < 1GB or > 80% used
            return .warning
        } else {
            return .normal
        }
    }
    
    // MARK: - Memory Warning Handling
    
    private func handleMemoryWarning() {
        logger.warning("Received memory warning")
        
        memoryPressure = .critical
        
        // Notify all services to reduce memory usage
        Task {
            await UnifiedLLMService.shared.handleMemoryWarning()
        }
        
        // Clear image caches if any
        URLCache.shared.removeAllCachedResponses()
        
        // Force garbage collection
        autoreleasepool {
            // This helps release autoreleased objects
        }
    }
    
    // MARK: - Public Methods
    
    func canLoadModel(estimatedSize: Int64) -> Bool {
        // Check if we have enough memory to load a model
        let requiredMemory = estimatedSize + 500_000_000 // Model size + 500MB buffer
        return availableMemory > requiredMemory
    }
    
    func requestMemory(size: Int64) -> Bool {
        // Check if requested memory is available
        if availableMemory > size {
            return true
        }
        
        // Try to free up memory
        handleMemoryWarning()
        updateMemoryStats()
        
        // Check again after cleanup
        return availableMemory > size
    }
    
    func getMemoryStats() -> MemoryStats {
        MemoryStats(
            total: totalMemory,
            used: usedMemory,
            available: availableMemory,
            pressure: memoryPressure
        )
    }
    
    func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }
    
    // MARK: - Memory Cleanup
    
    func performCleanup() async {
        // Trigger memory pressure handling
        await MainActor.run {
            handleMemoryWarning()
        }
    }
}

// MARK: - Memory Stats

struct MemoryStats {
    let total: Int64
    let used: Int64
    let available: Int64
    let pressure: MemoryManager.MemoryPressureLevel
    
    var usedPercentage: Double {
        Double(used) / Double(total) * 100
    }
    
    var availablePercentage: Double {
        Double(available) / Double(total) * 100
    }
}

// MARK: - Memory Aware Protocol

protocol MemoryAware {
    func reduceMemoryUsage()
    func getEstimatedMemoryUsage() -> Int64
}

// MARK: - UnifiedLLMService Memory Extension

extension UnifiedLLMService {
    @MainActor
    func handleMemoryWarning() {
        // Clear any cached data
        error = nil
        
        // Request current service to reduce memory if possible
        if let service = currentService as? MemoryAware {
            service.reduceMemoryUsage()
        }
        
        // Log memory warning
        print("UnifiedLLMService: Handling memory warning")
    }
}
