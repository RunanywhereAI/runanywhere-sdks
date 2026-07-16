//
//  SimplifiedModelsView.swift
//  RunAnywhereAI
//
//  Consumer-facing Models screen: hardware-aware recommendations up top, then a
//  clean, family-first catalog. Backend/quantization details are hidden — users
//  pick by friendly family + feel, and choose a specific variant in the family
//  detail. All recommendation/family/tag logic lives in the example app; the SDK
//  is consumed only via its public facade + RAModelInfo.
//

import SwiftUI
import RunAnywhere

struct SimplifiedModelsView: View {
    @StateObject private var viewModel = ModelListViewModel.shared
    @StateObject private var storageViewModel = StorageViewModel.shared
    @StateObject private var deviceInfo = DeviceInfoService.shared

    @State private var selectedModel: RAModelInfo?
    @State private var searchText = ""
    @State private var selectedModality: ModelModalityFilter = .all
    @State private var showAddFromHuggingFace = false
    @State private var showAddFromURL = false

    private let recommendationEngine = ModelRecommendationEngine()
    private let tierResolver = HardwareTierResolver()

    /// Detected hardware tier for the current device.
    private var hardwareTier: HardwareTier {
        tierResolver.resolve(from: deviceInfo.deviceInfo)
    }

    /// Hardware-aware recommendations computed from the live catalog.
    private var recommendation: RecommendedSelection {
        recommendationEngine.recommend(
            tier: hardwareTier,
            appleFoundationAvailable: tierResolver.appleFoundationAvailable,
            from: viewModel.availableModels
        )
    }

    /// Models not already surfaced in the recommended hero, grouped into families.
    private var browseFamilies: [ModelFamily] {
        let surfaced = recommendation.surfacedModelIDs
        let remaining = viewModel.availableModels.filter { model in
            !surfaced.contains(model.id)
                && selectedModality.matches(model)
                && searchMatches(model)
        }
        return ModelFamilyCatalog.families(from: remaining)
    }

