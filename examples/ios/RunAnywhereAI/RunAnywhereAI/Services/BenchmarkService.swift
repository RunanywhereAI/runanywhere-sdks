import Foundation
import SwiftUI

// MARK: - Benchmark Types

struct BenchmarkPrompt {
    let text: String
    let category: String
    let expectedTokens: Int
}

struct BenchmarkResult: Identifiable {
    let id = UUID()
    let framework: LLMFramework
    let model: ModelInfo
    let prompt: BenchmarkPrompt
    let tokensPerSecond: Double
    let timeToFirstToken: TimeInterval
    let totalTime: TimeInterval
    let generatedTokens: Int
    let memoryUsedMB: Double
    let cpuUsagePercent: Double
    let success: Bool
    let error: String?
    let timestamp: Date = Date()
}

struct FrameworkBenchmark: Identifiable {
    let id = UUID()
    let framework: LLMFramework
    let results: [BenchmarkResult]
    
    var averageTokensPerSecond: Double {
        let successful = results.filter { $0.success }
        guard !successful.isEmpty else { return 0 }
        return successful.map { $0.tokensPerSecond }.reduce(0, +) / Double(successful.count)
    }
    
    var averageTimeToFirstToken: TimeInterval {
        let successful = results.filter { $0.success }
        guard !successful.isEmpty else { return 0 }
        return successful.map { $0.timeToFirstToken }.reduce(0, +) / Double(successful.count)
    }
    
    var successRate: Double {
        guard !results.isEmpty else { return 0 }
        return Double(results.filter { $0.success }.count) / Double(results.count)
    }
    
    var averageMemoryMB: Double {
        let successful = results.filter { $0.success }
        guard !successful.isEmpty else { return 0 }
        return successful.map { $0.memoryUsedMB }.reduce(0, +) / Double(successful.count)
    }
}

// MARK: - Benchmark Service

@MainActor
class BenchmarkService: ObservableObject {
    @Published var isRunning = false
    @Published var currentProgress: Double = 0
    @Published var currentStatus = ""
    @Published var benchmarkResults: [FrameworkBenchmark] = []
    @Published var selectedFrameworks: Set<LLMFramework> = []
    @Published var selectedPromptCategories: Set<String> = ["short", "medium", "long"]
    
    private let unifiedService = UnifiedLLMService.shared
    private let memoryManager = MemoryManager.shared
    
    // Standard benchmark prompts
    let benchmarkPrompts = [
        BenchmarkPrompt(
            text: "Hello, how are you?",
            category: "short",
            expectedTokens: 20
        ),
        BenchmarkPrompt(
            text: "Explain the concept of machine learning in simple terms.",
            category: "medium",
            expectedTokens: 100
        ),
        BenchmarkPrompt(
            text: "Write a detailed explanation of how large language models work, including their architecture, training process, and common use cases. Be thorough and technical.",
            category: "long",
            expectedTokens: 300
        ),
        BenchmarkPrompt(
            text: "What is 2+2?",
            category: "short",
            expectedTokens: 10
        ),
        BenchmarkPrompt(
            text: "Compare and contrast supervised and unsupervised learning approaches in machine learning.",
            category: "medium",
            expectedTokens: 150
        ),
        BenchmarkPrompt(
            text: "Provide a comprehensive overview of the history of artificial intelligence, from its inception to modern deep learning systems. Include key milestones, breakthroughs, and influential researchers.",
            category: "long",
            expectedTokens: 400
        )
    ]
    
    func runBenchmark(models: [ModelInfo]) async {
        isRunning = true
        benchmarkResults = []
        currentProgress = 0
        
        let frameworks = selectedFrameworks.isEmpty ? LLMFramework.allCases : Array(selectedFrameworks)
        let prompts = benchmarkPrompts.filter { selectedPromptCategories.contains($0.category) }
        
        let totalTests = frameworks.count * models.count * prompts.count
        var completedTests = 0
        
        for framework in frameworks {
            var frameworkResults: [BenchmarkResult] = []
            
            for model in models where model.framework == framework {
                currentStatus = "Testing \(framework.rawValue) with \(model.name)..."
                
                // Load model
                do {
                    try await unifiedService.loadModel(model, framework: framework)
                    
                    // Run tests with different prompts
                    for prompt in prompts {
                        let result = await benchmarkSinglePrompt(
                            framework: framework,
                            model: model,
                            prompt: prompt
                        )
                        frameworkResults.append(result)
                        
                        completedTests += 1
                        currentProgress = Double(completedTests) / Double(totalTests)
                    }
                    
                    // Cleanup after each model
                    unifiedService.cleanup()
                    
                } catch {
                    // Record failure for all prompts
                    for prompt in prompts {
                        frameworkResults.append(BenchmarkResult(
                            framework: framework,
                            model: model,
                            prompt: prompt,
                            tokensPerSecond: 0,
                            timeToFirstToken: 0,
                            totalTime: 0,
                            generatedTokens: 0,
                            memoryUsedMB: 0,
                            cpuUsagePercent: 0,
                            success: false,
                            error: error.localizedDescription
                        ))
                        
                        completedTests += 1
                        currentProgress = Double(completedTests) / Double(totalTests)
                    }
                }
            }
            
            if !frameworkResults.isEmpty {
                benchmarkResults.append(FrameworkBenchmark(
                    framework: framework,
                    results: frameworkResults
                ))
            }
        }
        
        currentStatus = "Benchmark complete!"
        isRunning = false
    }
    
