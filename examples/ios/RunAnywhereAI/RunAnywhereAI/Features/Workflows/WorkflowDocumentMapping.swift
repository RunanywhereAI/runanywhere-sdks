//
//  WorkflowDocumentMapping.swift
//  RunAnywhereAI
//
//  Translation between WorkflowGraph and the SDK's RAWorkflowDocument. The one
//  place that knows both shapes: adding a node type touches the palette, the
//  inspector, and this file, and nothing else.
//

import Foundation
import RunAnywhere

enum WorkflowDocumentMapping {
    static func document(
        id: String,
        name: String,
        graph: WorkflowGraph,
        createdAtMs: Int64
    ) -> RAWorkflowDocument {
        var document = RAWorkflowDocument()
        document.id = id
        document.name = name
        document.createdAtMs = createdAtMs
        document.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        document.nodes = graph.nodes.map(wireNode)
        document.edges = graph.edges.map { edge in
            var wire = RAWorkflowEdge()
            wire.fromNode = edge.fromNode
            wire.fromPort = edge.fromPort.rawValue
            wire.toNode = edge.toNode
            wire.toPort = edge.toPort
            return wire
        }
        return document
    }

    static func graph(from document: RAWorkflowDocument) -> WorkflowGraph {
        var graph = WorkflowGraph()
        graph.nodes = document.nodes.compactMap(node)
        graph.edges = document.edges.compactMap { wire in
            guard let port = WorkflowOutputPort(rawValue: wire.fromPort) else { return nil }
            return WorkflowEdge(
                fromNode: wire.fromNode,
                fromPort: port,
                toNode: wire.toNode,
                toPort: wire.toPort.isEmpty ? WorkflowInputPort.flowName : wire.toPort
            )
        }
        return graph
    }

    // MARK: - Graph → proto

    private static func wireNode(_ node: WorkflowNode) -> RAWorkflowNode {
        var wire = RAWorkflowNode()
        wire.id = node.id
        wire.name = node.name

        var position = RANodePosition()
        position.x = Float(node.position.x)
        position.y = Float(node.position.y)
        wire.position = position
        wire.config = config(of: node)
        return wire
    }

    // One switch over every kind, so a new proto arm cannot be added without
    // being serialized. The complexity gate is written for branching logic,
    // not for a translation table.
    // swiftlint:disable:next cyclomatic_complexity
    private static func config(of node: WorkflowNode) -> RAWorkflowNode.OneOf_Config {
        let settings = node.settings
        switch node.kind {
        case .manualTrigger: return .manualTrigger(manualTrigger(settings))
        case .scheduleTrigger: return .scheduleTrigger(scheduleTrigger(settings))
        case .llmGenerate: return .llmGenerate(llmGenerate(settings))
        case .llmStructured: return .llmStructured(llmStructured(settings))
        case .vision: return .vision(vision(settings))
        case .embed: return .embed(embed(settings))
        case .rerank: return .rerank(rerank(settings))
        case .transcribe: return .transcribe(transcribe(settings))
        case .speak: return .speak(speak(settings))
        case .detectVoice: return .detectVoice(detectVoice(settings))
        case .diarize: return .diarize(diarize(settings))
        case .segment: return .segment(segment(settings))
        case .ragQuery: return .ragQuery(ragQuery(settings))
        case .ragIngest: return .ragIngest(ragIngest(settings))
        case .loadModel: return .loadModel(loadModel(settings))
        case .condition: return .condition(condition(settings))
        case .filter: return .filter(filter(settings))
        case .loopOverItems: return .loopOverItems(loop(settings))
        case .code: return .code(code(settings))
        case .setTransform: return .setTransform(setTransform(settings))
        case .merge: return .merge(merge(settings))
        case .splitOut: return .splitOut(splitOut(settings))
        case .aggregate: return .aggregate(aggregate(settings))
        case .wait: return .wait(wait(settings))
        case .toolCall: return .toolCall(toolCall(settings))
        case .httpRequest: return .httpRequest(httpRequest(settings))
        case .fileRead: return .fileRead(fileRead(settings))
        case .fileWrite: return .fileWrite(fileWrite(settings))
        case .packNode: return .packNode(packNode(settings))
        }
    }