    private var hasActiveFilters: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedModality != .all
    }

    private var handlers: ModelActionHandlers {
        ModelActionHandlers(
            onSelect: { model in Task { await selectModel(model) } },
            onChanged: { Task { await refreshAfterChange() } },
            onDelete: { model in Task { await deleteModel(model) } }
        )
    }

    var body: some View {
        #if os(macOS)
        mainContentView
        #else
        NavigationView {
            mainContentView
        }
        .navigationViewStyle(.stack)
        #endif
    }

    private var mainContentView: some View {
        List {
            DeviceSummarySection(tier: hardwareTier, device: deviceInfo.deviceInfo)
            recommendedSection
            browseSection
            ModelStorageSection(storageViewModel: storageViewModel)
        }
        .navigationTitle("Models")
        .toolbar {
            addModelToolbarItem
        }
        .sheet(
            isPresented: $showAddFromHuggingFace,
            onDismiss: { Task { await refreshAfterChange() } },
            content: { AddFromHuggingFaceView() }
        )
        .sheet(
            isPresented: $showAddFromURL,
            onDismiss: { Task { await refreshAfterChange() } },
            content: {
                AddModelFromURLView { _ in
                    Task { await refreshAfterChange() }
                }
            }
        )
        .task {
            await loadInitialData()
        }
    }

    private var addModelToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    showAddFromHuggingFace = true
                } label: {
                    Label("Add from Hugging Face", systemImage: "magnifyingglass")
                }
                Button {
                    showAddFromURL = true
                } label: {
                    Label("Add from URL", systemImage: "link")
                }
            } label: {
                Image(systemName: "plus")
            }
        }
    }

    // MARK: - Data

    private func loadInitialData() async {
        await viewModel.loadModelsFromRegistry()
        await storageViewModel.loadData()
    }

    /// Clean search: matches friendly family/variant names + tags only — never
    /// quantization or backend names.
    private func searchMatches(_ model: RAModelInfo) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }
        let tagText = model.consumerTags.map(\.label).joined(separator: " ")
        return [model.name, model.category.consumerCapabilityLabel, tagText]
            .joined(separator: " ")
            .lowercased()
            .contains(query)
    }

    private func selectModel(_ model: RAModelInfo) async {
        selectedModel = model
        await viewModel.selectModel(model)
    }

    private func deleteModel(_ model: RAModelInfo) async {
        do {
            try await viewModel.deleteModel(model)
            await storageViewModel.refreshData()
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func refreshAfterChange() async {
        await viewModel.loadModelsFromRegistry()
        await storageViewModel.refreshData()
    }

    private func unavailableReason(for model: RAModelInfo) -> String? {
        guard model.framework == .foundationModels else { return nil }
        return SystemFoundationModels.unavailableReason
    }

    // MARK: - Recommended (hardware-aware hero)

    private var recommendedSection: some View {
        Group {
            if hasRecommendations {
                Section {
                    if let defaultModel = recommendation.defaultChatModel {
                        defaultModelCard(defaultModel)
                    }

                    ForEach(recommendedLLMCards, id: \.id) { model in
                        RecommendedModelCard(
                            model: model,
                            subtitle: model.tagline,
                            availabilityReason: unavailableReason(for: model),
                            isSelected: selectedModel?.id == model.id,
                            isLoadingModel: viewModel.isLoadingModel,
                            handlers: handlers
                        )
                    }

                    if !recommendation.companions.isEmpty {
                        companionsRow
                    }
                } header: {
                    Text("Recommended for \(recommendedHeaderDeviceName)")
                } footer: {
                    Text("Picked to fit your device. Apple's built-in model is used first when available.")
                        .font(AppTypography.caption)
                }
            }
        }
    }

    private var hasRecommendations: Bool {
        recommendation.defaultChatModel != nil || !recommendation.recommendedLLMs.isEmpty
    }

    /// Recommended LLMs excluding the one already shown as the prominent default.
    private var recommendedLLMCards: [RAModelInfo] {
        let defaultID = recommendation.defaultChatModel?.id
        return recommendation.recommendedLLMs.filter { $0.id != defaultID }
    }

    /// Friendly phrase for the section header — never a raw identifier.
    private var recommendedHeaderDeviceName: String {
        guard let modelName = deviceInfo.deviceInfo?.modelName.lowercased() else {
            return "your device"
        }
        if modelName.contains("iphone") { return "this iPhone" }
        if modelName.contains("ipad") { return "this iPad" }
        if modelName.contains("mac") { return "this Mac" }
        return "your device"
    }

    private func defaultModelCard(_ model: RAModelInfo) -> some View {
        RecommendedModelCard(
            model: model,
            subtitle: model.tagline,
            availabilityReason: unavailableReason(for: model),
            isSelected: selectedModel?.id == model.id,
            isLoadingModel: viewModel.isLoadingModel,
            highlight: model.isBuiltIn ? "Best for this device" : "Default",
            handlers: handlers
        )
    }

    private var companionsRow: some View {
        VStack(alignment: .leading, spacing: AppSpacing.smallMedium) {
            Text("Also recommended")
                .font(AppTypography.captionMedium)
                .foregroundColor(AppColors.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.smallMedium) {
                    ForEach(recommendation.companions, id: \.id) { model in
                        CompanionModelChip(
                            model: model,
                            isSelected: selectedModel?.id == model.id,
                            isLoadingModel: viewModel.isLoadingModel,
                            handlers: handlers
                        )
                    }
                }
                .padding(.vertical, AppSpacing.xxSmall)
            }
        }
        .padding(.vertical, AppSpacing.xSmall)
    }

    // MARK: - Browse by family

    private var browseSection: some View {
        Group {
            searchSection

            if browseFamilies.isEmpty && !showsImageGenPlaceholder {
                Section {
                    emptyBrowseState
                } header: {
                    Text("Browse Models")
                }
            } else {
                Section {
                    ForEach(browseFamilies) { family in
                        NavigationLink {
                            ModelFamilyDetailView(
                                family: family,
                                tier: hardwareTier,
                                selectedModelID: selectedModel?.id,
                                isLoadingModel: viewModel.isLoadingModel,
                                availabilityReason: unavailableReason(for:),
                                handlers: handlers
                            )
                        } label: {
                            ModelFamilyRow(family: family)
                        }
                    }

                    if showsImageGenPlaceholder {
                        ComingSoonFamilyRow(
                            title: "Image Generation",
                            tagline: "Apple on-device image generation",
                            systemImage: "photo.artframe"
                        )
                    }
                } header: {
                    Text("Browse Models")
                } footer: {
                    Text("Pick a family, then choose the size that fits. We preselect the best one for you.")
                        .font(AppTypography.caption)
                }
            }
        }
    }

    /// Show the CoreML image-generation placeholder when its modality is in
    /// view, no real image-generation family is registered yet, and the search
    /// query is empty or plausibly matches it.
    private var showsImageGenPlaceholder: Bool {
        guard selectedModality.showsImageGenerationPlaceholder else { return false }
        guard !browseFamilies.contains(where: { $0.category == .imageGeneration }) else { return false }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }
        return "image generation apple coreml photo art".contains(query)
    }

    private var searchSection: some View {
        Section {
            ModelSearchBar(searchText: $searchText, selectedModality: $selectedModality)
        }
    }

    private var emptyBrowseState: some View {
        VStack(alignment: .center, spacing: AppSpacing.mediumLarge) {
            Image(systemName: hasActiveFilters ? "magnifyingglass" : "cube")
                .font(.system(size: 32, weight: .semibold))
                .foregroundColor(AppColors.textSecondary.opacity(0.6))
            Text(hasActiveFilters ? "No models match your search" : "No models available")
                .font(AppTypography.subheadline)
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xLarge)
    }
}

// MARK: - Recommended card subtitle

private extension RAModelInfo {
    /// One friendly line for a recommended card — size only, no technical terms.
    var tagline: String {
        isBuiltIn ? "Built in · no download" : consumerSizeLabel
    }
}

#Preview {
    SimplifiedModelsView()
}
