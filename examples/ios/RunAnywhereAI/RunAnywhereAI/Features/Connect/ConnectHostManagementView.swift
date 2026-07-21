//
//  ConnectHostManagementView.swift
//  RunAnywhereAI
//
//  macOS control surface for sharing one loaded language model on the local network.
//

#if os(macOS)
import Combine
import RunAnywhere
import SwiftUI

/// Keeps the local host alive when the user navigates away from its management view.
/// The host only publishes a model that is loaded by the existing app model flow.
@MainActor
final class ConnectHostController: ObservableObject {
    static let shared = ConnectHostController()

    let session = ConnectSession()

    @Published private(set) var selectedModel: RAModelInfo?
    @Published private(set) var isStarting = false
    @Published private(set) var errorMessage: String?

    private var sessionCancellable: AnyCancellable?
    private var lifecycleCancellable: AnyCancellable?

    private init() {
        sessionCancellable = session.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }

        lifecycleCancellable = RunAnywhere.events.modelLifecycle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                self?.handleModelLifecycle(change)
            }
    }

    var isHosting: Bool {
        session.status == .hosting
    }

    func useDefaultModelIfAvailable(_ model: RAModelInfo?) {
        guard !isHosting,
              selectedModel == nil,
              let model,
              model.category == .language else {
            return
        }
        selectedModel = model
    }

    func selectModel(_ model: RAModelInfo) {
        guard model.category == .language else { return }
        selectedModel = model
        errorMessage = nil
    }

    func startHosting() async {
        guard !isStarting else { return }
        guard let selectedModel else {
            errorMessage = "Choose a language model before hosting this Mac."
            return
        }

        isStarting = true
        errorMessage = nil
        defer { isStarting = false }

        do {
            // A model selected from the catalog may not be the one currently in
            // memory. Load it through the app's canonical model flow before
            // advertising it, so every client receives a usable model.
            if ModelListViewModel.shared.currentModel?.id != selectedModel.id {
                try await ModelListViewModel.shared.loadModel(selectedModel)
            }

            let model = ConnectModel(
                id: selectedModel.id,
                displayName: selectedModel.name,
                framework: selectedModel.framework.displayName,
                contextWindow: selectedModel.contextLength > 0
                    ? UInt32(selectedModel.contextLength)
                    : 0,
                supportsStreaming: true
            )

            try await session.startHosting(model: model) { request in
                try await RunAnywhere.generateStream(request)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopHosting() {
        session.stopHosting()
    }

    private func handleModelLifecycle(_ change: RAModelLifecycleChange) {
        guard change.kind == .unloaded,
              isHosting,
              change.modelID == selectedModel?.id else {
            return
        }

        // Do not keep publishing a host whose advertised model has been
        // unloaded elsewhere in the app. Clients will discover a truthful
        // availability state rather than connecting to a stale endpoint.
        session.stopHosting()
        errorMessage = "Hosting stopped because \(selectedModel?.name ?? "the selected model") was unloaded."
    }
}

struct ConnectHostManagementView: View {
    @ObservedObject private var hostController = ConnectHostController.shared
    @ObservedObject private var modelList = ModelListViewModel.shared

    @State private var showingModelPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                introduction

                if hostController.isHosting {
                    hostingStatus
                } else {
                    hostingSetup
                }

                if let errorMessage = hostController.errorMessage {
                    errorNotice(errorMessage)
                }

                networkNotice
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Host this Mac")
        .task {
            await modelList.loadModelsFromRegistry()
            hostController.useDefaultModelIfAvailable(modelList.currentModel)
        }
        .onChange(of: modelList.currentModel?.id) { _, _ in
            hostController.useDefaultModelIfAvailable(modelList.currentModel)
        }
        .adaptiveSheet(isPresented: $showingModelPicker) {
            ModelSelectionSheet(context: .llm) { model in
                hostController.selectModel(model)
            }
        }
    }

    private var introduction: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "macbook.and.iphone")
                .font(.system(size: 26, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppColors.primaryAccent)
                .frame(width: 52, height: 52)
                .background(AppColors.primaryAccent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Text("Host this Mac")
                        .font(.title2.weight(.semibold))

                    statusBadge
                }

                Text("Use a language model on this Mac from iPhone and iPad devices on the same local network.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusBadge: some View {
        Label(
            hostController.isHosting ? "Hosting" : (hostController.isStarting ? "Starting" : "Not hosting"),
            systemImage: hostController.isHosting ? "circle.fill" : "circle"
        )
        .font(.caption.weight(.medium))
        .foregroundStyle(hostController.isHosting ? AppColors.statusGreen : AppColors.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((hostController.isHosting ? AppColors.statusGreen : AppColors.statusGray).opacity(0.12))
        .clipShape(Capsule())
    }

    private var hostingSetup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 18) {
                modelSelection

                Divider()

                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Share on your local network")
                            .font(.subheadline.weight(.medium))
                        Text(hostController.selectedModel == nil
                             ? "Choose a model before starting the host."
                             : "The model will be loaded and advertised when hosting starts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    startHostingButton
                }
            }
            .padding(8)
        } label: {
            Label("Hosting setup", systemImage: "switch.2")
                .font(.headline)
        }
    }

    private var modelSelection: some View {
        HStack(spacing: 14) {
            Image(systemName: hostController.selectedModel == nil ? "cube" : "checkmark.circle.fill")
                .font(.system(size: 18, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(hostController.selectedModel == nil ? AppColors.statusGray : AppColors.statusGreen)
                .frame(width: 38, height: 38)
                .background((hostController.selectedModel == nil ? AppColors.statusGray : AppColors.statusGreen).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(hostController.selectedModel?.name ?? "No model selected")
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(hostController.selectedModel.map { $0.framework.displayName } ?? "Select the language model this Mac will provide")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(hostController.selectedModel == nil ? "Choose Model" : "Change") {
                showingModelPicker = true
            }
        }
    }

    private var startHostingButton: some View {
        Button {
            guard hostController.selectedModel != nil else {
                showingModelPicker = true
                return
            }

            Task { await hostController.startHosting() }
        } label: {
            if hostController.isStarting {
                ProgressView()
                    .controlSize(.small)
                    .frame(minWidth: 94)
            } else {
                Label(
                    hostController.selectedModel == nil ? "Choose Model" : "Start Hosting",
                    systemImage: hostController.selectedModel == nil ? "cube" : "play.fill"
                )
            }
        }
        .disabled(hostController.isStarting)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private var hostingStatus: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 20, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(AppColors.statusGreen)
                        .frame(width: 42, height: 42)
                        .background(AppColors.statusGreen.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Available on your local network")
                            .font(.body.weight(.medium))
                        Text("Keep RunAnywhere open on this Mac while other devices use the model.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Stop Hosting", role: .destructive) {
                        hostController.stopHosting()
                    }
                    .controlSize(.large)
                }

                Divider()

                LabeledContent("Model") {
                    Text(hostController.session.activeModel?.displayName ?? hostController.selectedModel?.name ?? "Language model")
                        .lineLimit(1)
                }

                LabeledContent("Connected devices") {
                    Text("\(hostController.session.activeClientCount)")
                        .monospacedDigit()
                }

                LabeledContent("Access") {
                    Text("Same local network")
                }
            }
            .padding(8)
        } label: {
            Label("Hosting status", systemImage: "network")
                .font(.headline)
        }
    }

    private func errorNotice(_ message: String) -> some View {
        Label {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(AppColors.statusOrange)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.statusOrange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var networkNotice: some View {
        Label {
            Text("Connections stay on your local network. This Mac is not exposed to the internet.")
        } icon: {
            Image(systemName: "lock.shield")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
#endif
