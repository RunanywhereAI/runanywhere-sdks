@file:JvmName("RunAnywhereExtensions")

package com.runanywhere.sdk.public.extensions

/**
 * Central import file for all RunAnywhere SDK extensions
 * This file provides access to all extension functionality matching iOS modular design
 *
 * Extensions included:
 * - Configuration Management (RunAnywhere+Configuration.swift equivalent)
 * - Voice Operations (RunAnywhere+Voice.swift equivalent)
 * - Model Management (RunAnywhere+ModelManagement.swift equivalent)
 * - Component Management (RunAnywhere+Components.swift equivalent)
 * - Pipeline Management (RunAnywhere+Pipelines.swift equivalent)
 * - Structured Output Generation
 * - Cost Tracking and Analytics
 * - Conversation Factory and Session Management
 * - Enhanced Event System
 */

// MARK: - Public API Summary

/*

 ## Configuration Management Extensions
 ```kotlin
 // Get and update configuration settings
 val settings = RunAnywhere.getCurrentGenerationSettings()
 val policy = RunAnywhere.getCurrentRoutingPolicy()
 RunAnywhere.updateRoutingPolicy(newPolicy)
 RunAnywhere.syncUserPreferences()
 ```

 ## Voice Operations Extensions
 ```kotlin
 // Rich voice transcription
 val result = RunAnywhere.transcribe(
     audio = audioData,
     modelId = "whisper-large",
     options = STTOptions(language = "en", enableVAD = true)
 )

 // Voice conversation pipeline
 val conversationFlow = RunAnywhere.createVoiceConversation(
     sttModelId = "whisper-base",
     llmModelId = "llama3-8b",
     ttsVoice = "neural-voice"
 )
 ```

 ## Model Management Extensions
 ```kotlin
 // Enhanced model operations
 val modelInfo = RunAnywhere.loadModelWithInfo("gpt-4")
 val models = RunAnywhere.listAvailableModels(
     options = ModelSearchOptions(
         capabilities = listOf(ModelCapability.CONVERSATION),
         maxSize = 10_000_000_000L // 10GB
     )
 )

 // Download with progress tracking
 RunAnywhere.downloadModel("llama3-70b").collect { progress ->
     println("Download progress: ${progress.progress * 100}% (${progress.speed} bytes/s)")
 }
 ```

 ## Structured Output Generation
 ```kotlin
 // Type-safe structured generation
 val analysis = RunAnywhere.generateStructured<SentimentAnalysis>(
     prompt = "Analyze the sentiment of: 'I love this product!'",
     options = StructuredGenerationOptions(
         validationMode = SchemaValidationMode.STRICT,
         retryOnInvalidSchema = true
     )
 )

 // Built-in analysis methods
 val classification = RunAnywhere.classifyText(
     text = "This is a technical document about machine learning",
     categories = listOf("Technical", "Marketing", "Legal", "Personal")
 )
 ```

 ## Cost Tracking and Analytics
 ```kotlin
 // Enable real-time cost tracking
 RunAnywhere.enableCostTracking(
     CostTrackingConfig(
         trackTokenCosts = true,
         trackSavings = true,
         enableBudgetAlerts = true
     )
 )

 // Monitor costs and savings
 RunAnywhere.getCostStream().collect { costInfo ->
     println("Cost: $${costInfo.totalCost}, Savings: $${costInfo.savingsAmount}")
 }

 // Set budget alerts
 RunAnywhere.setCostBudget(
     amount = 100.0f,
     period = CostBudget.BudgetPeriod.MONTHLY,
     alertThresholds = listOf(0.5f, 0.8f, 0.9f)
 )
 ```

 ## Pipeline Management
 ```kotlin
 // Use pre-built pipeline templates
 val voicePipeline = PipelineTemplates.voiceConversation(
     sttModelId = "whisper-base",
     llmModelId = "llama3-8b",
     ttsVoice = "neural-voice"
 )

 RunAnywhere.createPipeline(voicePipeline)

 // Execute with real-time events
 RunAnywhere.executePipelineStream(
     pipelineId = "voice_conversation",
     inputs = mapOf("audioData" to audioBytes)
 ).collect { event ->
     when (event) {
         is PipelineEvent.StageCompleted -> println("Stage completed: ${event.stageResult}")
         is PipelineEvent.PipelineComplete -> println("Pipeline finished")
     }
 }
 ```

 ## Component Management with Priorities
 ```kotlin
 // Initialize components with dependencies and priorities
 val componentConfigs = listOf(
     RunAnywhere.createDefaultComponentConfig(SDKComponent.LLM, "llama3-8b"),
     RunAnywhere.createDefaultComponentConfig(SDKComponent.STT, "whisper-large"),
     RunAnywhere.createDefaultComponentConfig(SDKComponent.TTS, "neural-voice")
 )

 val results = RunAnywhere.initializeComponents(componentConfigs)

 // Monitor component health
 val healthStatus = RunAnywhere.healthCheckAllComponents()
 RunAnywhere.getComponentManagementStream().collect { event ->
     when (event) {
         is ComponentManagementEvent.ComponentFailed -> {
             // Auto-restart failed components
             RunAnywhere.restartComponent(event.componentType, "Health check failure")
         }
     }
 }
 ```

 ## Conversation Factory and Session Management
 ```kotlin
 // Create different conversation types
 val chatSession = RunAnywhere.createChatConversation(
     systemPrompt = "You are a helpful AI assistant",
     enableMemory = true
 )

 val roleplaySession = RunAnywhere.createRoleplayConversation(
     characterName = "Sherlock Holmes",
     characterPersonality = "Brilliant detective with keen observation skills",
     scenario = "Investigating a mysterious case"
 )

 // Manage conversation turns
 val (userTurn, aiTurn) = RunAnywhere.sendMessageAndGetResponse(
     sessionId = chatSession.sessionId,
     message = "Hello, how are you today?"
 )

 // Get conversation insights
 val summary = RunAnywhere.summarizeConversation(
     sessionId = chatSession.sessionId,
     summaryType = SummaryType.COMPREHENSIVE
 )
 ```

 ## Enhanced Event System
 ```kotlin
 // Subscribe to typed events with filtering
 EnhancedEventBus.subscribe<EnhancedSDKGenerationEvent.Completed> { event ->
     println("Generation completed: ${event.result} (${event.tokensUsed} tokens, $${event.cost})")
 }

 // Monitor progress across all operations
 EnhancedEventBus.subscribeToProgress().collect { progressEvent ->
     println("${progressEvent.stage}: ${progressEvent.progress * 100}% - ${progressEvent.details}")
 }

 // Session-specific event monitoring
 EnhancedEventBus.subscribeToSession(sessionId).collect { event ->
     // Handle events for specific session
 }
 ```

 */

