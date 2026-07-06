//
//  ChatMessageListView.swift
//  RunAnywhereAI
//
//  Message list + input area for ChatInterfaceView.
//

import SwiftUI
import os.log
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

enum ComposerAction {
    case attachFile
    case takePhoto
    case attachPhoto
    case talk
}

// MARK: - Chat Messages View

struct ChatMessageListView: View {
    @Bindable var viewModel: LLMViewModel
    @FocusState.Binding var isTextFieldFocused: Bool
    @Binding var showingLoRAManagement: Bool
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var toolSettingsViewModel: ToolSettingsViewModel

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                ScrollView {
                    if viewModel.messages.isEmpty && !viewModel.isGenerating {
                        emptyStateView
                    } else {
                        messageListView
                    }
                }
                .scrollDisabled(viewModel.messages.isEmpty && !viewModel.isGenerating)
                .defaultScrollAnchor(viewModel.messages.isEmpty && !viewModel.isGenerating ? .center : .bottom)
            }
            .background(AppColors.backgroundGrouped)
            .contentShape(Rectangle())
            .onTapGesture {
                isTextFieldFocused = false
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.isGenerating) { _, isGenerating in
                if isGenerating {
                    scrollToBottom(proxy: proxy, animated: true)
                }
            }
            .onChange(of: isTextFieldFocused) { _, focused in
                if focused {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                }
            }
            #if os(iOS)
            .onReceive(
                NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            ) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    scrollToBottom(proxy: proxy, animated: true)
                }
            }
            #endif
            .onChange(of: viewModel.messages.last?.content) { _, _ in
                if viewModel.isGenerating, let lastMessage = viewModel.messages.last {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: AppSpacing.xLarge) {
            Spacer()

            Image("runanywhere_logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 76, height: 76)

            VStack(spacing: 8) {
                Text("Ask anything privately")
                    .font(AppTypography.title2Semibold)
                    .foregroundColor(AppColors.textPrimary)

                Text("Chat with local models, attach context, or switch into Talk mode when you want to speak.")
                    .font(AppTypography.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            starterPrompts

            Spacer()
        }
        .padding(.horizontal, AppSpacing.xLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var starterPrompts: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.mediumLarge) {
                StarterPromptChip(title: "Explain", subtitle: "a complex topic simply") {
                    viewModel.currentInput = "Explain a complex topic simply"
                    isTextFieldFocused = true
                }

                StarterPromptChip(title: "Summarize", subtitle: "my notes or document") {
                    viewModel.currentInput = "Summarize this clearly:"
                    isTextFieldFocused = true
                }

                StarterPromptChip(title: "Draft", subtitle: "a polished response") {
                    viewModel.currentInput = "Draft a polished response for:"
                    isTextFieldFocused = true
                }
            }
        }
    }

    // MARK: - Message List

    private var messageListView: some View {
        LazyVStack(spacing: AppSpacing.large) {
            Spacer(minLength: 20)
                .id("top-spacer")

            ForEach(viewModel.messages) { message in
                MessageBubbleView(message: message, isGenerating: viewModel.isGenerating)
                    .id(message.id.uuidString)
                    .transition(messageTransition)
                    .animation(nil, value: message.content)
            }

            if viewModel.isGenerating, viewModel.messages.last?.content.isEmpty == true {
                TypingIndicatorView()
                    .id("typing")
                    .transition(typingTransition)
            }

            Spacer(minLength: 20)
                .id("bottom-spacer")
        }
        .padding(AppSpacing.large)
        .animation(.default, value: viewModel.messages.count)
    }

    private var messageTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.8)
                .combined(with: .opacity)
                .combined(with: .move(edge: .bottom)),
            removal: .scale(scale: 0.9).combined(with: .opacity)
        )
    }

    private var typingTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.8).combined(with: .opacity),
            removal: .scale(scale: 0.9).combined(with: .opacity)
        )
    }

    // MARK: - Scroll Helper

    func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        let scrollToId: String
        if viewModel.isGenerating {
            scrollToId = "typing"
        } else if let lastMessage = viewModel.messages.last {
            scrollToId = lastMessage.id.uuidString
        } else {
            scrollToId = "bottom-spacer"
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.5)) {
                proxy.scrollTo(scrollToId, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(scrollToId, anchor: .bottom)
        }
    }
}

// MARK: - Chat Input Area