    private static func manualTrigger(_ settings: WorkflowNodeSettings) -> RAManualTriggerConfig {
        var config = RAManualTriggerConfig()
        config.initialItemsJson = settings.triggerItemsJSON
        return config
    }

    private static func scheduleTrigger(_ settings: WorkflowNodeSettings) -> RAScheduleTriggerConfig {
        var config = RAScheduleTriggerConfig()
        config.kind = settings.scheduleKind
        config.intervalSeconds = UInt32(max(0, settings.scheduleIntervalSeconds))
        config.hour = UInt32(min(23, max(0, settings.scheduleHour)))
        config.minute = UInt32(min(59, max(0, settings.scheduleMinute)))
        config.cron = settings.scheduleCron
        config.initialItemsJson = settings.triggerItemsJSON
        return config
    }

    private static func llmGenerate(_ settings: WorkflowNodeSettings) -> RALlmGenerateConfig {
        var config = RALlmGenerateConfig()
        config.prompt = settings.prompt
        if !settings.systemPrompt.isEmpty { config.systemPrompt = settings.systemPrompt }
        if !settings.modelID.isEmpty { config.modelID = settings.modelID }
        if let options = generation(settings) { config.generation = options }
        return config
    }

    private static func llmStructured(_ settings: WorkflowNodeSettings) -> RALlmStructuredConfig {
        var config = RALlmStructuredConfig()
        config.prompt = settings.prompt
        config.jsonSchema = settings.jsonSchema
        if !settings.systemPrompt.isEmpty { config.systemPrompt = settings.systemPrompt }
        if !settings.modelID.isEmpty { config.modelID = settings.modelID }
        if let options = generation(settings) { config.generation = options }
        return config
    }

    private static func vision(_ settings: WorkflowNodeSettings) -> RAVisionConfig {
        var config = RAVisionConfig()
        config.prompt = settings.prompt
        config.binaryKey = settings.binaryKey
        if !settings.modelID.isEmpty { config.modelID = settings.modelID }
        if let options = generation(settings) { config.generation = options }
        return config
    }

    private static func embed(_ settings: WorkflowNodeSettings) -> RAEmbedConfig {
        var config = RAEmbedConfig()
        config.text = settings.textInput
        if !settings.modelID.isEmpty { config.modelID = settings.modelID }
        return config
    }

    private static func rerank(_ settings: WorkflowNodeSettings) -> RARerankConfig {
        var config = RARerankConfig()
        config.query = settings.rerankQuery
        config.documents = settings.rerankDocuments
        config.topN = UInt32(max(0, settings.rerankTopN))
        if !settings.modelID.isEmpty { config.modelID = settings.modelID }
        return config
    }

    private static func transcribe(_ settings: WorkflowNodeSettings) -> RATranscribeConfig {
        var config = RATranscribeConfig()
        config.binaryKey = settings.binaryKey
        if !settings.modelID.isEmpty { config.modelID = settings.modelID }
        if !settings.language.isEmpty { config.language = settings.language }
        return config
    }

    private static func speak(_ settings: WorkflowNodeSettings) -> RASpeakConfig {
        var config = RASpeakConfig()
        config.text = settings.textInput
        config.binaryKey = settings.binaryKey
        if !settings.modelID.isEmpty { config.modelID = settings.modelID }
        if !settings.voice.isEmpty { config.voice = settings.voice }
        return config
    }

    private static func detectVoice(_ settings: WorkflowNodeSettings) -> RADetectVoiceConfig {
        var config = RADetectVoiceConfig()
        config.binaryKey = settings.binaryKey
        if let threshold = settings.vadThreshold { config.threshold = Float(threshold) }
        return config
    }

