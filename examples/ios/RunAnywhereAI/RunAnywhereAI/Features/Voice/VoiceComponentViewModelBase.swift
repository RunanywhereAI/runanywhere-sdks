//
//  VoiceComponentViewModelBase.swift
//  RunAnywhereAI
//
//  Shared lifecycle base for the single-component Voice ViewModels
//  (STT / TTS / VAD). It owns the idempotent initialize/subscribe/cleanup
//  plumbing that every voice-component screen needs so each concrete
//  ViewModel only declares its component identity and how it maps an
//  SDK event onto its published model state.
//
//  VoiceAgentViewModel is intentionally NOT built on this base: it
//  orchestrates the full STT→LLM→TTS pipeline and consumes per-component
//  event streams plus lifecycle snapshots, a richer pattern than the
//  single-component load/unload tracking captured here.
//

import Foundation
import RunAnywhere
import Combine
import os

/// Base class for ViewModels that observe a single SDK voice component's
/// load/unload lifecycle (STT, TTS, VAD).
///
/// Subclasses must override `component`, `eventCategory`, and `modelCategory`
/// to identify their modality. The base provides the shared
/// `loadModel(from:)` entry point, the idempotent `subscribeToSDKEvents()`
/// (built on the SDK's typed `modelLifecycle` stream), and
/// `checkInitialModelState()` / `cleanupBase()` helpers shared by all three.
@MainActor
class VoiceComponentViewModelBase: ObservableObject {
    // MARK: - Published Model State

    @Published var selectedFramework: InferenceFramework?
    @Published var selectedModelName: String?
    @Published var selectedModelId: String?
    @Published var errorMessage: String?

    // MARK: - Subscription / Idempotency State

    let logger: Logger
    var cancellables = Set<AnyCancellable>()
    private var isInitialized = false
    private var hasSubscribedToSDKEvents = false

    // MARK: - Component Identity (override in subclasses)

    /// SDK component this ViewModel tracks (e.g. `.stt`).
    var component: RASDKComponent { .unspecified }

    /// Event category that carries this component's lifecycle events.
    var eventCategory: RAEventCategory { .unspecified }

    /// Model category used to query the initial loaded model.
    var modelCategory: RAModelCategory { .unspecified }

    // MARK: - Initialization

    init(loggerCategory: String) {
        self.logger = Logger(subsystem: "com.runanywhere", category: loggerCategory)
    }

    /// Claim the one-time initialization guard. Subclasses call this at the
    /// top of their `initialize()`; when it returns `true` they own the
    /// remaining setup (permissions, subscriptions, initial-state query) and
    /// may order it however the modality requires.
    ///
    /// - Returns: `true` when this is the first initialization, `false` when
    ///   already initialized and the caller should bail out.
    func beginInitialization() -> Bool {
        guard !isInitialized else {
            logger.debug("Voice component view model already initialized, skipping")
            return false
        }
        isInitialized = true
        return true
    }

    // MARK: - Model Loading

    /// Load a model for this component via the canonical SDK entry point.
    /// Shared by every voice-component screen; subclasses wrap it only to
    /// toggle their busy flag.
    @discardableResult
    func loadModel(from model: RAModelInfo) async -> Bool {
        logger.info("Loading \(String(describing: self.component)) model: \(model.name)")
        errorMessage = nil

        var request = RAModelLoadRequest()
        request.modelID = model.id
        request.category = modelCategory
        let result = await RunAnywhere.loadModel(request)
        guard result.success else {
            logger.error("Model load failed: \(result.errorMessage)")
            errorMessage = "Failed to load model: \(result.errorMessage)"
            return false
        }
        applyLoadedModel(model)
        logger.info("Model loaded: \(model.id)")
        return true
    }

    // MARK: - SDK Event Subscription

    func subscribeToSDKEvents() {
        guard !hasSubscribedToSDKEvents else {
            logger.debug("Already subscribed to SDK events, skipping")
            return
        }
        hasSubscribedToSDKEvents = true

        // The SDK's typed lifecycle stream folds the three native load/unload
        // channels into one publisher; the base just applies it to this
        // component's published state.
        RunAnywhere.events.modelLifecycle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                // Defer state modifications to avoid "Publishing changes
                // within view updates" warnings.
                Task { @MainActor in
                    guard let self else { return }
                    guard change.component == self.component
                        || change.event.category == self.eventCategory else { return }
                    switch change.kind {
                    case .loaded:
                        self.applyCurrentModelSnapshot(reason: "loaded")
                    case .unloaded:
                        self.clearLoadedModel()
                        self.logger.info("Voice component model unloaded")
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Initial Model State

    func checkInitialModelState() async {
        applyCurrentModelSnapshot(reason: "already loaded")
    }

    /// Resolve the current model for this modality via the SDK snapshot and
    /// apply it to published state. Shared by `checkInitialModelState()` (cold
    /// start) and the lifecycle-loaded sink — the lifecycle change only
    /// carries `modelID`/`kind`, so the full `RAModelInfo` is re-resolved
    /// through `RunAnywhere.currentModel` rather than passed from the event.
    func applyCurrentModelSnapshot(reason: String) {
        var request = RACurrentModelRequest()
        request.category = modelCategory
        let snapshot = RunAnywhere.currentModel(request)
        guard snapshot.found else { return }

        // When the snapshot omits model metadata, `model.id` is empty; fall
        // back to the top-level `modelID` so the id is always populated.
        var model = snapshot.model
        if model.id.isEmpty {
            model.id = snapshot.modelID
        }
        applyLoadedModel(model)
        logger.info("Voice component model \(reason): \(model.id)")
    }

    /// Apply a model resolved at startup (or via an event) to published state.
    /// Default resolves the display name from the id; override when a modality
    /// needs different name/framework resolution (e.g. catalog lookup).
    func applyLoadedModel(_ model: RAModelInfo) {
        selectedModelId = model.id
        selectedModelName = model.name.modelNameFromID()
        selectedFramework = model.framework
    }

    /// Clear published state for an unloaded model.
    func clearLoadedModel() {
        selectedModelId = nil
        selectedModelName = nil
        selectedFramework = nil
    }

    // MARK: - Cleanup

    /// Tear down subscriptions and reset the idempotency guards so the
    /// ViewModel can be re-initialized. Subclasses call this from their
    /// `cleanup()` after releasing any modality-specific resources.
    func cleanupBase() {
        cancellables.removeAll()
        isInitialized = false
        hasSubscribedToSDKEvents = false
    }
}