struct ChatInputAreaView: View {
    @Bindable var viewModel: LLMViewModel
    @FocusState.Binding var isTextFieldFocused: Bool
    @Binding var showingLoRAManagement: Bool
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var toolSettingsViewModel: ToolSettingsViewModel
    let imageAttachment: ChatImageAttachment?
    let documentAttachment: ChatDocumentAttachment?
    let isVisionModelReady: Bool
    let areDocumentModelsReady: Bool
    let canSendCurrentTurn: Bool
    let onRemoveImageAttachment: () -> Void
    let onRemoveDocumentAttachment: () -> Void
    let onChooseVisionModel: () -> Void
    let onChooseDocumentModels: () -> Void
    let onComposerAction: (ComposerAction) -> Void
    let onSend: () -> Void

    var hasModelSelected: Bool {
        viewModel.isModelLoaded && viewModel.loadedModelName != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 8) {
                if settingsViewModel.thinkingModeEnabled && viewModel.loadedModelSupportsThinking {
                    thinkingModeBadge
                }

                if viewModel.useToolCalling {
                    toolCallingBadge
                }

                if !viewModel.loraAdapters.isEmpty {
                    loraAdapterBadge
                }

                if hasModelSelected {
                    loraAddButton
                }
            }
            .padding(
                .top,
                ((settingsViewModel.thinkingModeEnabled && viewModel.loadedModelSupportsThinking)
                    || viewModel.useToolCalling
                    || !viewModel.loraAdapters.isEmpty
                    || hasModelSelected
                    || imageAttachment != nil
                    || documentAttachment != nil) ? 8 : 0
            )

            if let imageAttachment {
                ImageAttachmentPill(
                    attachment: imageAttachment,
                    isVisionModelReady: isVisionModelReady,
                    onRemove: onRemoveImageAttachment,
                    onChooseVisionModel: onChooseVisionModel
                )
                .padding(.horizontal, AppSpacing.large)
                .padding(.top, AppSpacing.small)
            }

            if let documentAttachment {
                DocumentAttachmentPill(
                    attachment: documentAttachment,
                    areModelsReady: areDocumentModelsReady,
                    onRemove: onRemoveDocumentAttachment,
                    onChooseModels: onChooseDocumentModels
                )
                .padding(.horizontal, AppSpacing.large)
                .padding(.top, AppSpacing.small)
            }

            HStack(spacing: AppSpacing.mediumLarge) {
                attachmentMenu

                TextField(
                    inputPlaceholder,
                    text: $viewModel.currentInput,
                    axis: .vertical
                )
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        onSend()
                    }
                    .submitLabel(.send)

                toolToggleButton

                Button {
                    onComposerAction(.talk)
                } label: {
                    ZStack {
                        Circle()
                            .fill(AppColors.primaryAccent.opacity(0.12))
                        Image(systemName: "waveform")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppColors.primaryAccent)
                    }
                    .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Talk")

                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(AppTypography.system28)
                        .foregroundColor(
                            canSendCurrentTurn ? AppColors.primaryAccent : AppColors.statusGray
                        )
                }
                .disabled(!canSendCurrentTurn)
                .background {
                    if #available(iOS 26.0, macOS 26.0, *) {
                        Circle()
                            .fill(.clear)
                            .glassEffect(.regular.interactive())
                    }
                }
            }
            .padding(AppSpacing.large)
            .background(AppColors.backgroundPrimary)
            .animation(.easeInOut(duration: AppLayout.animationFast), value: isTextFieldFocused)
        }
    }

    private var attachmentMenu: some View {
        Menu {
            Button {
                onComposerAction(.attachFile)
            } label: {
                Label("Attach document", systemImage: "doc.badge.plus")
            }

            Button {
                onComposerAction(.attachPhoto)
            } label: {
                Label("Attach image", systemImage: "photo")
            }

            Button {
                onComposerAction(.takePhoto)
            } label: {
                Label("Live camera", systemImage: "livephoto")
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(AppTypography.system28)
                .foregroundColor(AppColors.textSecondary)
        }
        .accessibilityLabel("Attach")
    }

    private var inputPlaceholder: String {
        if imageAttachment != nil {
            return "Ask about this image..."
        }
        if documentAttachment != nil {
            return "Ask about this document..."
        }
        return "Type a message..."
    }

    private var toolToggleButton: some View {
        Button {
            toolSettingsViewModel.toolCallingEnabled.toggle()
        } label: {
            ZStack {
                Circle()
                    .fill(
                        viewModel.useToolCalling
                            ? AppColors.primaryAccent.opacity(0.14)
                            : AppColors.backgroundSecondary
                    )
                Image(systemName: "safari")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(
                        viewModel.useToolCalling
                            ? AppColors.primaryAccent
                            : AppColors.textSecondary
                    )
            }
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.useToolCalling ? "Disable web tools" : "Enable web tools")
    }

    // MARK: - Badges

    private var thinkingModeBadge: some View {
        Button {
            settingsViewModel.thinkingModeEnabled.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.min.fill")
                    .font(.system(size: 10))
                Text("Thinking")
                    .font(AppTypography.caption2)
            }
            .foregroundColor(AppColors.primaryPurple)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(AppColors.primaryPurple.opacity(0.1))
            .cornerRadius(6)
        }
    }

    private var toolCallingBadge: some View {
        Button {
            toolSettingsViewModel.toolCallingEnabled.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "safari")
                    .font(.system(size: 10))
                Text(toolSettingsViewModel.registeredTools.isEmpty ? "Setting up tools" : "Web/tools on")
                    .font(AppTypography.caption2)
            }
            .foregroundColor(AppColors.primaryAccent)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(AppColors.primaryAccent.opacity(0.1))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private var loraAdapterBadge: some View {
        Button {
            Task { await viewModel.refreshAvailableAdapters() }
            showingLoRAManagement = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                Text("LoRA x\(viewModel.loraAdapters.count)")
                    .font(AppTypography.caption2)
            }
            .foregroundColor(.purple)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.purple.opacity(0.1))
            .cornerRadius(6)
        }
    }

    private var loraAddButton: some View {
        Button {
            Task { await viewModel.refreshAvailableAdapters() }
            showingLoRAManagement = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                Text("LoRA")
                    .font(AppTypography.caption2)
            }
            .foregroundColor(AppColors.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppColors.backgroundSecondary)
            .cornerRadius(6)
        }
    }
}