    private static func diarize(_ settings: WorkflowNodeSettings) -> RADiarizeConfig {
        var config = RADiarizeConfig()
        config.binaryKey = settings.binaryKey
        if !settings.modelID.isEmpty { config.modelID = settings.modelID }
        if let speakers = settings.speakerCount { config.speakerCount = UInt32(max(0, speakers)) }
        return config
    }

    private static func segment(_ settings: WorkflowNodeSettings) -> RASegmentConfig {
        var config = RASegmentConfig()
        config.text = settings.textInput
        if !settings.modelID.isEmpty { config.modelID = settings.modelID }
        return config
    }

    private static func ragQuery(_ settings: WorkflowNodeSettings) -> RARagQueryConfig {
        var config = RARagQueryConfig()
        config.question = settings.ragQuestion
        config.embeddingModelID = settings.embeddingModelID
        config.llmModelID = settings.ragLLMModelID
        config.topK = UInt32(max(0, settings.ragTopK))
        return config
    }

    private static func ragIngest(_ settings: WorkflowNodeSettings) -> RARagIngestConfig {
        var config = RARagIngestConfig()
        config.text = settings.textInput
        config.embeddingModelID = settings.embeddingModelID
        config.llmModelID = settings.ragLLMModelID
        config.documentID = settings.documentID
        return config
    }

    private static func loadModel(_ settings: WorkflowNodeSettings) -> RALoadModelConfig {
        var config = RALoadModelConfig()
        config.modelID = settings.modelID
        if let category = settings.loadCategory { config.category = category }
        return config
    }

    private static func condition(_ settings: WorkflowNodeSettings) -> RAConditionConfig {
        var config = RAConditionConfig()
        config.left = settings.conditionLeft
        config.operator = settings.conditionOperator
        config.right = settings.conditionRight
        return config
    }

    private static func filter(_ settings: WorkflowNodeSettings) -> RAFilterConfig {
        var config = RAFilterConfig()
        config.left = settings.conditionLeft
        config.operator = settings.conditionOperator
        config.right = settings.conditionRight
        return config
    }

    private static func loop(_ settings: WorkflowNodeSettings) -> RALoopOverItemsConfig {
        var config = RALoopOverItemsConfig()
        config.items = settings.loopItems
        config.bodyNodeIds = settings.loopBodyNodeIDs
        config.maxIterations = UInt32(max(0, settings.loopMaxIterations))
        return config
    }

    private static func code(_ settings: WorkflowNodeSettings) -> RACodeConfig {
        var config = RACodeConfig()
        config.source = settings.codeSource
        return config
    }

    private static func setTransform(_ settings: WorkflowNodeSettings) -> RASetTransformConfig {
        var config = RASetTransformConfig()
        config.assignments = settings.assignments.map { row in
            var assignment = RAFieldAssignment()
            assignment.field = row.key
            assignment.value = row.value
            return assignment
        }
        config.keepOnlyAssigned = settings.keepOnlyAssigned
        return config
    }

    private static func merge(_ settings: WorkflowNodeSettings) -> RAMergeConfig {
        var config = RAMergeConfig()
        config.inputCount = UInt32(max(1, settings.mergeInputCount))
        config.deduplicate = settings.mergeDeduplicate
        return config
    }

    private static func splitOut(_ settings: WorkflowNodeSettings) -> RASplitOutConfig {
        var config = RASplitOutConfig()
        config.field = settings.fieldPath
        return config
    }

    private static func aggregate(_ settings: WorkflowNodeSettings) -> RAAggregateConfig {
        var config = RAAggregateConfig()
        config.field = settings.fieldPath
        return config
    }

    private static func wait(_ settings: WorkflowNodeSettings) -> RAWaitConfig {
        var config = RAWaitConfig()
        config.seconds = UInt32(max(0, settings.waitSeconds))
        return config
    }

