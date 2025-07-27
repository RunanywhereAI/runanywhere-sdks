//
//  ComparisonViewModel.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/27/25.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class ComparisonViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var frameworkA: LLMFramework = .llamaCpp
    @Published var frameworkB: LLMFramework = .coreML
    @Published var outputA = ""
    @Published var outputB = ""
    @Published var isGeneratingA = false
    @Published var isGeneratingB = false
    @Published var metricsA: ComparisonMetrics?
    @Published var metricsB: ComparisonMetrics?
    @Published var performanceDataA: [Double] = []
    @Published var performanceDataB: [Double] = []
    @Published var settings = ComparisonSettings()
    
    // MARK: - Private Properties
    private let unifiedService = UnifiedLLMService.shared
    private let performanceMonitor = RealtimePerformanceMonitor.shared
    private let abTesting = ABTestingFramework.shared
    private let logger = Logger.shared
    private var cancellables = Set<AnyCancellable>()
    private var taskA: Task<Void, Never>?
    private var taskB: Task<Void, Never>?
    
    let quickPrompts = [
        "Hello, how are you?",
        "Explain quantum computing",
        "Write a haiku about AI",
        "What is 2+2?",
        "Tell me a joke"
    ]
    
    var isGenerating: Bool {
        isGeneratingA || isGeneratingB
    }
    
    // MARK: - Initialization
    init() {
        setupSubscriptions()
    }
    
    // MARK: - Public Methods
    
    func runComparison(prompt: String) async {
        // Reset outputs
        outputA = ""
        outputB = ""
        metricsA = nil
        metricsB = nil
        performanceDataA.removeAll()
        performanceDataB.removeAll()
        
        // Create A/B test if enabled
        if settings.autoRunBenchmarks {
            let variantA = TestVariant(id: UUID(), name: frameworkA.displayName, framework: frameworkA, configuration: [:])
            let variantB = TestVariant(id: UUID(), name: frameworkB.displayName, framework: frameworkB, configuration: [:])
            
            let test = abTesting.createTest(
                name: "Manual Comparison",
                description: "Comparing \(frameworkA.displayName) vs \(frameworkB.displayName)",
                variantA: variantA,
                variantB: variantB
            )
            
            do {
                try await abTesting.startTest(test.id)
            } catch {
                logger.log("Failed to start A/B test: \(error)", level: .error, category: "Comparison")
            }
        }
        
        // Run generations
        if settings.synchronizeStart {
            // Start both at the same time
            async let resultA = generateWithFramework(frameworkA, prompt: prompt, isA: true)
            async let resultB = generateWithFramework(frameworkB, prompt: prompt, isA: false)
            
            _ = await (resultA, resultB)
        } else {
            // Run sequentially
            await generateWithFramework(frameworkA, prompt: prompt, isA: true)
            await generateWithFramework(frameworkB, prompt: prompt, isA: false)
        }
    }
    
    func determineWinner() -> LLMFramework? {
        guard let metricsA = metricsA, let metricsB = metricsB else { return nil }
        
        // Simple scoring based on speed and efficiency
        let scoreA = metricsA.tokensPerSecond / (Double(metricsA.memoryUsed) / 1_000_000_000)
        let scoreB = metricsB.tokensPerSecond / (Double(metricsB.memoryUsed) / 1_000_000_000)
        
        if abs(scoreA - scoreB) < 0.1 {
            return nil // Too close to call
        }
        
        return scoreA > scoreB ? frameworkA : frameworkB
    }
    
    func stopGeneration() {
        taskA?.cancel()
        taskB?.cancel()
        isGeneratingA = false
        isGeneratingB = false
    }
    
    // MARK: - Private Methods
    
    private func setupSubscriptions() {
        // Monitor performance metrics if enabled
        if settings.showRealtimeMetrics {
            performanceMonitor.$currentMetrics
                .receive(on: DispatchQueue.main)
                .sink { [weak self] metrics in
                    guard let self = self else { return }
                    
                    if metrics.currentTokensPerSecond > 0 {
                        if self.isGeneratingA {
                            self.performanceDataA.append(metrics.currentTokensPerSecond)
                            if self.performanceDataA.count > 50 {
                                self.performanceDataA.removeFirst()
                            }
                        }
                        if self.isGeneratingB {
                            self.performanceDataB.append(metrics.currentTokensPerSecond)
                            if self.performanceDataB.count > 50 {
                                self.performanceDataB.removeFirst()
                            }
                        }
                    }
                }
                .store(in: &cancellables)
        }
    }
    
    private func generateWithFramework(_ framework: LLMFramework, prompt: String, isA: Bool) async {
        if isA {
            isGeneratingA = true
        } else {
            isGeneratingB = true
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let startMemory = getMemoryUsage()
        var firstTokenTime: CFAbsoluteTime?
        var tokenCount = 0
        var generatedText = ""
        
        do {
            // Switch to framework
            unifiedService.selectService(named: framework.displayName)
            
            // Start monitoring
            performanceMonitor.beginGeneration(framework: framework, prompt: prompt)
            
            // Generate
            let options = GenerationOptions(
                maxTokens: settings.maxTokens,
                temperature: Float(settings.temperature),
                topP: 0.95,
                topK: 40,
                repetitionPenalty: 1.1,
                stopSequences: []
            )
            
            try await unifiedService.streamGenerate(
                prompt: prompt,
                options: options
            ) { [weak self] token in
                guard let self = self else { return }
                
                if firstTokenTime == nil {
                    firstTokenTime = CFAbsoluteTimeGetCurrent()
                }
                
                tokenCount += 1
                generatedText += token
                
                Task { @MainActor in
                    if isA {
                        self.outputA = generatedText
                    } else {
                        self.outputB = generatedText
                    }
                }
                
                // Record for performance tracking
                self.performanceMonitor.recordToken(token)
            }
            
            // End monitoring
            performanceMonitor.endGeneration()
            
            // Calculate final metrics
            let endTime = CFAbsoluteTimeGetCurrent()
            let endMemory = getMemoryUsage()
            
            let metrics = ComparisonMetrics(
                totalTime: endTime - startTime,
                timeToFirstToken: firstTokenTime.map { $0 - startTime } ?? 0,
                tokensPerSecond: Double(tokenCount) / (endTime - startTime),
                tokenCount: tokenCount,
                memoryUsed: Int(endMemory - startMemory)
            )
            
            if isA {
                metricsA = metrics
            } else {
                metricsB = metrics
            }
            
            // Record A/B test metric
            if settings.autoRunBenchmarks {
                let metric = ABTestMetric(
                    id: UUID(),
                    timestamp: Date(),
                    type: .tokensPerSecond(metrics.tokensPerSecond)
                )
                
                // Record to appropriate variant
                if let activeTest = abTesting.activeTests.last {
                    let variant = isA ? activeTest.variantA : activeTest.variantB
                    abTesting.recordMetric(testId: activeTest.id, variant: variant, metric: metric)
                }
            }
        } catch {
            logger.log("Generation failed for \(framework.displayName): \(error)", level: .error, category: "Comparison")
            
            let errorText = "Error: \(error.localizedDescription)"
            if isA {
                outputA = errorText
            } else {
                outputB = errorText
            }
        }
        
        if isA {
            isGeneratingA = false
        } else {
            isGeneratingB = false
        }
    }
    
    private func getMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }
        
        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
}

// MARK: - Supporting Types

struct ComparisonSettings {
    var maxTokens: Int = 150
    var temperature: Double = 0.7
    var synchronizeStart: Bool = true
    var showRealtimeMetrics: Bool = true
    var autoRunBenchmarks: Bool = false
}

// MARK: - Supporting Types

struct ComparisonMetrics {
    let totalTime: TimeInterval
    let timeToFirstToken: TimeInterval
    let tokensPerSecond: Double
    let tokenCount: Int
    let memoryUsed: Int
}
