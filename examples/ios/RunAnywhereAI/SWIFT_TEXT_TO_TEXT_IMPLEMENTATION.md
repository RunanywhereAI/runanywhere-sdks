# Swift Sample App Text-to-Text Generation Implementation

**Technical Specification for Android Parity**

**Document Version:** 1.0
**Date:** January 2025
**Purpose:** Definitive reference for implementing text-to-text generation in Android

---

## Table of Contents

1. [SDK Initialization Flow](#1-sdk-initialization-flow)
2. [Model Management & Download](#2-model-management--download)
3. [Text-to-Text Generation Flow](#3-text-to-text-generation-flow)
4. [Analytics System](#4-analytics-system)
5. [Data Models](#5-data-models)
6. [Settings Integration](#6-settings-integration)
7. [State Management](#7-state-management)
8. [Error Handling](#8-error-handling)
9. [Critical Dependencies](#9-critical-dependencies)
10. [Implementation Checklist](#10-implementation-checklist)

---

## 1. SDK Initialization Flow

### 1.1 App Launch Sequence

**File:** `examples/ios/RunAnywhereAI/RunAnywhereAI/App/RunAnywhereAIApp.swift`

#### Initialization Steps

```swift
// Step 1: SDK Initialization (Fast, No Network Calls)
try RunAnywhere.initialize(
    apiKey: "dev",  // Any string works in dev mode
    baseURL: "localhost",  // Not used in dev mode
    environment: .development
)

// Step 2: Register Framework Adapters
await LLMSwiftServiceProvider.register()
await WhisperKitServiceProvider.register()
await FluidAudioDiarizationProvider.register()

// Step 3: Register Models with Lazy Loading
let lazyOptions = AdapterRegistrationOptions(
    validateModels: false,
    autoDownloadInDev: false,  // Don't auto-download
    showProgress: true,
    fallbackToMockModels: true,
    downloadTimeout: 600
)

try await RunAnywhere.registerFrameworkAdapter(
    LLMSwiftAdapter(),
    models: [/* Model registrations */],
    options: lazyOptions
)
```

#### Initialization Timing

- **Initialization Time:** < 100ms (validated via logging)
- **Network Calls:** ZERO during initialization
- **Device Registration:** Lazy (happens on first API call)
- **Model Loading:** Lazy (user-triggered)

#### Key Points

1. **Development Mode:** No API key validation required
2. **Local Storage Only:** No keychain for dev mode
3. **Lazy Device Registration:** Only registers when making first API call
4. **No Auto-Download:** Models are NOT downloaded automatically

### 1.2 SDK Configuration Storage

**File:** `sdk/runanywhere-swift/Sources/RunAnywhere/Public/RunAnywhere.swift`

```swift
// Internal state management
internal static var configurationData: ConfigurationData?
internal static var initParams: SDKInitParams?
internal static var currentEnvironment: SDKEnvironment?
private static var isInitialized = false

// Device ID management
private static var _cachedDeviceId: String?
private static var _isRegistering: Bool = false
private static let registrationLock = NSLock()
```

#### Device Registration (Lazy)

```swift
private static func ensureDeviceRegistered() async throws {
    // Skip in development mode
    if currentEnvironment == .development {
        let mockDeviceId = "dev-" + generateDeviceIdentifier()
        try storeDeviceId(mockDeviceId)
        _cachedDeviceId = mockDeviceId
        return
    }

    // Register device with backend (with retry logic)
    for attempt in 1...maxRegistrationRetries {
        do {
            let deviceRegistration = try await authService.registerDevice()
            try storeDeviceId(deviceRegistration.deviceId)
            _cachedDeviceId = deviceRegistration.deviceId
            return
        } catch {
            // Retry logic
        }
    }
}
```

---

## 2. Model Management & Download

### 2.1 Model Registration

**File:** `examples/ios/RunAnywhereAI/RunAnywhereAI/App/RunAnywhereAIApp.swift`

#### Model Registration Structure

```swift
try! ModelRegistration(
    url: "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf",
    framework: .llamaCpp,
    id: "smollm2-360m-q8-0",
    name: "SmolLM2 360M Q8_0",
    memoryRequirement: 500_000_000
)
```

#### Available Models (Example Set)

| Model ID | Name | Size | Framework |
|----------|------|------|-----------|
| smollm2-360m-q8-0 | SmolLM2 360M Q8_0 | ~500 MB | llama.cpp |
| qwen-2.5-0.5b-instruct-q6-k | Qwen 2.5 0.5B Instruct Q6_K | ~600 MB | llama.cpp |
| llama-3.2-1b-instruct-q6-k | Llama 3.2 1B Instruct Q6_K | ~1.2 GB | llama.cpp |
| smollm2-1.7b-instruct-q6-k-l | SmolLM2 1.7B Instruct Q6_K_L | ~1.8 GB | llama.cpp |
| qwen-2.5-1.5b-instruct-q6-k | Qwen 2.5 1.5B Instruct Q6_K | ~1.6 GB | llama.cpp |
| lfm2-350m-q4-k-m | LiquidAI LFM2 350M Q4_K_M | ~250 MB | llama.cpp |
| lfm2-350m-q8-0 | LiquidAI LFM2 350M Q8_0 | ~400 MB | llama.cpp |

### 2.2 Model Discovery

**File:** `examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Models/ModelListViewModel.swift`

```swift
func loadModelsFromRegistry() async {
    // Get all models from SDK registry
    let allModels = try await RunAnywhere.availableModels()

    // Filter based on iOS version if needed
    var filteredModels = allModels
    if #unavailable(iOS 26.0) {
        filteredModels = allModels.filter { $0.preferredFramework != .foundationModels }
    }

    availableModels = filteredModels
}
```

### 2.3 Model Download Flow

**File:** `examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Models/SimplifiedModelsView.swift`

#### Download Implementation

```swift
private func downloadModel() async {
    await MainActor.run {
        isDownloading = true
        downloadProgress = 0.0
    }

    do {
        // Use progress-enabled download API
        let progressStream = try await RunAnywhere.downloadModelWithProgress(model.id)

        // Process progress updates
        for await progress in progressStream {
            await MainActor.run {
                self.downloadProgress = progress.percentage
            }

            // Check download state
            switch progress.state {
            case .completed:
                await MainActor.run {
                    self.downloadProgress = 1.0
                    self.isDownloading = false
                    onDownloadCompleted()
                }
                return

            case .failed(let error):
                await MainActor.run {
                    self.downloadProgress = 0.0
                    self.isDownloading = false
                }
                return

            default:
                continue
            }
        }
    } catch {
        await MainActor.run {
            downloadProgress = 0.0
            isDownloading = false
        }
    }
}
```

#### Download Progress States

```swift
enum DownloadState {
    case idle
    case downloading(percentage: Double)
    case completed
    case failed(Error)
}
```

### 2.4 Model Loading

**File:** `examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Models/SimplifiedModelsView.swift`

```swift
private func selectModel(_ model: ModelInfo) async {
    selectedModel = model
    await viewModel.selectModel(model)
}

// In ModelListViewModel
func selectModel(_ model: ModelInfo) async {
    do {
        try await loadModel(model)
        setCurrentModel(model)

        // Post notification that model was loaded
        await MainActor.run {
            NotificationCenter.default.post(
                name: Notification.Name("ModelLoaded"),
                object: model
            )
        }
    } catch {
        errorMessage = "Failed to load model: \(error.localizedDescription)"
    }
}
```

#### Model Load Flow

1. User selects model from UI
2. `selectModel()` called on ViewModel
3. SDK loads model via `RunAnywhere.loadModel(model.id)`
4. Notification posted: "ModelLoaded"
5. ChatViewModel receives notification
6. UI updates to reflect loaded model

---

## 3. Text-to-Text Generation Flow

### 3.1 Complete Generation Sequence

**File:** `examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Chat/ChatViewModel.swift`

#### User Message → AI Response Flow

```
User Input → sendMessage() → SDK Generation → Streaming → Analytics → UI Update
```

#### Detailed Implementation

```swift
func sendMessage() async {
    guard canSend else { return }

    let prompt = currentInput
    currentInput = ""
    isGenerating = true
    error = nil

    // 1. Add user message
    let userMessage = Message(role: .user, content: prompt)
    messages.append(userMessage)

    // 2. Save user message to conversation
    if let conversation = currentConversation {
        conversationStore.addMessage(userMessage, to: conversation)
    }

    // 3. Create assistant message placeholder
    let assistantMessage = Message(role: .assistant, content: "")
    messages.append(assistantMessage)
    let messageIndex = messages.count - 1

    // 4. Start generation task
    generationTask = Task {
        do {
            // 4a. Ensure model is loaded
            if isModelLoaded, let model = ModelListViewModel.shared.currentModel {
                try await RunAnywhere.loadModel(model.id)
            }

            // 4b. Get generation options from settings
            let savedTemperature = UserDefaults.standard.double(forKey: "defaultTemperature")
            let savedMaxTokens = UserDefaults.standard.integer(forKey: "defaultMaxTokens")

            let effectiveSettings = (
                temperature: savedTemperature != 0 ? savedTemperature : 0.7,
                maxTokens: savedMaxTokens != 0 ? savedMaxTokens : 1000
            )

            let options = RunAnywhereGenerationOptions(
                maxTokens: effectiveSettings.maxTokens,
                temperature: Float(effectiveSettings.temperature)
            )

            // 4c. Generate with streaming or non-streaming
            if useStreaming {
                await handleStreamingGeneration(prompt, options, messageIndex)
            } else {
                await handleNonStreamingGeneration(prompt, options, messageIndex)
            }
        } catch {
            await handleGenerationError(error, messageIndex)
        }

        // 5. Finalize
        await MainActor.run {
            isGenerating = false

            // Save final message with analytics
            if messageIndex < messages.count,
               let conversation = currentConversation {
                var updatedConversation = conversation
                updatedConversation.messages = messages
                updatedConversation.modelName = loadedModelName
                conversationStore.updateConversation(updatedConversation)
            }
        }
    }
}
```

### 3.2 Streaming Generation

**File:** `examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Chat/ChatViewModel.swift`

```swift
private func handleStreamingGeneration(
    _ prompt: String,
    _ options: RunAnywhereGenerationOptions,
    _ messageIndex: Int
) async {
    var fullResponse = ""
    var isInThinkingMode = false
    var thinkingContent = ""
    var responseContent = ""

    // Analytics tracking
    let startTime = Date()
    var firstTokenTime: Date? = nil
    var thinkingStartTime: Date? = nil
    var thinkingEndTime: Date? = nil
    var tokensPerSecondHistory: [Double] = []
    var totalTokensReceived = 0
    var wasInterrupted = false

    let stream = RunAnywhere.generateStream(prompt, options: options)

    // Stream tokens as they arrive
    for try await token in stream {
        fullResponse += token
        totalTokensReceived += 1

        // Track first token time
        if firstTokenTime == nil {
            firstTokenTime = Date()
        }

        // Calculate real-time tokens per second every 10 tokens
        if totalTokensReceived % 10 == 0 {
            let elapsed = Date().timeIntervalSince(firstTokenTime ?? startTime)
            if elapsed > 0 {
                let currentSpeed = Double(totalTokensReceived) / elapsed
                tokensPerSecondHistory.append(currentSpeed)
            }
        }

        // Check for thinking tags
        if fullResponse.contains("<think>") && !isInThinkingMode {
            isInThinkingMode = true
            thinkingStartTime = Date()
        }

        if isInThinkingMode {
            if fullResponse.contains("</think>") {
                // Extract thinking and response content
                if let thinkingStart = fullResponse.range(of: "<think>"),
                   let thinkingEnd = fullResponse.range(of: "</think>") {
                    thinkingContent = String(fullResponse[thinkingStart.upperBound..<thinkingEnd.lowerBound])
                    responseContent = String(fullResponse[thinkingEnd.upperBound...])
                    isInThinkingMode = false
                    thinkingEndTime = Date()
                }
            } else {
                // Still in thinking mode
                if let thinkingStart = fullResponse.range(of: "<think>") {
                    thinkingContent = String(fullResponse[thinkingStart.upperBound...])
                }
            }
        } else {
            // Not in thinking mode, show response tokens directly
            responseContent = fullResponse.replacingOccurrences(of: "</think>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Update the assistant message with current content
        await MainActor.run {
            if messageIndex < self.messages.count {
                let currentMessage = self.messages[messageIndex]
                let displayContent = isInThinkingMode ? "" : responseContent
                let updatedMessage = Message(
                    id: currentMessage.id,
                    role: currentMessage.role,
                    content: displayContent,
                    thinkingContent: thinkingContent.isEmpty ? nil : thinkingContent.trimmingCharacters(in: .whitespacesAndNewlines),
                    timestamp: currentMessage.timestamp
                )
                self.messages[messageIndex] = updatedMessage

                // Notify UI to scroll during streaming
                NotificationCenter.default.post(name: Notification.Name("MessageContentUpdated"), object: nil)
            }
        }
    }

    // Analytics: Mark end time
    let endTime = Date()
    wasInterrupted = isInThinkingMode && !fullResponse.contains("</think>")

    // Collect analytics
    if let conversationId = currentConversation?.id,
       messageIndex < messages.count {
        let analytics = collectMessageAnalytics(
            messageId: messages[messageIndex].id.uuidString,
            conversationId: conversationId,
            startTime: startTime,
            endTime: endTime,
            firstTokenTime: firstTokenTime,
            thinkingStartTime: thinkingStartTime,
            thinkingEndTime: thinkingEndTime,
            inputText: prompt,
            outputText: responseContent,
            thinkingText: thinkingContent.isEmpty ? nil : thinkingContent,
            tokensPerSecondHistory: tokensPerSecondHistory,
            wasInterrupted: wasInterrupted,
            options: options
        )

        // Update message with analytics
        await MainActor.run {
            if let analytics = analytics, messageIndex < self.messages.count {
                let currentMessage = self.messages[messageIndex]
                let modelInfo = ModelListViewModel.shared.currentModel != nil ?
                    MessageModelInfo(from: ModelListViewModel.shared.currentModel!) : nil

                let updatedMessage = Message(
                    id: currentMessage.id,
                    role: currentMessage.role,
                    content: currentMessage.content,
                    thinkingContent: currentMessage.thinkingContent,
                    timestamp: currentMessage.timestamp,
                    analytics: analytics,
                    modelInfo: modelInfo
                )
                self.messages[messageIndex] = updatedMessage

                // Update conversation-level analytics
                self.updateConversationAnalytics()
            }
        }
    }
}
```

### 3.3 Non-Streaming Generation

```swift
private func handleNonStreamingGeneration(
    _ prompt: String,
    _ options: RunAnywhereGenerationOptions,
    _ messageIndex: Int
) async throws {
    let startTime = Date()
    let resultText = try await RunAnywhere.generate(prompt, options: options)
    let endTime = Date()

    // Update the assistant message with the complete response
    await MainActor.run {
        if messageIndex < self.messages.count {
            let currentMessage = self.messages[messageIndex]
            let updatedMessage = Message(
                role: currentMessage.role,
                content: resultText,
                thinkingContent: nil,
                timestamp: currentMessage.timestamp
            )
            self.messages[messageIndex] = updatedMessage
        }
    }

    // Collect analytics
    if let conversationId = currentConversation?.id,
       messageIndex < messages.count {
        let analytics = collectMessageAnalytics(
            messageId: messages[messageIndex].id.uuidString,
            conversationId: conversationId,
            startTime: startTime,
            endTime: endTime,
            firstTokenTime: nil,
            thinkingStartTime: nil,
            thinkingEndTime: nil,
            inputText: prompt,
            outputText: resultText,
            thinkingText: nil,
            tokensPerSecondHistory: [],
            wasInterrupted: false,
            options: options
        )

        // Update message with analytics
        await MainActor.run {
            if let analytics = analytics, messageIndex < self.messages.count {
                let currentMessage = self.messages[messageIndex]
                let modelInfo = ModelListViewModel.shared.currentModel != nil ?
                    MessageModelInfo(from: ModelListViewModel.shared.currentModel!) : nil

                let updatedMessage = Message(
                    id: currentMessage.id,
                    role: currentMessage.role,
                    content: currentMessage.content,
                    thinkingContent: currentMessage.thinkingContent,
                    timestamp: currentMessage.timestamp,
                    analytics: analytics,
                    modelInfo: modelInfo
                )
                self.messages[messageIndex] = updatedMessage

                // Update conversation-level analytics
                self.updateConversationAnalytics()
            }
        }
    }
}
```

### 3.4 Thinking Mode Support

The system supports models that use `<think>` tags for Chain-of-Thought reasoning:

```swift
// Example output:
// "<think>Let me analyze this question...</think>The answer is..."

// Detection logic:
if fullResponse.contains("<think>") && !isInThinkingMode {
    isInThinkingMode = true
    thinkingStartTime = Date()
}

if isInThinkingMode && fullResponse.contains("</think>") {
    // Extract thinking and response separately
    let thinkingContent = extractBetweenTags("<think>", "</think>")
    let responseContent = extractAfterTag("</think>")
    isInThinkingMode = false
    thinkingEndTime = Date()
}
```

---

## 4. Analytics System

### 4.1 Message Analytics Structure

**File:** `examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Chat/ChatViewModel.swift`

```swift
public struct MessageAnalytics: Codable {
    // Identifiers
    let messageId: String
    let conversationId: String
    let modelId: String
    let modelName: String
    let framework: String
    let timestamp: Date

    // Timing Metrics
    let timeToFirstToken: TimeInterval?
    let totalGenerationTime: TimeInterval
    let thinkingTime: TimeInterval?
    let responseTime: TimeInterval?

    // Token Metrics
    let inputTokens: Int
    let outputTokens: Int
    let thinkingTokens: Int?
    let responseTokens: Int
    let averageTokensPerSecond: Double

    // Quality Metrics
    let messageLength: Int
    let wasThinkingMode: Bool
    let wasInterrupted: Bool
    let retryCount: Int
    let completionStatus: CompletionStatus

    // Performance Indicators
    let tokensPerSecondHistory: [Double]
    let generationMode: GenerationMode

    // Context Information
    let contextWindowUsage: Double
    let generationParameters: GenerationParameters
}
```

#### Completion Status

```swift
public enum CompletionStatus: String, Codable {
    case complete
    case interrupted
    case failed
    case timeout
}
```

#### Generation Mode

```swift
public enum GenerationMode: String, Codable {
    case streaming
    case nonStreaming
}
```

#### Generation Parameters

```swift
public struct GenerationParameters: Codable {
    let temperature: Double
    let maxTokens: Int
    let topP: Double?
    let topK: Int?

    init(temperature: Double = 0.7, maxTokens: Int = 500, topP: Double? = nil, topK: Int? = nil) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
        self.topK = topK
    }
}
```

### 4.2 Analytics Collection

```swift
private func collectMessageAnalytics(
    messageId: String,
    conversationId: String,
    startTime: Date,
    endTime: Date,
    firstTokenTime: Date?,
    thinkingStartTime: Date?,
    thinkingEndTime: Date?,
    inputText: String,
    outputText: String,
    thinkingText: String?,
    tokensPerSecondHistory: [Double],
    wasInterrupted: Bool,
    options: RunAnywhereGenerationOptions
) -> MessageAnalytics? {

    guard let modelName = loadedModelName,
          let currentModel = ModelListViewModel.shared.currentModel else {
        return nil
    }

    let totalGenerationTime = endTime.timeIntervalSince(startTime)
    let timeToFirstToken = firstTokenTime?.timeIntervalSince(startTime)

    var thinkingTime: TimeInterval? = nil
    var responseTime: TimeInterval? = nil

    if let thinkingStart = thinkingStartTime, let thinkingEnd = thinkingEndTime {
        thinkingTime = thinkingEnd.timeIntervalSince(thinkingStart)
        responseTime = totalGenerationTime - (thinkingTime ?? 0)
    }

    // Calculate token counts (rough estimate: ~4 characters per token)
    let inputTokens = estimateTokenCount(inputText)
    let outputTokens = estimateTokenCount(outputText)
    let thinkingTokens = thinkingText != nil ? estimateTokenCount(thinkingText!) : nil
    let responseTokens = outputTokens - (thinkingTokens ?? 0)

    // Calculate average tokens per second
    let averageTokensPerSecond = totalGenerationTime > 0 ?
        Double(outputTokens) / totalGenerationTime : 0

    // Determine completion status
    let completionStatus: MessageAnalytics.CompletionStatus =
        wasInterrupted ? .interrupted : .complete

    // Create generation parameters
    let generationParameters = MessageAnalytics.GenerationParameters(
        temperature: Double(options.temperature ?? 0.7),
        maxTokens: options.maxTokens ?? 10000,
        topP: nil,
        topK: nil
    )

    return MessageAnalytics(
        messageId: messageId,
        conversationId: conversationId,
        modelId: currentModel.id,
        modelName: modelName,
        framework: currentModel.compatibleFrameworks.first?.rawValue ?? "unknown",
        timestamp: startTime,
        timeToFirstToken: timeToFirstToken,
        totalGenerationTime: totalGenerationTime,
        thinkingTime: thinkingTime,
        responseTime: responseTime,
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        thinkingTokens: thinkingTokens,
        responseTokens: responseTokens,
        averageTokensPerSecond: averageTokensPerSecond,
        messageLength: outputText.count,
        wasThinkingMode: thinkingText != nil,
        wasInterrupted: wasInterrupted,
        retryCount: 0,
        completionStatus: completionStatus,
        tokensPerSecondHistory: tokensPerSecondHistory,
        generationMode: useStreaming ? .streaming : .nonStreaming,
        contextWindowUsage: 0.0,
        generationParameters: generationParameters
    )
}

// Token estimation helper
private func estimateTokenCount(_ text: String) -> Int {
    return Int(ceil(Double(text.count) / 4.0))
}
```

### 4.3 Conversation Analytics

```swift
public struct ConversationAnalytics: Codable {
    let conversationId: String
    let startTime: Date
    let endTime: Date?
    let messageCount: Int

    // Aggregate Metrics
    let averageTTFT: TimeInterval
    let averageGenerationSpeed: Double
    let totalTokensUsed: Int
    let modelsUsed: Set<String>

    // Efficiency Metrics
    let thinkingModeUsage: Double // percentage
    let completionRate: Double // successful / total
    let averageMessageLength: Int

    // Real-time Metrics
    let currentModel: String?
    let ongoingMetrics: MessageAnalytics?
}
```

#### Conversation Analytics Update

```swift
private func updateConversationAnalytics() {
    guard let conversation = currentConversation else { return }

    let analyticsMessages = messages.compactMap { $0.analytics }

    if !analyticsMessages.isEmpty {
        let averageTTFT = analyticsMessages.compactMap { $0.timeToFirstToken }.reduce(0, +) / Double(analyticsMessages.count)
        let averageGenerationSpeed = analyticsMessages.map { $0.averageTokensPerSecond }.reduce(0, +) / Double(analyticsMessages.count)
        let totalTokensUsed = analyticsMessages.reduce(0) { $0 + $1.inputTokens + $1.outputTokens }
        let modelsUsed = Set(analyticsMessages.map { $0.modelName })

        let thinkingMessages = analyticsMessages.filter { $0.wasThinkingMode }
        let thinkingModeUsage = Double(thinkingMessages.count) / Double(analyticsMessages.count)

        let completedMessages = analyticsMessages.filter { $0.completionStatus == .complete }
        let completionRate = Double(completedMessages.count) / Double(analyticsMessages.count)

        let averageMessageLength = analyticsMessages.reduce(0) { $0 + $1.messageLength } / analyticsMessages.count

        let conversationAnalytics = ConversationAnalytics(
            conversationId: conversation.id,
            startTime: conversation.createdAt,
            endTime: Date(),
            messageCount: messages.count,
            averageTTFT: averageTTFT,
            averageGenerationSpeed: averageGenerationSpeed,
            totalTokensUsed: totalTokensUsed,
            modelsUsed: modelsUsed,
            thinkingModeUsage: thinkingModeUsage,
            completionRate: completionRate,
            averageMessageLength: averageMessageLength,
            currentModel: loadedModelName,
            ongoingMetrics: nil
        )

        // Update conversation in store
        var updatedConversation = conversation
        updatedConversation.analytics = conversationAnalytics
        updatedConversation.performanceSummary = PerformanceSummary(from: messages)
        conversationStore.updateConversation(updatedConversation)
    }
}
```

### 4.4 Analytics Display

**File:** `examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Chat/ChatInterfaceView.swift`

#### Message-Level Analytics Display

```swift
// Display in message bubble footer
if let analytics = message.analytics {
    Group {
        // Response time
        Text("\(String(format: "%.1f", analytics.totalGenerationTime))s")

        Text("•")

        // Tokens per second
        if analytics.averageTokensPerSecond > 0 {
            Text("\(Int(analytics.averageTokensPerSecond)) tok/s")
        }

        // Thinking mode indicator
        if analytics.wasThinkingMode {
            Image(systemName: "lightbulb.min")
                .foregroundColor(.purple)
        }
    }
    .font(.caption2)
    .foregroundColor(.secondary)
}
```

#### Chat Details View (Analytics Dashboard)

```swift
struct ChatDetailsView: View {
    let messages: [Message]
    let conversation: Conversation?

    var body: some View {
        NavigationView {
            TabView {
                // Overview Tab
                ChatOverviewTab(messages: messages, conversation: conversation)
                    .tabItem { Label("Overview", systemImage: "chart.bar") }

                // Message Analytics Tab
                MessageAnalyticsTab(messages: messages)
                    .tabItem { Label("Messages", systemImage: "message") }

                // Performance Tab
                PerformanceTab(messages: messages)
                    .tabItem { Label("Performance", systemImage: "speedometer") }
            }
            .navigationTitle("Chat Analytics")
        }
    }
}
```

#### Performance Cards

```swift
PerformanceCard(
    title: "Avg Response Time",
    value: String(format: "%.1fs", averageResponseTime),
    icon: "timer",
    color: .green
)

PerformanceCard(
    title: "Avg Speed",
    value: "\(Int(averageTokensPerSecond)) tok/s",
    icon: "speedometer",
    color: .blue
)

PerformanceCard(
    title: "Total Tokens",
    value: "\(totalTokens)",
    icon: "textformat.123",
    color: .purple
)

PerformanceCard(
    title: "Success Rate",
    value: "\(Int(completionRate * 100))%",
    icon: "checkmark.circle",
    color: .orange
)
```

---

## 5. Data Models

### 5.1 Message Model

**File:** `examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Chat/ChatViewModel.swift`

```swift
public struct Message: Identifiable, Codable {
    public let id: UUID
    public let role: Role
    public let content: String
    public let thinkingContent: String?
    public let timestamp: Date

    // Analytics data
    public let analytics: MessageAnalytics?
    public let modelInfo: MessageModelInfo?

    public enum Role: String, Codable {
        case system
        case user
        case assistant
    }

    public init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        thinkingContent: String? = nil,
        timestamp: Date = Date(),
        analytics: MessageAnalytics? = nil,
        modelInfo: MessageModelInfo? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.thinkingContent = thinkingContent
        self.timestamp = timestamp
        self.analytics = analytics
        self.modelInfo = modelInfo
    }
}
```

### 5.2 Model Info

**File:** SDK Model

```swift
public struct MessageModelInfo: Codable {
    public let modelId: String
    public let modelName: String
    public let framework: String

    public init(from modelInfo: ModelInfo) {
        self.modelId = modelInfo.id
        self.modelName = modelInfo.name
        self.framework = modelInfo.compatibleFrameworks.first?.rawValue ?? "unknown"
    }
}
```

### 5.3 Conversation Model

**File:** `examples/ios/RunAnywhereAI/RunAnywhereAI/Core/Services/ConversationStore.swift`

```swift
struct Conversation: Identifiable, Codable {
    let id: String
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var messages: [Message]
    var modelName: String?
    var frameworkName: String?

    // Conversation-level analytics
    var analytics: ConversationAnalytics?
    var performanceSummary: PerformanceSummary?
}
```

### 5.4 SDK Message Model

**File:** `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Models/Conversation.swift`

```swift
public struct Message: Sendable {
    public let role: MessageRole
    public let content: String
    public let metadata: [String: String]?
    public let timestamp: Date

    public init(
        role: MessageRole,
        content: String,
        metadata: [String: String]? = nil,
        timestamp: Date = Date()
    ) {
        self.role = role
        self.content = content
        self.metadata = metadata
        self.timestamp = timestamp
    }
}

public enum MessageRole: String, Sendable {
    case system = "system"
    case user = "user"
    case assistant = "assistant"
}
```

### 5.5 Context Model

**File:** `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Models/Conversation.swift`

```swift
public struct Context: Sendable {
    public let systemPrompt: String?
    public let messages: [Message]
    public let maxMessages: Int
    public let metadata: [String: String]

    public init(
        systemPrompt: String? = nil,
        messages: [Message] = [],
        maxMessages: Int = 100,
        metadata: [String: String] = [:]
    ) {
        self.systemPrompt = systemPrompt
        self.messages = messages
        self.maxMessages = maxMessages
        self.metadata = metadata
    }
}
```

### 5.6 Generation Options

```swift
public struct RunAnywhereGenerationOptions {
    public var maxTokens: Int
    public var temperature: Float
    public var streamingEnabled: Bool

    public init(
        maxTokens: Int = 100,
        temperature: Float = 0.7,
        streamingEnabled: Bool = true
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.streamingEnabled = streamingEnabled
    }
}
```

---

## 6. Settings Integration

### 6.1 Settings Model

**File:** `examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Settings/SimplifiedSettingsView.swift`

```swift
@State private var defaultTemperature = 0.7
@State private var defaultMaxTokens = 10000
@State private var routingPolicy = RoutingPolicy.automatic
@State private var analyticsLogToLocal = false
```

### 6.2 Settings Persistence

```swift
private func updateSDKConfiguration() {
    // Save to UserDefaults for persistence
    UserDefaults.standard.set(routingPolicy.rawValue, forKey: "routingPolicy")
    UserDefaults.standard.set(defaultTemperature, forKey: "defaultTemperature")
    UserDefaults.standard.set(defaultMaxTokens, forKey: "defaultMaxTokens")
}

private func loadCurrentConfiguration() {
    // Load from UserDefaults
    if let policyRaw = UserDefaults.standard.string(forKey: "routingPolicy"),
       let policy = RoutingPolicy(rawValue: policyRaw) {
        routingPolicy = policy
    } else {
        routingPolicy = .automatic
    }

    defaultTemperature = UserDefaults.standard.double(forKey: "defaultTemperature")
    if defaultTemperature == 0 { defaultTemperature = 0.7 }

    defaultMaxTokens = UserDefaults.standard.integer(forKey: "defaultMaxTokens")
    if defaultMaxTokens == 0 { defaultMaxTokens = 10000 }

    // Load analytics setting from keychain
    analyticsLogToLocal = KeychainHelper.loadBool(key: "analyticsLogToLocal", defaultValue: false)
}
```

### 6.3 Settings Application

```swift
// In ChatViewModel.sendMessage()
let savedTemperature = UserDefaults.standard.double(forKey: "defaultTemperature")
let savedMaxTokens = UserDefaults.standard.integer(forKey: "defaultMaxTokens")

let effectiveSettings = (
    temperature: savedTemperature != 0 ? savedTemperature : 0.7,
    maxTokens: savedMaxTokens != 0 ? savedMaxTokens : 1000
)

let options = RunAnywhereGenerationOptions(
    maxTokens: effectiveSettings.maxTokens,
    temperature: Float(effectiveSettings.temperature)
)
```

### 6.4 Routing Policy

```swift
public enum RoutingPolicy: String, Codable {
    case automatic = "automatic"
    case deviceOnly = "deviceOnly"
    case preferDevice = "preferDevice"
    case preferCloud = "preferCloud"
}
```

---

## 7. State Management

### 7.1 ChatViewModel State

**File:** `examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Chat/ChatViewModel.swift`

```swift
@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var isGenerating = false
    @Published var currentInput = ""
    @Published var error: Error?
    @Published var isModelLoaded = false
    @Published var loadedModelName: String?
    @Published var useStreaming = true

    private let conversationStore = ConversationStore.shared
    private var generationTask: Task<Void, Never>?
    @Published var currentConversation: Conversation?

    var canSend: Bool {
        !currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isGenerating &&
        isModelLoaded
    }
}
```

### 7.2 ModelListViewModel State

**File:** `examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Models/ModelListViewModel.swift`

```swift
@MainActor
class ModelListViewModel: ObservableObject {
    static let shared = ModelListViewModel()

    @Published var availableModels: [ModelInfo] = []
    @Published var currentModel: ModelInfo?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var cancellables = Set<AnyCancellable>()
}
```

### 7.3 ConversationStore State

**File:** `examples/ios/RunAnywhereAI/RunAnywhereAI/Core/Services/ConversationStore.swift`

```swift
@MainActor
class ConversationStore: ObservableObject {
    static let shared = ConversationStore()

    @Published var conversations: [Conversation] = []
    @Published var currentConversation: Conversation?

    private let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    private let conversationsDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
}
```

### 7.4 Notification-Based Communication

```swift
// Model loaded notification
NotificationCenter.default.post(
    name: Notification.Name("ModelLoaded"),
    object: model
)

// Listen for model loaded
NotificationCenter.default.addObserver(
    self,
    selector: #selector(modelLoaded(_:)),
    name: Notification.Name("ModelLoaded"),
    object: nil
)

// Conversation selected notification
NotificationCenter.default.post(
    name: Notification.Name("ConversationSelected"),
    object: conversation
)

// Message content updated (during streaming)
NotificationCenter.default.post(
    name: Notification.Name("MessageContentUpdated"),
    object: nil
)
```

---

## 8. Error Handling

### 8.1 Error Types

```swift
enum ChatError: LocalizedError {
    case noModelLoaded

    var errorDescription: String? {
        switch self {
        case .noModelLoaded:
            return "❌ No model is loaded. Please select and load a model from the Models tab first."
        }
    }
}
```

### 8.2 SDK Errors

**File:** `sdk/runanywhere-swift/Sources/RunAnywhere/Components/llm/LLMComponent.swift`

```swift
public enum LLMServiceError: LocalizedError {
    case notInitialized
    case modelNotFound(String)
    case generationFailed(Error)
    case streamingNotSupported
    case contextLengthExceeded
    case invalidOptions

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "LLM service is not initialized"
        case .modelNotFound(let model):
            return "Model not found: \(model)"
        case .generationFailed(let error):
            return "Generation failed: \(error.localizedDescription)"
        case .streamingNotSupported:
            return "Streaming generation is not supported"
        case .contextLengthExceeded:
            return "Context length exceeded"
        case .invalidOptions:
            return "Invalid generation options"
        }
    }
}
```

### 8.3 Error Handling in Generation

```swift
do {
    // Attempt generation
    if useStreaming {
        await handleStreamingGeneration(prompt, options, messageIndex)
    } else {
        await handleNonStreamingGeneration(prompt, options, messageIndex)
    }
} catch {
    await MainActor.run {
        self.error = error

        // Add error message to chat
        if messageIndex < self.messages.count {
            let errorMessage: String
            if error is ChatError {
                errorMessage = error.localizedDescription
            } else {
                errorMessage = "❌ Generation failed: \(error.localizedDescription)"
            }
            let currentMessage = self.messages[messageIndex]
            let updatedMessage = Message(
                role: currentMessage.role,
                content: errorMessage,
                timestamp: currentMessage.timestamp
            )
            self.messages[messageIndex] = updatedMessage
        }
    }
}
```

### 8.4 Model Loading Error Handling

```swift
func selectModel(_ model: ModelInfo) async {
    do {
        try await loadModel(model)
        setCurrentModel(model)

        // Post notification that model was loaded
        await MainActor.run {
            NotificationCenter.default.post(
                name: Notification.Name("ModelLoaded"),
                object: model
            )
        }
    } catch {
        errorMessage = "Failed to load model: \(error.localizedDescription)"
        // Don't set currentModel if loading failed
    }
}
```

---

## 9. Critical Dependencies

### 9.1 Minimum Required Frameworks

**For Text-to-Text Generation:**

1. **LLMSwift** - LLM inference via llama.cpp
2. **RunAnywhere SDK Core** - SDK infrastructure
3. **Foundation** - Core Swift framework

**Optional (for enhanced features):**

4. **WhisperKit** - For voice-to-text (not required for text-to-text)
5. **FluidAudioDiarization** - For speaker detection (not required for text-to-text)

### 9.2 SDK Components Required

**File:** `sdk/runanywhere-swift/Sources/RunAnywhere/Components/llm/LLMComponent.swift`

```swift
/// Language Model component
@MainActor
public final class LLMComponent: BaseComponent<LLMServiceWrapper> {
    public override class var componentType: SDKComponent { .llm }

    private let llmConfiguration: LLMConfiguration
    private var conversationContext: Context?
    private var isModelLoaded = false
    private var modelPath: String?
}
```

#### LLM Configuration

```swift
public struct LLMConfiguration: ComponentConfiguration {
    public var componentType: SDKComponent { .llm }

    public let modelId: String?
    public let contextLength: Int
    public let useGPUIfAvailable: Bool
    public let quantizationLevel: QuantizationLevel?
    public let cacheSize: Int
    public let preloadContext: String?

    public let temperature: Double
    public let maxTokens: Int
    public let systemPrompt: String?
    public let streamingEnabled: Bool
}
```

### 9.3 Service Container

**File:** `sdk/runanywhere-swift/Sources/RunAnywhere/Public/RunAnywhere.swift`

```swift
internal static var serviceContainer: ServiceContainer {
    ServiceContainer.shared
}

// Required services:
- generationService: GenerationService
- streamingService: StreamingService
- modelLoadingService: ModelLoadingService
- modelRegistry: ModelRegistry
- authenticationService: AuthenticationService (optional in dev mode)
```

### 9.4 Initialization Order

1. SDK Core Initialization
2. Register LLM Framework Adapters
3. Register Models (lazy loading)
4. User selects model
5. Model download (if needed)
6. Model loading
7. Generation ready

---

## 10. Implementation Checklist

### 10.1 Phase 1: SDK Setup

- [ ] Initialize RunAnywhere SDK
- [ ] Register LLMSwift adapter
- [ ] Register model catalog
- [ ] Implement lazy device registration
- [ ] Test SDK initialization (< 100ms)

### 10.2 Phase 2: Model Management

- [ ] Implement model discovery (availableModels)
- [ ] Implement model download with progress
- [ ] Implement model loading
- [ ] Implement model selection UI
- [ ] Handle download errors
- [ ] Handle loading errors
- [ ] Post model loaded notifications

### 10.3 Phase 3: Message Flow

- [ ] Create Message data model
- [ ] Implement ChatViewModel
- [ ] Implement message list UI
- [ ] Implement input field
- [ ] Implement send button logic
- [ ] Handle empty state
- [ ] Handle loading state

### 10.4 Phase 4: Generation

- [ ] Implement non-streaming generation
- [ ] Implement streaming generation
- [ ] Handle thinking mode tags
- [ ] Update UI during streaming
- [ ] Handle generation errors
- [ ] Implement stop generation
- [ ] Test with various prompts

### 10.5 Phase 5: Analytics

- [ ] Implement MessageAnalytics model
- [ ] Collect timing metrics (TTFT, total time)
- [ ] Collect token metrics (input/output tokens)
- [ ] Calculate tokens per second
- [ ] Track thinking mode usage
- [ ] Attach analytics to messages
- [ ] Implement ConversationAnalytics
- [ ] Update conversation-level analytics

### 10.6 Phase 6: Analytics Display

- [ ] Display timing in message footer
- [ ] Display tokens per second
- [ ] Show thinking mode indicator
- [ ] Implement Chat Details view
- [ ] Implement Overview tab
- [ ] Implement Message Analytics tab
- [ ] Implement Performance tab
- [ ] Create performance cards
- [ ] Format metrics for display

### 10.7 Phase 7: Settings

- [ ] Implement Settings UI
- [ ] Add temperature slider
- [ ] Add max tokens control
- [ ] Persist settings to UserDefaults
- [ ] Load settings on app launch
- [ ] Apply settings to generation options
- [ ] Test settings persistence

### 10.8 Phase 8: Conversation Management

- [ ] Implement Conversation model
- [ ] Implement ConversationStore
- [ ] Persist conversations to disk
- [ ] Load conversations on app launch
- [ ] Implement conversation list UI
- [ ] Implement conversation selection
- [ ] Implement conversation deletion
- [ ] Auto-generate conversation titles
- [ ] Attach analytics to conversations

### 10.9 Phase 9: Error Handling

- [ ] Define error types
- [ ] Handle no model loaded error
- [ ] Handle generation errors
- [ ] Handle download errors
- [ ] Handle loading errors
- [ ] Display errors in UI
- [ ] Implement retry logic
- [ ] Test all error scenarios

### 10.10 Phase 10: Testing & Optimization

- [ ] Test with smallest model (SmolLM2 360M)
- [ ] Test with largest model (SmolLM2 1.7B)
- [ ] Test streaming performance
- [ ] Test non-streaming performance
- [ ] Test thinking mode models
- [ ] Test conversation persistence
- [ ] Test analytics accuracy
- [ ] Optimize memory usage
- [ ] Profile generation performance
- [ ] Test on low-end devices

---

## Key Implementation Notes

### Must-Have Features

1. **Lazy Initialization:** SDK initializes fast (< 100ms), no network calls
2. **Lazy Model Loading:** Models are NOT auto-downloaded
3. **Streaming Support:** Real-time token display during generation
4. **Thinking Mode:** Support for models with `<think>` tags
5. **Analytics:** Comprehensive metrics collection and display
6. **Settings Persistence:** Temperature and maxTokens saved to UserDefaults
7. **Conversation Persistence:** Full conversation history saved to disk
8. **Error Handling:** Graceful error handling with user-friendly messages

### Performance Targets

- **Initialization:** < 100ms
- **Model Discovery:** < 500ms
- **Model Loading:** Depends on model size (1-3s typical)
- **Time to First Token:** < 1s (depends on model)
- **Tokens Per Second:** 10-50 tokens/s (depends on device and model)

### Critical Paths

1. **App Launch → SDK Ready:** < 100ms
2. **Model Selection → Model Loaded:** 1-3s
3. **User Message → First Token:** < 1s
4. **Streaming Token Rate:** 10-50 tokens/s
5. **Analytics Collection:** Real-time during generation

### Android-Specific Considerations

1. **Use Kotlin Coroutines:** Replace Swift async/await with coroutines
2. **Use StateFlow/LiveData:** Replace @Published with StateFlow
3. **Use Room Database:** Replace file-based persistence with Room
4. **Use Jetpack Compose:** Replace SwiftUI with Compose
5. **Use Navigation Component:** Replace SwiftUI navigation
6. **Use DataStore:** Replace UserDefaults with DataStore Preferences
7. **Use ViewModel:** Maintain state across configuration changes
8. **Handle Lifecycle:** Properly handle Android lifecycle events

---

## Appendix A: Code Flow Diagram

```
App Launch
    ↓
SDK Initialize (< 100ms)
    ↓
Register Adapters
    ↓
Register Models (lazy)
    ↓
[User Action: Select Model]
    ↓
Download Model (if needed)
    ↓
Load Model
    ↓
Post "ModelLoaded" Notification
    ↓
[User Action: Type Message]
    ↓
sendMessage()
    ↓
Add User Message
    ↓
Create Assistant Placeholder
    ↓
Get Settings (temp, maxTokens)
    ↓
Start Generation Task
    ↓
[If Streaming]
    ↓
Stream Tokens
    ↓
Parse Thinking Tags
    ↓
Update UI (real-time)
    ↓
Collect Analytics
    ↓
[End Streaming]
    ↓
Attach Analytics to Message
    ↓
Update Conversation Analytics
    ↓
Save Conversation to Disk
    ↓
Update UI (final)
```

---

## Appendix B: Key Files Reference

| Component | File Path |
|-----------|-----------|
| App Entry | `examples/ios/RunAnywhereAI/RunAnywhereAI/App/RunAnywhereAIApp.swift` |
| SDK Public API | `sdk/runanywhere-swift/Sources/RunAnywhere/Public/RunAnywhere.swift` |
| LLM Component | `sdk/runanywhere-swift/Sources/RunAnywhere/Components/llm/LLMComponent.swift` |
| Chat ViewModel | `examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Chat/ChatViewModel.swift` |
| Chat View | `examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Chat/ChatInterfaceView.swift` |
| Model ViewModel | `examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Models/ModelListViewModel.swift` |
| Models View | `examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Models/SimplifiedModelsView.swift` |
| Settings View | `examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Settings/SimplifiedSettingsView.swift` |
| Conversation Store | `examples/ios/RunAnywhereAI/RunAnywhereAI/Core/Services/ConversationStore.swift` |
| SDK Models | `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Models/Conversation.swift` |

---

## Appendix C: Kotlin Translation Guide

### Swift → Kotlin Quick Reference

| Swift | Kotlin |
|-------|--------|
| `async/await` | `suspend fun` + coroutines |
| `@Published` | `StateFlow` / `MutableStateFlow` |
| `@StateObject` | `viewModel()` in Compose |
| `@ObservedObject` | `collectAsState()` in Compose |
| `Task { }` | `viewModelScope.launch { }` |
| `AsyncThrowingStream` | `Flow<T>` |
| `NotificationCenter` | `SharedFlow` / `EventBus` |
| `UserDefaults` | `DataStore Preferences` |
| File persistence | `Room Database` |
| `@MainActor` | `Dispatchers.Main` |
| SwiftUI | Jetpack Compose |

### Example Translation

**Swift:**
```swift
@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var isGenerating = false

    func sendMessage() async {
        isGenerating = true
        let result = try await RunAnywhere.generate(prompt)
        messages.append(result)
        isGenerating = false
    }
}
```

**Kotlin:**
```kotlin
@HiltViewModel
class ChatViewModel @Inject constructor(
    private val runAnywhere: RunAnywhere
) : ViewModel() {
    private val _messages = MutableStateFlow<List<Message>>(emptyList())
    val messages: StateFlow<List<Message>> = _messages.asStateFlow()

    private val _isGenerating = MutableStateFlow(false)
    val isGenerating: StateFlow<Boolean> = _isGenerating.asStateFlow()

    fun sendMessage(prompt: String) {
        viewModelScope.launch {
            _isGenerating.value = true
            val result = runAnywhere.generate(prompt)
            _messages.value = _messages.value + result
            _isGenerating.value = false
        }
    }
}
```

---

**End of Technical Specification**

This document serves as the definitive reference for implementing text-to-text generation in the Android SDK with full parity to the iOS Swift implementation.