    private static func toolCall(_ settings: WorkflowNodeSettings) -> RAToolCallConfig {
        var config = RAToolCallConfig()
        config.toolName = settings.toolName
        config.arguments = dictionary(from: settings.toolArguments)
        config.ports = settings.toolPorts.map(\.wire)
        return config
    }

    private static func packNode(_ settings: WorkflowNodeSettings) -> RAPackNodeConfig {
        var config = RAPackNodeConfig()
        config.packID = settings.packID
        config.arguments = dictionary(from: settings.toolArguments)
        config.ports = settings.toolPorts.map(\.wire)
        config.outputs = settings.packOutputs
        config.missing = settings.packMissing
        return config
    }

    private static func httpRequest(_ settings: WorkflowNodeSettings) -> RAHttpRequestConfig {
        var config = RAHttpRequestConfig()
        config.method = settings.httpMethod
        config.url = settings.httpURL
        config.headers = dictionary(from: settings.httpHeaders)
        if !settings.httpBody.isEmpty { config.body = settings.httpBody }
        if settings.httpTimeoutMs > 0 { config.timeoutMs = UInt32(settings.httpTimeoutMs) }
        if settings.httpAuthEnabled {
            var auth = RAHttpAuth()
            auth.kind = settings.httpAuthKind
            auth.secret = settings.httpAuthSecret
            auth.name = settings.httpAuthName
            config.auth = auth
        }
        return config
    }

    private static func fileRead(_ settings: WorkflowNodeSettings) -> RAFileReadConfig {
        var config = RAFileReadConfig()
        config.path = settings.filePath
        config.binary = settings.fileBinary
        config.binaryKey = settings.binaryKey
        config.mimeType = settings.mimeType
        return config
    }

    private static func fileWrite(_ settings: WorkflowNodeSettings) -> RAFileWriteConfig {
        var config = RAFileWriteConfig()
        config.path = settings.filePath
        config.content = settings.fileContent
        config.binaryKey = settings.binaryKey
        config.append = settings.fileAppend
        return config
    }

    private static func generation(_ settings: WorkflowNodeSettings) -> RALLMGenerationOptions? {
        guard settings.llmTemperature != nil || settings.llmMaxTokens != nil else { return nil }
        var options = RALLMGenerationOptions()
        if let temperature = settings.llmTemperature { options.temperature = Float(temperature) }
        if let maxTokens = settings.llmMaxTokens { options.maxOutputTokens = Int32(maxTokens) }
        return options
    }

    private static func dictionary(from rows: [WorkflowKeyValueRow]) -> [String: String] {
        rows.reduce(into: [:]) { result, row in
            guard !row.key.isEmpty else { return }
            result[row.key] = row.value
        }
    }
}

// MARK: - Proto → graph

extension WorkflowDocumentMapping {
    private static func node(_ wire: RAWorkflowNode) -> WorkflowNode? {
        guard let config = wire.config else { return nil }
        let parsed = settings(from: config)
        var node = WorkflowNode(
            id: wire.id,
            kind: parsed.kind,
            name: wire.name,
            position: CGPoint(x: CGFloat(wire.position.x), y: CGFloat(wire.position.y))
        )
        node.settings = parsed.settings
        return node
    }

