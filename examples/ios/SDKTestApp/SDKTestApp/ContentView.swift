import SwiftUI
import RunAnywhere
import LlamaCPPRuntime
import ONNXRuntime

@MainActor
final class DemoViewModel: ObservableObject {
    @Published var apiKey: String = ""
    @Published var baseURL: String = "https://api.runanywhere.ai"
    @Published var environment: SDKEnvironment = .development

    @Published var llmModelId: String = "llama-3.2-1b-instruct-q4"
    @Published var sttModelId: String = "whisper-base-onnx"
    @Published var ttsVoiceId: String = "piper-en_US-amy"

    @Published var prompt: String = "Write a one sentence summary of this SDK."
    @Published var ttsText: String = "Hello from RunAnywhere."

    @Published var isInitialized: Bool = false
    @Published var servicesReady: Bool = false
    @Published var currentLLMModel: String = "—"
    @Published var currentTTSVoice: String = "—"
    @Published var modelCount: Int = 0

    @Published var lastChatResponse: String = ""
    @Published var lastTTSSummary: String = ""

    @Published var logs: [String] = []

    func appendLog(_ message: String) {
        let line = "[\(Self.timestamp())] \(message)"
        logs.insert(line, at: 0)
    }

    func initialize() {
        do {
            try RunAnywhere.initialize(apiKey: apiKey.isEmpty ? nil : apiKey,
                                      baseURL: baseURL.isEmpty ? nil : baseURL,
                                      environment: environment)
            appendLog("Initialized SDK (env: \(environment.description))")
            refreshStatus()
        } catch {
            appendLog("Init failed: \(error)")
        }
    }

    func registerBackends() {
        LlamaCPP.register()
        ONNX.register()
        appendLog("Backends registered (LlamaCPP + ONNX)")
    }

    func refreshStatus() {
        isInitialized = RunAnywhere.isSDKInitialized
        servicesReady = RunAnywhere.areServicesReady
        Task {
            currentLLMModel = await RunAnywhere.getCurrentModelId() ?? "—"
            currentTTSVoice = await RunAnywhere.currentTTSVoiceId ?? "—"
            do {
                let models = try await RunAnywhere.availableModels()
                modelCount = models.count
            } catch {
                appendLog("Model registry unavailable: \(error)")
            }
        }
    }

    func loadLLMModel() {
        Task {
            do {
                try await RunAnywhere.loadModel(llmModelId)
                appendLog("LLM model loaded: \(llmModelId)")
                refreshStatus()
            } catch {
                appendLog("LLM load failed: \(error)")
            }
        }
    }

    func loadSTTModel() {
        Task {
            do {
                try await RunAnywhere.loadSTTModel(sttModelId)
                appendLog("STT model loaded: \(sttModelId)")
            } catch {
                appendLog("STT load failed: \(error)")
            }
        }
    }

    func loadTTSVoice() {
        Task {
            do {
                try await RunAnywhere.loadTTSVoice(ttsVoiceId)
                appendLog("TTS voice loaded: \(ttsVoiceId)")
                refreshStatus()
            } catch {
                appendLog("TTS load failed: \(error)")
            }
        }
    }

    func chat() {
        Task {
            do {
                let response = try await RunAnywhere.chat(prompt)
                lastChatResponse = response
                appendLog("Chat completed (\(response.count) chars)")
            } catch {
                appendLog("Chat failed: \(error)")
            }
        }
    }

    func synthesize() {
        Task {
            do {
                let output = try await RunAnywhere.synthesize(ttsText)
                lastTTSSummary = "Format: \(output.format.rawValue) • \(Int(output.duration))s • \(output.audioSizeBytes) bytes"
                appendLog("TTS synthesized: \(lastTTSSummary)")
            } catch {
                appendLog("TTS failed: \(error)")
            }
        }
    }

    func resetSDK() {
        RunAnywhere.reset()
        appendLog("SDK reset")
        refreshStatus()
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}

struct ContentView: View {
    @StateObject private var model = DemoViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    statusCard
                    initCard
                    modelCard
                    llmCard
                    ttsCard
                    logsCard
                }
                .padding(20)
            }
            .navigationTitle("SDK Test")
            .onAppear {
                model.refreshStatus()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RunAnywhere SDK Test")
                .font(.title2).bold()
            Text("Version: \(RunAnywhere.version)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Device ID: \(RunAnywhere.deviceId)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Status").font(.headline)
            HStack {
                statusPill(title: "Initialized", isOn: model.isInitialized)
                statusPill(title: "Services Ready", isOn: model.servicesReady)
            }
            Text("LLM: \(model.currentLLMModel)")
                .font(.caption)
            Text("TTS: \(model.currentTTSVoice)")
                .font(.caption)
            Text("Models in registry: \(model.modelCount)")
                .font(.caption)
            HStack {
                Button("Refresh") { model.refreshStatus() }
                Button("Reset SDK", role: .destructive) { model.resetSDK() }
            }
        }
        .cardStyle()
    }

    private var initCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Initialize").font(.headline)
            Picker("Environment", selection: $model.environment) {
                Text("Dev").tag(SDKEnvironment.development)
                Text("Prod").tag(SDKEnvironment.production)
                Text("Staging").tag(SDKEnvironment.staging)
            }
            .pickerStyle(.segmented)

            TextField("API Key (optional for dev)", text: $model.apiKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            TextField("Base URL", text: $model.baseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Initialize SDK") { model.initialize() }
                Button("Register Backends") { model.registerBackends() }
            }
        }
        .cardStyle()
    }

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Models").font(.headline)
            TextField("LLM Model ID", text: $model.llmModelId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            Button("Load LLM Model") { model.loadLLMModel() }

            TextField("STT Model ID", text: $model.sttModelId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            Button("Load STT Model") { model.loadSTTModel() }

            TextField("TTS Voice ID", text: $model.ttsVoiceId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            Button("Load TTS Voice") { model.loadTTSVoice() }
        }
        .cardStyle()
    }

    private var llmCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LLM Demo").font(.headline)
            TextField("Prompt", text: $model.prompt, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
            Button("Generate") { model.chat() }

            if !model.lastChatResponse.isEmpty {
                Text("Response").font(.caption).foregroundStyle(.secondary)
                Text(model.lastChatResponse)
                    .font(.body)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .cardStyle()
    }

    private var ttsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TTS Demo").font(.headline)
            TextField("Text to synthesize", text: $model.ttsText, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
            Button("Synthesize") { model.synthesize() }

            if !model.lastTTSSummary.isEmpty {
                Text(model.lastTTSSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    private var logsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Logs").font(.headline)
            if model.logs.isEmpty {
                Text("No logs yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.logs.prefix(8), id: \.self) { line in
                    Text(line).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .cardStyle()
    }

    private func statusPill(title: String, isOn: Bool) -> some View {
        HStack(spacing: 6) {
            Circle().fill(isOn ? .green : .red).frame(width: 8, height: 8)
            Text(title).font(.caption)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