// MARK: - Extension Organization Summary

/**
 * Configuration Extensions (RunAnywhereConfiguration.kt)
 * - getCurrentGenerationSettings()
 * - getCurrentRoutingPolicy() / updateRoutingPolicy()
 * - getUserPreferences() / updateUserPreferences()
 * - syncUserPreferences()
 * - resetToDefaults()
 */

/**
 * Voice Extensions (RunAnywhereVoice.kt)
 * - transcribe() with rich options and results
 * - createVoiceConversation()
 * - processVoiceTurn()
 * - transcribeStream()
 * - detectVoiceActivity()
 * - getAvailableTTSVoices() / getAvailableSTTLanguages()
 */

/**
 * Model Management Extensions (RunAnywhereModelManagement.kt)
 * - loadModelWithInfo() / unloadModel()
 * - listAvailableModels() with filtering
 * - downloadModel() with progress tracking
 * - deleteModel() / addModelFromURL()
 * - getCurrentModel() / getModelStorageUsage()
 * - cleanupUnusedModels()
 */

/**
 * Structured Output Extensions (RunAnywhereStructuredOutput.kt)
 * - generateStructured<T>() with validation
 * - generateStructuredStream<T>()
 * - validateStructuredOutput<T>()
 * - Convenience methods: classifyText(), analyzeSentiment(), extractInformation(), summarizeContent()
 */

/**
 * Cost Tracking Extensions (RunAnywhereCostTracking.kt)
 * - enableCostTracking() / disableCostTracking()
 * - getCostStream() / getSavingsStream()
 * - getCostStatistics() / setCostBudget()
 * - estimateCost() / compareCosts()
 * - exportCostData()
 */

/**
 * Pipeline Extensions (RunAnywherePipelines.kt)
 * - createPipeline() / executePipeline()
 * - executePipelineStream() with real-time events
 * - PipelineTemplates for common workflows
 * - validatePipeline() / clonePipeline()
 * - getAvailablePipelines()
 */

/**
 * Component Management Extensions (RunAnywhereComponents.kt)
 * - initializeComponents() with priorities
 * - getComponentStatus() / getAllComponentStatuses()
 * - healthCheckComponent() / healthCheckAllComponents()
 * - restartComponent() / setComponentAutoRestart()
 * - createDefaultComponentConfig()
 */

/**
 * Conversation Extensions (RunAnywhereConversations.kt)
 * - createConversation() / createChatConversation() / createVoiceConversation()
 * - sendMessage() / sendMessageAndGetResponse()
 * - conversationStream() / getConversationHistory()
 * - summarizeConversation() / endConversation()
 * - pauseConversation() / resumeConversation()
 */

/**
 * Enhanced Event System (EnhancedEventBus.kt)
 * - Comprehensive typed events for all operations
 * - Progress tracking across all components
 * - Session-specific event filtering
 * - Cost and performance event monitoring
 */

// MARK: - Usage Patterns

/**
 * ## Complete Voice Assistant Setup
 * ```kotlin
 * // 1. Initialize SDK
 * RunAnywhere.initialize(apiKey, environment = SDKEnvironment.PRODUCTION)
 *
 * // 2. Configure components with priorities
 * val configs = listOf(
 *     RunAnywhere.createDefaultComponentConfig(SDKComponent.VAD),
 *     RunAnywhere.createDefaultComponentConfig(SDKComponent.STT, "whisper-large"),
 *     RunAnywhere.createDefaultComponentConfig(SDKComponent.LLM, "llama3-70b"),
 *     RunAnywhere.createDefaultComponentConfig(SDKComponent.TTS, "neural-voice")
 * )
 *
 * RunAnywhere.initializeComponents(configs)
 *
 * // 3. Enable cost tracking
 * RunAnywhere.enableCostTracking(CostTrackingConfig(
 *     trackSavings = true,
 *     enableBudgetAlerts = true
 * ))
 *
 * // 4. Create and execute voice pipeline
 * val pipeline = PipelineTemplates.voiceConversation(
 *     sttModelId = "whisper-large",
 *     llmModelId = "llama3-70b",
 *     ttsVoice = "neural-voice"
 * )
 *
 * RunAnywhere.createPipeline(pipeline)
 *
 * // 5. Process voice input
 * val result = RunAnywhere.executePipeline(
 *     pipelineId = "voice_conversation",
 *     inputs = mapOf("audioData" to audioBytes)
 * )
 * ```
 */

// MARK: - Import All Extensions

// This ensures all extension methods are available when importing this file
// Import all extension files to make them available
// Note: In Kotlin, extension functions are automatically available when their containing files are in the classpath