    // The mirror of `config(of:)`, exhaustive for the same reason.
    // swiftlint:disable:next cyclomatic_complexity
    private static func settings(
        from config: RAWorkflowNode.OneOf_Config
    ) -> (kind: WorkflowNodeKind, settings: WorkflowNodeSettings) {
        switch config {
        case .manualTrigger(let value): return (.manualTrigger, manualTriggerSettings(value))
        case .scheduleTrigger(let value): return (.scheduleTrigger, scheduleSettings(value))
        case .llmGenerate(let value): return (.llmGenerate, llmGenerateSettings(value))
        case .llmStructured(let value): return (.llmStructured, llmStructuredSettings(value))
        case .vision(let value): return (.vision, visionSettings(value))
        case .embed(let value): return (.embed, embedSettings(value))
        case .rerank(let value): return (.rerank, rerankSettings(value))
        case .transcribe(let value): return (.transcribe, transcribeSettings(value))
        case .speak(let value): return (.speak, speakSettings(value))
        case .detectVoice(let value): return (.detectVoice, detectVoiceSettings(value))
        case .diarize(let value): return (.diarize, diarizeSettings(value))
        case .segment(let value): return (.segment, segmentSettings(value))
        case .ragQuery(let value): return (.ragQuery, ragQuerySettings(value))
        case .ragIngest(let value): return (.ragIngest, ragIngestSettings(value))
        case .loadModel(let value): return (.loadModel, loadModelSettings(value))
        case .condition(let value): return (.condition, conditionSettings(value))
        case .filter(let value): return (.filter, filterSettings(value))
        case .loopOverItems(let value): return (.loopOverItems, loopSettings(value))
        case .code(let value): return (.code, codeSettings(value))
        case .setTransform(let value): return (.setTransform, setTransformSettings(value))
        case .merge(let value): return (.merge, mergeSettings(value))
        case .splitOut(let value): return (.splitOut, fieldSettings(value.field))
        case .aggregate(let value): return (.aggregate, fieldSettings(value.field))
        case .wait(let value): return (.wait, waitSettings(value))
        case .toolCall(let value): return (.toolCall, toolCallSettings(value))
        case .httpRequest(let value): return (.httpRequest, httpSettings(value))
        case .fileRead(let value): return (.fileRead, fileReadSettings(value))
        case .fileWrite(let value): return (.fileWrite, fileWriteSettings(value))
        case .packNode(let value): return (.packNode, packNodeSettings(value))
        }
    }

    private static func manualTriggerSettings(_ value: RAManualTriggerConfig) -> WorkflowNodeSettings {
        var settings = WorkflowNodeSettings()
        settings.triggerItemsJSON = value.initialItemsJson
        return settings
    }

    private static func scheduleSettings(_ value: RAScheduleTriggerConfig) -> WorkflowNodeSettings {
        var settings = WorkflowNodeSettings()
        settings.scheduleKind = value.kind == .unspecified ? .interval : value.kind
        settings.scheduleIntervalSeconds = Int(value.intervalSeconds)
        settings.scheduleHour = Int(value.hour)
        settings.scheduleMinute = Int(value.minute)
        settings.scheduleCron = value.cron
        settings.triggerItemsJSON = value.initialItemsJson
        return settings
    }

    private static func llmGenerateSettings(_ value: RALlmGenerateConfig) -> WorkflowNodeSettings {
        var settings = WorkflowNodeSettings()
        settings.prompt = value.prompt
        settings.systemPrompt = value.hasSystemPrompt ? value.systemPrompt : ""
        settings.modelID = value.hasModelID ? value.modelID : ""
        if value.hasGeneration { applyGeneration(value.generation, to: &settings) }
        return settings
    }

    private static func llmStructuredSettings(_ value: RALlmStructuredConfig) -> WorkflowNodeSettings {
        var settings = WorkflowNodeSettings()
        settings.prompt = value.prompt
        settings.jsonSchema = value.jsonSchema
        settings.systemPrompt = value.hasSystemPrompt ? value.systemPrompt : ""
        settings.modelID = value.hasModelID ? value.modelID : ""
        if value.hasGeneration { applyGeneration(value.generation, to: &settings) }
        return settings
    }

    private static func visionSettings(_ value: RAVisionConfig) -> WorkflowNodeSettings {
        var settings = WorkflowNodeSettings()
        settings.prompt = value.prompt
        settings.binaryKey = value.binaryKey
        settings.modelID = value.hasModelID ? value.modelID : ""
        if value.hasGeneration { applyGeneration(value.generation, to: &settings) }
        return settings
    }

    private static func embedSettings(_ value: RAEmbedConfig) -> WorkflowNodeSettings {
        var settings = WorkflowNodeSettings()
        settings.textInput = value.text
        settings.modelID = value.hasModelID ? value.modelID : ""
        return settings
    }