    private func benchmarkSinglePrompt(
        framework: LLMFramework,
        model: ModelInfo,
        prompt: BenchmarkPrompt
    ) async -> BenchmarkResult {
        let startTime = Date()
        var timeToFirstToken: TimeInterval = 0
        var tokenCount = 0
        var firstTokenReceived = false
        
        // Get initial memory and CPU stats
        let initialMemory = memoryManager.getMemoryStats().used
        let initialCPU = getCPUUsage()
        
        do {
            let options = GenerationOptions(
                maxTokens: prompt.expectedTokens,
                temperature: 0.7,
                topP: 0.9,
                topK: 40,
                repetitionPenalty: 1.1
            )
            
            try await unifiedService.streamGenerate(
                prompt: prompt.text,
                options: options
            ) { token in
                if !firstTokenReceived {
                    timeToFirstToken = Date().timeIntervalSince(startTime)
                    firstTokenReceived = true
                }
                tokenCount += 1
            }
            
            let totalTime = Date().timeIntervalSince(startTime)
            let tokensPerSecond = Double(tokenCount) / totalTime
            
            // Get final memory and CPU stats
            let finalMemory = memoryManager.getMemoryStats().used
            let finalCPU = getCPUUsage()
            
            let memoryUsedMB = Double(finalMemory - initialMemory) / 1_000_000
            let cpuUsagePercent = (finalCPU - initialCPU) * 100
            
            return BenchmarkResult(
                framework: framework,
                model: model,
                prompt: prompt,
                tokensPerSecond: tokensPerSecond,
                timeToFirstToken: timeToFirstToken,
                totalTime: totalTime,
                generatedTokens: tokenCount,
                memoryUsedMB: max(0, memoryUsedMB), // Ensure non-negative
                cpuUsagePercent: max(0, cpuUsagePercent),
                success: true,
                error: nil
            )
            
        } catch {
            return BenchmarkResult(
                framework: framework,
                model: model,
                prompt: prompt,
                tokensPerSecond: 0,
                timeToFirstToken: 0,
                totalTime: Date().timeIntervalSince(startTime),
                generatedTokens: 0,
                memoryUsedMB: 0,
                cpuUsagePercent: 0,
                success: false,
                error: error.localizedDescription
            )
        }
    }
    
    private func getCPUUsage() -> Double {
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
            return Double(info.resident_size) / Double(ProcessInfo.processInfo.physicalMemory)
        }
        
        return 0
    }
    
    // MARK: - Export Results
    
    func exportResults() -> String {
        var csv = "Framework,Model,Prompt Category,Tokens/Second,Time to First Token (s),Total Time (s),Generated Tokens,Memory Used (MB),CPU Usage (%),Success,Error\n"
        
        for benchmark in benchmarkResults {
            for result in benchmark.results {
                csv += "\"\(result.framework.rawValue)\","
                csv += "\"\(result.model.name)\","
                csv += "\"\(result.prompt.category)\","
                csv += "\(String(format: "%.2f", result.tokensPerSecond)),"
                csv += "\(String(format: "%.3f", result.timeToFirstToken)),"
                csv += "\(String(format: "%.2f", result.totalTime)),"
                csv += "\(result.generatedTokens),"
                csv += "\(String(format: "%.2f", result.memoryUsedMB)),"
                csv += "\(String(format: "%.1f", result.cpuUsagePercent)),"
                csv += "\(result.success ? "Yes" : "No"),"
                csv += "\"\(result.error ?? "")\""
                csv += "\n"
            }
        }
        
        return csv
    }
    
    func saveResults() {
        let csv = exportResults()
        let filename = "benchmark_\(Date().ISO8601Format()).csv"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
        
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            print("Benchmark results saved to: \(url.path)")
        } catch {
            print("Failed to save benchmark results: \(error)")
        }
    }
}

// MARK: - Benchmark Comparison

extension BenchmarkService {
    func getTopPerformers(metric: BenchmarkMetric) -> [(framework: LLMFramework, value: Double)] {
        benchmarkResults.compactMap { benchmark in
            let value: Double
            switch metric {
            case .tokensPerSecond:
                value = benchmark.averageTokensPerSecond
            case .timeToFirstToken:
                value = benchmark.averageTimeToFirstToken
            case .memoryUsage:
                value = benchmark.averageMemoryMB
            case .successRate:
                value = benchmark.successRate
            }
            return (benchmark.framework, value)
        }.sorted { metric == .timeToFirstToken || metric == .memoryUsage ? $0.value < $1.value : $0.value > $1.value }
    }
    
    enum BenchmarkMetric {
        case tokensPerSecond
        case timeToFirstToken
        case memoryUsage
        case successRate
        
        var name: String {
            switch self {
            case .tokensPerSecond: return "Tokens/Second"
            case .timeToFirstToken: return "Time to First Token"
            case .memoryUsage: return "Memory Usage"
            case .successRate: return "Success Rate"
            }
        }
        
        var unit: String {
            switch self {
            case .tokensPerSecond: return "tok/s"
            case .timeToFirstToken: return "seconds"
            case .memoryUsage: return "MB"
            case .successRate: return "%"
            }
        }
    }
}