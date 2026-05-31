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
        VStack(spacing: 16) {
            Spacer()

            Image("runanywhere_logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)

            VStack(spacing: 8) {
                Text("Start a conversation")
                    .font(AppTypography.title2Semibold)
                    .foregroundColor(AppColors.textPrimary)

                Text("Type a message below to get started")
                    .font(AppTypography.subheadline)
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Message List

    private var messageListView: some View {
        LazyVStack(spacing: AppSpacing.large) {
            Spacer(minLength: 20)
                .id("top-spacer")

            ForEach(viewModel.messages) { message in
                MessageBubbleView(message: message, isGenerating: viewModel.isGenerating)
                    .id(message.id)
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

                if viewModel.useToolCalling && !toolSettingsViewModel.registeredTools.isEmpty {
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
                    || hasModelSelected) ? 8 : 0
            )

            HStack(spacing: AppSpacing.mediumLarge) {
                TextField("Type a message...", text: $viewModel.currentInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        onSend()
                    }
                    .submitLabel(.send)

                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(AppTypography.system28)
                        .foregroundColor(
                            viewModel.canSend ? AppColors.primaryAccent : AppColors.statusGray
                        )
                }
                .disabled(!viewModel.canSend)
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
        HStack(spacing: 6) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 10))
            Text("Tools enabled")
                .font(AppTypography.caption2)
        }
        .foregroundColor(AppColors.primaryAccent)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(AppColors.primaryAccent.opacity(0.1))
        .cornerRadius(6)
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