private struct ImageAttachmentPill: View {
    let attachment: ChatImageAttachment
    let isVisionModelReady: Bool
    let onRemove: () -> Void
    let onChooseVisionModel: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.mediumLarge) {
            thumbnail

            VStack(alignment: .leading, spacing: 2) {
                Text("Image attached")
                    .font(AppTypography.subheadlineMedium)
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)
                Text(isVisionModelReady ? "Ready for a question" : "Choose a vision model")
                    .font(AppTypography.caption)
                    .foregroundColor(isVisionModelReady ? AppColors.statusGreen : AppColors.primaryAccent)
                    .lineLimit(1)
            }

            Spacer(minLength: AppSpacing.small)

            if !isVisionModelReady {
                Button("Model", action: onChooseVisionModel)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.primaryAccent)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(AppColors.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove image")
        }
        .padding(AppSpacing.smallMedium)
        .background(AppColors.backgroundSecondary)
        .cornerRadius(AppSpacing.cornerRadiusRegular)
    }

    @ViewBuilder private var thumbnail: some View {
        #if canImport(UIKit)
        if let image = UIImage(data: attachment.data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        } else {
            fallbackThumbnail
        }
        #elseif canImport(AppKit)
        if let image = NSImage(data: attachment.data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        } else {
            fallbackThumbnail
        }
        #else
        fallbackThumbnail
        #endif
    }

    private var fallbackThumbnail: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(AppColors.primaryAccent.opacity(0.12))
            .frame(width: 42, height: 42)
            .overlay(
                Image(systemName: "photo")
                    .foregroundColor(AppColors.primaryAccent)
            )
    }
}

private struct DocumentAttachmentPill: View {
    let attachment: ChatDocumentAttachment
    let areModelsReady: Bool
    let onRemove: () -> Void
    let onChooseModels: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.mediumLarge) {
            RoundedRectangle(cornerRadius: 7)
                .fill(AppColors.primaryPurple.opacity(0.12))
                .frame(width: 42, height: 42)
                .overlay(
                    Image(systemName: "doc.text")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppColors.primaryPurple)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .font(AppTypography.subheadlineMedium)
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(areModelsReady ? "Ready for questions" : "Choose document models")
                    .font(AppTypography.caption)
                    .foregroundColor(areModelsReady ? AppColors.statusGreen : AppColors.primaryAccent)
                    .lineLimit(1)
            }

            Spacer(minLength: AppSpacing.small)

            if !areModelsReady {
                Button("Models", action: onChooseModels)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.primaryAccent)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(AppColors.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove document")
        }
        .padding(AppSpacing.smallMedium)
        .background(AppColors.backgroundSecondary)
        .cornerRadius(AppSpacing.cornerRadiusRegular)
    }
}

private struct StarterPromptChip: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.subheadlineMedium)
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 160, alignment: .leading)
            .padding(.horizontal, AppSpacing.large)
            .padding(.vertical, AppSpacing.mediumLarge)
            .background(AppColors.backgroundPrimary)
            .cornerRadius(AppSpacing.cornerRadiusRegular)
            .shadow(color: AppColors.shadowLight, radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}