    private static func rerankSettings(_ value: RARerankConfig) -> WorkflowNodeSettings {
        var settings = WorkflowNodeSettings()
        settings.rerankQuery = value.query
        settings.rerankDocuments = value.documents
        settings.rerankTopN = Int(value.topN)
        settings.modelID = value.hasModelID ? value.modelID : ""
        return settings
    }

    private static func transcribeSettings(_ value: RATranscribeConfig) -> WorkflowNodeSettings {
        var settings = WorkflowNodeSettings()
        settings.binaryKey = value.binaryKey
        settings.modelID = value.hasModelID ? value.modelID : ""
        settings.language = value.hasLanguage ? value.language : ""
        return settings
    }

    private static func speakSettings(_ value: RASpeakConfig) -> WorkflowNodeSettings {
        var settings = WorkflowNodeSettings()
        settings.textInput = value.text
        settings.binaryKey = value.binaryKey
        settings.modelID = value.hasModelID ? value.modelID : ""
        settings.voice = value.hasVoice ? value.voice : ""
        return settings
    }

    private static func detectVoiceSettings(_ value: RADetectVoiceConfig) -> WorkflowNodeSettings {
        var settings = WorkflowNodeSettings()
        settings.binaryKey = value.binaryKey
        if value.hasThreshold { settings.vadThreshold = Double(value.threshold) }
        return settings
    }

    private static func diarizeSettings(_ value: RADiarizeConfig) -> WorkflowNodeSettings {
        var settings = WorkflowNodeSettings()
        settings.binaryKey = value.binaryKey
        settings.modelID = value.hasModelID ? value.modelID : ""
        if value.hasSpeakerCount { settings.speakerCount = Int(value.speakerCount) }
        return settings
    }

    private static func segmentSettings(_ value: RASegmentConfig) -> WorkflowNodeSettings {
        var settings = WorkflowNodeSettings()
        settings.textInput = value.text
        settings.modelID = value.hasModelID ? value.modelID : ""
        return settings
    }

    private static func ragQuerySettings(_ value: RARagQueryConfig) -> WorkflowNodeSettings {
        var settings = WorkflowNodeSettings()
        settings.ragQuestion = value.question
        settings.embeddingModelID = value.embeddingModelID
        settings.ragLLMModelID = value.llmModelID
        settings.ragTopK = Int(value.topK)
        return settings
    }

    private static func ragIngestSettings(_ value: RARagIngestConfig) -> WorkflowNodeSettings {
        var settings = WorkflowNodeSettings()
        settings.textInput = value.text
        settings.embeddingModelID = value.embeddingModelID
        settings.ragLLMModelID = value.llmModelID
        settings.documentID = value.documentID
        return settings
    }

    private static func loadModelSettings(_ value: RALoadModelConfig) -> WorkflowNodeSettings {
        var settings = WorkflowNodeSettings()
        settings.modelID = value.modelID
        settings.loadCategory = value.hasCategory ? value.category : nil
        return settings
    }

    private static func conditionSettings(_ value: RAConditionConfig) -> WorkflowNodeSettings {
        var settings = WorkflowNodeSettings()
        settings.conditionLeft = value.left
        settings.conditionOperator = value.operator
        settings.conditionRight = value.right
        return settings
    }

    private static func filterSettings(_ value: RAFilterConfig) -> WorkflowNodeSettings {
        var settings = WorkflowNodeSettings()
        settings.conditionLeft = value.left
        settings.conditionOperator = value.operator
        settings.conditionRight = value.right
        return settings
    }

    private static func loopSettings(_ value: RALoopOverItemsConfig) -> WorkflowNodeSettings {
        var settings = WorkflowNodeSettings()
        settings.loopItems = value.items
        settings.loopBodyNodeIDs = value.bodyNodeIds
        settings.loopMaxIterations = Int(value.maxIterations)
        return settings
    }

    private static func codeSettings(_ value: RACodeConfig) -> WorkflowNodeSettings {
        var settings = WorkflowNodeSettings()
        settings.codeSource = value.source
        return settings
    }

    private static func setTransformSettings(_ value: RASetTransformConfig) -> WorkflowNodeSettings {
        var settings = WorkflowNodeSettings()
        settings.assignments = value.assignments.map {
            WorkflowKeyValueRow(key: $0.field, value: $0.value)
        }
        settings.keepOnlyAssigned = value.keepOnlyAssigned
        return settings
    }

    private static func mergeSettings(_ value: RAMergeConfig) -> WorkflowNodeSettings {
        var settings = WorkflowNodeSettings()
        settings.mergeInputCount = value.inputCount > 0 ? Int(value.inputCount) : 2
        settings.mergeDeduplicate = value.deduplicate
        return settings
    }

    private static func fieldSettings(_ field: String) -> WorkflowNodeSettings {
        var settings = WorkflowNodeSettings()
        settings.fieldPath = field
        return settings
    }

    private static func waitSettings(_ value: RAWaitConfig) -> WorkflowNodeSettings {
        var settings = WorkflowNodeSettings()
        settings.waitSeconds = Int(value.seconds)
        return settings
    }

    private static func toolCallSettings(_ value: RAToolCallConfig) -> WorkflowNodeSettings {
        var settings = WorkflowNodeSettings()
        settings.toolName = value.toolName
        settings.toolArguments = rows(from: value.arguments)
        settings.toolPorts = value.ports.map(WorkflowToolPort.init)
        return settings
    }

    private static func packNodeSettings(_ value: RAPackNodeConfig) -> WorkflowNodeSettings {
        var settings = WorkflowNodeSettings()
        settings.packID = value.packID
        settings.toolArguments = rows(from: value.arguments)
        settings.toolPorts = value.ports.map(WorkflowToolPort.init)
        settings.packOutputs = value.outputs
        settings.packMissing = value.missing
        return settings
    }

    private static func httpSettings(_ value: RAHttpRequestConfig) -> WorkflowNodeSettings {
        var settings = WorkflowNodeSettings()
        settings.httpMethod = value.method
        settings.httpURL = value.url
        settings.httpHeaders = rows(from: value.headers)
        settings.httpBody = value.hasBody ? value.body : ""
        settings.httpTimeoutMs = value.hasTimeoutMs ? Int(value.timeoutMs) : 0
        settings.httpAuthEnabled = value.hasAuth
        if value.hasAuth {
            settings.httpAuthKind = value.auth.kind == .unspecified ? .bearer : value.auth.kind
            settings.httpAuthSecret = value.auth.secret
            settings.httpAuthName = value.auth.name
        }
        return settings
    }

    private static func fileReadSettings(_ value: RAFileReadConfig) -> WorkflowNodeSettings {
        var settings = WorkflowNodeSettings()
        settings.filePath = value.path
        settings.fileBinary = value.binary
        settings.binaryKey = value.binaryKey
        settings.mimeType = value.mimeType
        return settings
    }

    private static func fileWriteSettings(_ value: RAFileWriteConfig) -> WorkflowNodeSettings {
        var settings = WorkflowNodeSettings()
        settings.filePath = value.path
        settings.fileContent = value.content
        settings.binaryKey = value.binaryKey
        settings.fileAppend = value.append
        return settings
    }

    private static func applyGeneration(
        _ options: RALLMGenerationOptions,
        to settings: inout WorkflowNodeSettings
    ) {
        if options.hasTemperature { settings.llmTemperature = Double(options.temperature) }
        if options.hasMaxOutputTokens { settings.llmMaxTokens = Int(options.maxOutputTokens) }
    }

    private static func rows(from dictionary: [String: String]) -> [WorkflowKeyValueRow] {
        dictionary.sorted { $0.key < $1.key }.map { WorkflowKeyValueRow(key: $0.key, value: $0.value) }
    }
}
