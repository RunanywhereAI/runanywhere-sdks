//
//  ChatMessageListView.swift
//  RunAnywhereAI
//
//  The transcript and the composer.
//
//  Two things here are deliberate and easy to undo by accident:
//
//  1. **Zero scroll drivers.** There used to be six (`messages.count`,
//     `isGenerating`, focus + a 0.3s `asyncAfter`, `keyboardWillShow` + a 0.1s
//     `asyncAfter`, `last?.content`, `last?.thinkingContent`) all calling
//     `scrollTo` on one proxy, three of them animated. They fought each other: a
//     token arriving mid-animation restarted the 0.5s curve, so a fast reply
//     scrolled in visible lurches. Collapsing them to one coalesced `scrollTo`
//     fixed the lurching but not the underlying problem: `scrollTo(_, anchor:
//     .bottom)` on a transcript **shorter than the viewport** overscrolls past
//     the end, so the first reply of a chat landed entirely above the visible
//     region and the screen read as blank until you dragged it back. Verified on
//     an iPhone 17 Pro: send one message, get a full reply, see nothing.
//     `.defaultScrollAnchor(.bottom)` alone does the whole job — it pins content
//     to the bottom edge *and* holds that alignment as the content grows, with
//     no offset arithmetic to get wrong at either size.
//  2. **The reading measure.** `Measure.text` caps both the transcript and the
//     composer. Without it a 3456pt Mac window sets one line of prose across the
//     whole display, which is unreadable and the loudest "this is a phone app in
//     a window" tell in the build.
//

import SwiftUI
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
    /// Attach whatever is on the clipboard. Also reachable with ⌘V on the Mac;
    /// the menu item is what makes it discoverable on a phone, which has no
    /// keyboard shortcut and no other way to hand a screenshot to the chat.
    case pasteAttachment
    case talk
}

// MARK: - Chat Messages View

struct ChatMessageListView: View {
    @Bindable var viewModel: LLMViewModel
    @FocusState.Binding var isTextFieldFocused: Bool
    @Binding var showingLoRAManagement: Bool
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var toolSettingsViewModel: ToolSettingsViewModel

    private var isEmpty: Bool {
        viewModel.messages.isEmpty && !viewModel.isGenerating
    }

    var body: some View {
        // `GeometryReader` for one number: the viewport height, which the content
        // below claims as a *minimum*. Without it `.defaultScrollAnchor(.bottom)`
        // pins a two-message transcript to the composer and leaves ~860pt of void
        // above it in a 1034pt Mac window — measured on the real app. Claiming
        // the viewport height with `alignment: .top` makes bottom-anchoring a
        // no-op while the transcript is short (it starts at the top and grows
        // down, as every assistant does) and hands scrolling back the moment the
        // content genuinely overflows.
        GeometryReader { proxy in
            ScrollView {
                if isEmpty {
                    emptyStateView
                        .frame(minHeight: proxy.size.height, alignment: .center)
                } else {
                    messageListView
                        .frame(minHeight: proxy.size.height, alignment: .top)
                }
            }
            // Scrolling stays enabled even on the empty state. It was disabled to
            // stop an idle screen rubber-banding, but raising the keyboard halves
            // the viewport, and a centered empty state taller than that gets its
            // greeting clipped under the header with no way to reach it.
            .defaultScrollAnchor(isEmpty ? .center : .bottom)
            .background(AppColors.backgroundGrouped)
            .contentShape(Rectangle())
            .onTapGesture { isTextFieldFocused = false }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: Space.xl) {
            // The shared figure, so the empty transcript is recognisably the same
            // object as every other empty state in the app. 96pt rather than the
            // 132pt hero: this state also carries four starter prompts, and a
            // full-size mark pushed them below the fold on the shortest phone.
            EmptyStateMark(systemImage: "bubble.left.and.bubble.right", diameter: 96)

            VStack(spacing: Space.sm) {
                Text(emptyStateGreeting)
                    .appType(.title)
                    .foregroundStyle(AppColors.textPrimary)

                Text("Ask anything — everything runs privately on your device.")
                    .appType(.secondary)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            starterPrompts
        }
        .padding(.horizontal, Space.screenMargin)
        .padding(.vertical, Space.xxl)
        .measured(Measure.text)
    }

    private var emptyStateGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<5: return "Working late?"
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    /// `.adaptive` rather than two fixed columns: two columns in a 1200pt Mac
    /// window stretched each chip to 500pt of mostly empty card, and two columns
    /// on a phone in landscape clipped the subtitles.
    private var starterPrompts: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 200, maximum: 320), spacing: Space.md)],
            spacing: Space.md
        ) {
            ForEach(StarterPrompt.all) { prompt in
                StarterPromptChip(prompt: prompt) {
                    viewModel.currentInput = prompt.text
                    isTextFieldFocused = true
                }
            }
        }
    }

    // MARK: - Message List

    private var messageListView: some View {
        LazyVStack(spacing: Space.xl) {
            ForEach(viewModel.messages) { message in
                MessageBubbleView(
                    message: message,
                    isStreamingTail: viewModel.isGenerating
                        && message.role == .assistant
                        && message.id == viewModel.messages.last?.id,
                    isLatestTurn: message.id == viewModel.messages.last?.id,
                    loadedModelSupportsThinking: viewModel.loadedModelSupportsThinking,
                    actions: actions(for: message)
                )
                .id(message.id)
                .transition(.messageInsert)
            }
        }
        .padding(.horizontal, Space.screenMargin)
        .padding(.vertical, Space.xl)
        .measured(Measure.text)
        .motionAware(Motion.standardSpring, value: viewModel.messages.count)
    }

    /// Which actions a turn offers.
    ///
    /// Everything is withheld while a generation is running: regenerating or
    /// deleting a message the in-flight turn is indexed against would leave that
    /// turn writing into the wrong slot. Copy always stays, since the bubble owns
    /// it and it mutates nothing.
    private func actions(for message: Message) -> MessageActions {
        guard !viewModel.isGenerating else { return .none }

        let id = message.id
        let delete = { viewModel.deleteMessage(id: id) }

        switch message.role {
        case .assistant:
            // An error bubble is UI feedback, not a reply — retrying the question
            // is the useful action, so it keeps Regenerate.
            let regenerate = { viewModel.regenerateReply(messageID: id) }
            return MessageActions(regenerate: regenerate, edit: nil, delete: delete)

        case .user:
            let edit = {
                viewModel.editQuestion(messageID: id)
                // The question lands in the composer; taking focus with it is
                // what makes this an edit rather than a puzzle.
                isTextFieldFocused = true
            }
            return MessageActions(regenerate: nil, edit: edit, delete: delete)

        case .system:
            return .none
        }
    }
}

// MARK: - Starter Prompts

/// The four things a consumer opens an on-device assistant to do.
///
/// `title` is the shared label — the same string Android's `generalSuggestions` and the web's
/// `STARTER_PROMPTS` show — so the same chip is recognisable on all three. It used to be a
/// single word ("Plan"), which made the four chips look like a different feature from the
/// two-word set on the other two apps. `subtitle` is this platform's extra line and qualifies
/// the label rather than repeating it. A value type
/// rather than four hand-built call sites, so the grid stays one `ForEach` and
/// the copy lives in one place.
struct StarterPrompt: Identifiable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    let text: String

    static let all: [StarterPrompt] = [
        StarterPrompt(
            id: "plan",
            icon: "list.bullet.clipboard",
            title: "Plan my day",
            subtitle: "from messy notes",
            text: "Turn this messy list into a realistic plan with the top three priorities:"
        ),
        StarterPrompt(
            id: "rewrite",
            icon: "pencil.line",
            title: "Rewrite clearly",
            subtitle: "warm and concise",
            text: "Rewrite this so it is clear, warm, and concise:"
        ),
        StarterPrompt(
            id: "compare",
            icon: "arrow.left.arrow.right",
            title: "Compare options",
            subtitle: "weigh the tradeoffs",
            text: "Compare these options, explain the tradeoffs, and recommend one:"
        ),
        StarterPrompt(
            id: "summarize",
            icon: "checklist",
            title: "Summarize notes",
            subtitle: "into next steps",
            text: "Summarize these notes into decisions, action items, and open questions:"
        )
    ]
}

private struct StarterPromptChip: View {
    let prompt: StarterPrompt
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: Space.md) {
                Image(systemName: prompt.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppColors.primaryAccent)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: Space.hair) {
                    Text(prompt.title)
                        .appType(.cardTitle)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    Text(prompt.subtitle)
                        .appType(.meta)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.cardPadding)
            .cardSurface(radius: Radius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(
                        isHovering ? AppColors.primaryAccent.opacity(0.45) : .clear,
                        lineWidth: Stroke.regular
                    )
            )
            // Hover lifts the card a hair off the page. On a Mac, a border that
            // changes color is easy to miss on a grid of four; a card that rises
            // is unmistakable, and it says "this is pressable" rather than just
            // "the pointer is here". No-op on a phone, which has no hover.
            .shadow(
                color: AppColors.primaryAccent.opacity(isHovering ? 0.18 : 0),
                radius: isHovering ? 12 : 0,
                y: isHovering ? 4 : 0
            )
            .scaleEffect(isHovering ? 1.012 : 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        // `micro`, not `standard`: hover feedback slower than ~150ms lags the
        // pointer, and on a grid the reader notices the lag before the lift.
        .motionAware(Motion.microFade, value: isHovering)
    }
}

// MARK: - Message Insert Transition

extension AnyTransition {
    /// A new turn rises into place. Asymmetric because a removal that mirrors
    /// the insert reads as an undo rather than a delete.
    static var messageInsert: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 12)),
            removal: .opacity.combined(with: .scale(scale: 0.96))
        )
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

    private var hasText: Bool {
        !viewModel.currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: Space.sm) {
            if !activeBadges.isEmpty {
                HStack(spacing: Space.sm) {
                    ForEach(activeBadges) { badge in
                        badgeView(badge)
                    }
                    Spacer(minLength: 0)
                }
            }

            if let imageAttachment {
                ImageAttachmentPill(
                    attachment: imageAttachment,
                    isVisionModelReady: isVisionModelReady,
                    onRemove: onRemoveImageAttachment,
                    onChooseVisionModel: onChooseVisionModel
                )
            }

            if let documentAttachment {
                DocumentAttachmentPill(
                    attachment: documentAttachment,
                    areModelsReady: areDocumentModelsReady,
                    onRemove: onRemoveDocumentAttachment,
                    onChooseModels: onChooseDocumentModels
                )
            }

            composerRow
        }
        .padding(.horizontal, Space.screenMargin)
        .padding(.top, Space.md)
        .padding(.bottom, Space.lg)
        .measured(Measure.text)
        .background(AppColors.backgroundGrouped)
        .motionAware(Motion.snappy, value: composerLayoutSignature)
    }

    /// Everything that changes the composer's height, in one value — so growth
    /// animates once instead of four modifiers each animating a different
    /// subview at a different speed.
    private var composerLayoutSignature: String {
        let badges = activeBadges.map(\.id).joined(separator: ",")
        return "\(badges)|\(imageAttachment == nil)|\(documentAttachment == nil)"
    }

    // MARK: - Composer Row

    private var composerRow: some View {
        HStack(alignment: .bottom, spacing: Space.sm) {
            composerMenu

            TextField(inputPlaceholder, text: $viewModel.currentInput, axis: .vertical)
                .textFieldStyle(.plain)
                .appType(.body)
                .lineLimit(1...6)
                .padding(.vertical, Space.sm)
                .focused($isTextFieldFocused)
                .onSubmit(onSend)
                .submitLabel(.send)

            trailingAction
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(AppColors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(
                    isTextFieldFocused ? AppColors.primaryAccent.opacity(0.5) : AppColors.borderSubtle,
                    lineWidth: isTextFieldFocused ? Stroke.regular : Hairline.width
                )
        )
        .motionAware(Motion.microFade, value: isTextFieldFocused)
    }

    /// Attachments and per-turn switches in one native menu.
    ///
    /// The switches used to be two always-on circular buttons in the row, which
    /// on a phone left the text field about 150pt wide and gave two rarely
    /// changed settings the same visual weight as Send. Their *state* still
    /// shows, as a badge above the composer — visible always, changed from a
    /// menu, which is the right trade for something you set once.
    private var composerMenu: some View {
        Menu {
            Section {
                Button {
                    onComposerAction(.attachFile)
                } label: {
                    Label("Attach Document", systemImage: "doc.badge.plus")
                }

                Button {
                    onComposerAction(.attachPhoto)
                } label: {
                    Label("Attach Image", systemImage: "photo")
                }

                #if os(iOS)
                Button {
                    onComposerAction(.takePhoto)
                } label: {
                    // `eye` — looking through a live feed — and not `livephoto`, which
                    // VLMCameraView already uses for the auto-streaming toggle. It is also
                    // what `RAModelCategory.consumerCapabilityIcon` returns for vision, and
                    // the glyph Android (`RACIcons.Outline.Eye`) and the web app draw here.
                    Label("Live Camera", systemImage: "eye")
                }
                #endif

                // Disabled rather than hidden when the clipboard is empty: a row
                // that appears and disappears is a control nobody learns, and it
                // is the only signal on a phone that pasting a screenshot is
                // even possible.
                Button {
                    onComposerAction(.pasteAttachment)
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .disabled(!ChatAttachmentLoader.pasteboardHasAttachment)
            }

            Section {
                Toggle(isOn: $settingsViewModel.thinkingModeEnabled) {
                    Label("Show Reasoning", systemImage: "brain")
                }
                .disabled(!viewModel.loadedModelSupportsThinking)

                Toggle(isOn: $toolSettingsViewModel.toolCallingEnabled) {
                    // `globe` — the network — rather than `safari`, one browser's mark
                    // standing in for the web. Matches the web app's `globe` and Android's
                    // new `RACIcons.Outline.Globe`.
                    Label("Web Tools", systemImage: "globe")
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        // `.button` + `.plain` rather than `.borderlessButton`: the latter is
        // deprecated on iOS in favor of exactly this pair, and the default menu
        // style paints AppKit's bordered chrome around the glyph on the Mac.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Attach or change options")
    }

    /// One slot, three states — stop while generating, send when there is
    /// something to send, otherwise voice.
    ///
    /// A single `Button` whose symbol is computed, not three sibling buttons: the
    /// slot keeps its identity, so `.contentTransition(.symbolEffect(.replace))`
    /// actually fires and the row never reflows when send becomes stop
    /// mid-sentence. A permanently dimmed Send is also a dead end; offering
    /// voice in its place makes the empty composer actionable.
    private var trailingAction: some View {
        Button {
            Haptics.light()
            switch trailingRole {
            case .stop: viewModel.stopGeneration()
            case .send: onSend()
            case .talk: onComposerAction(.talk)
            }
        } label: {
            Image(systemName: trailingRole.icon)
                .font(.system(size: 28))
                .foregroundStyle(trailingTint)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(trailingRole == .send && !canSendCurrentTurn)
        .accessibilityLabel(trailingRole.label)
        .contentTransition(.symbolEffect(.replace))
        .motionAware(Motion.snappy, value: trailingRole)
    }

    private enum TrailingRole: Equatable {
        case stop
        case send
        case talk

        var icon: String {
            switch self {
            case .stop: return "stop.circle.fill"
            case .send: return "arrow.up.circle.fill"
            case .talk: return "mic.circle.fill"
            }
        }

        var label: String {
            switch self {
            case .stop: return "Stop generating"
            case .send: return "Send message"
            case .talk: return "Talk to the assistant"
            }
        }
    }

    private var trailingRole: TrailingRole {
        if viewModel.isGenerating { return .stop }
        return hasText ? .send : .talk
    }

    private var trailingTint: Color {
        trailingRole == .send && !canSendCurrentTurn
            ? AppColors.statusGray
            : AppColors.primaryAccent
    }

    private var inputPlaceholder: String {
        if imageAttachment != nil { return "Ask about this image…" }
        if documentAttachment != nil { return "Ask about this document…" }
        return "Message"
    }

    // MARK: - Badges

    /// A live capability that changes what the next turn will do. Not a setting —
    /// state, surfaced where the turn is composed.
    private struct ComposerBadge: Identifiable {
        let id: String
        let icon: String
        let title: String
        let tint: Color
        let action: (() -> Void)?
    }

    private var activeBadges: [ComposerBadge] {
        var badges: [ComposerBadge] = []

        if settingsViewModel.thinkingModeEnabled && viewModel.loadedModelSupportsThinking {
            badges.append(
                ComposerBadge(
                    id: "thinking",
                    icon: "brain",
                    title: "Reasoning",
                    tint: AppColors.primaryPurple,
                    action: nil
                )
            )
        }

        if viewModel.useToolCalling && !viewModel.isUsingConnect {
            badges.append(
                ComposerBadge(
                    id: "tools",
                    icon: "globe",
                    title: toolSettingsViewModel.registeredTools.isEmpty ? "Preparing tools…" : "Web tools",
                    tint: AppColors.primaryAccent,
                    action: nil
                )
            )
        }

        if !viewModel.isUsingConnect && !viewModel.loraAdapters.isEmpty {
            badges.append(
                ComposerBadge(
                    id: "lora",
                    icon: "sparkles",
                    title: "LoRA ×\(viewModel.loraAdapters.count)",
                    tint: AppColors.primaryPurple
                ) {
                    Task { await viewModel.refreshAvailableAdapters() }
                    showingLoRAManagement = true
                }
            )
        }

        return badges
    }

    @ViewBuilder
    private func badgeView(_ badge: ComposerBadge) -> some View {
        let content = HStack(spacing: Space.xs) {
            Image(systemName: badge.icon)
                .font(.system(size: 10, weight: .semibold))
            Text(badge.title)
                .appType(.chip)
        }
        .foregroundStyle(badge.tint)
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs)
        .background(Capsule().fill(badge.tint.opacity(0.12)))

        if let action = badge.action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
                .accessibilityLabel("\(badge.title) is on")
        }
    }
}

// MARK: - Attachment Pills

private struct ImageAttachmentPill: View {
    let attachment: ChatImageAttachment
    let isVisionModelReady: Bool
    let onRemove: () -> Void
    let onChooseVisionModel: () -> Void

    var body: some View {
        AttachmentPillLayout(
            title: "Image attached",
            subtitle: isVisionModelReady ? "Ready for a question" : "Choose a vision model",
            isReady: isVisionModelReady,
            actionTitle: "Model",
            onAction: onChooseVisionModel,
            onRemove: onRemove,
            removeLabel: "Remove image"
        ) {
            thumbnail
        }
    }

    @ViewBuilder private var thumbnail: some View {
        #if canImport(UIKit)
        if let image = UIImage(data: attachment.data) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            fallbackThumbnail
        }
        #elseif canImport(AppKit)
        if let image = NSImage(data: attachment.data) {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            fallbackThumbnail
        }
        #else
        fallbackThumbnail
        #endif
    }

    private var fallbackThumbnail: some View {
        AppColors.primaryAccent.opacity(0.12)
            .overlay(Image(systemName: "photo").foregroundStyle(AppColors.primaryAccent))
    }
}

private struct DocumentAttachmentPill: View {
    let attachment: ChatDocumentAttachment
    let areModelsReady: Bool
    let onRemove: () -> Void
    let onChooseModels: () -> Void

    var body: some View {
        AttachmentPillLayout(
            title: attachment.filename,
            subtitle: areModelsReady ? "Ready for questions" : "Choose document models",
            isReady: areModelsReady,
            actionTitle: "Models",
            onAction: onChooseModels,
            onRemove: onRemove,
            removeLabel: "Remove document"
        ) {
            AppColors.primaryPurple.opacity(0.12)
                .overlay(
                    Image(systemName: "doc.text")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.primaryPurple)
                )
        }
    }
}

/// The two attachment pills differed only in their leading icon and their copy,
/// yet each hand-rolled the same 40 lines of layout — and drifted, so the
/// document pill truncated its title in the middle and the image pill did not.
private struct AttachmentPillLayout<Leading: View>: View {
    let title: String
    let subtitle: String
    let isReady: Bool
    let actionTitle: String
    let onAction: () -> Void
    let onRemove: () -> Void
    let removeLabel: String
    @ViewBuilder let leading: Leading

    var body: some View {
        HStack(spacing: Space.md) {
            leading
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))

            VStack(alignment: .leading, spacing: Space.hair) {
                Text(title)
                    .appType(.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .appType(.meta)
                    .foregroundStyle(isReady ? AppColors.statusGreen : AppColors.primaryAccent)
                    .lineLimit(1)
            }

            Spacer(minLength: Space.xs)

            if !isReady {
                Button(actionTitle, action: onAction)
                    .buttonStyle(.plain)
                    .appType(.meta)
                    .foregroundStyle(AppColors.primaryAccent)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(removeLabel)
        }
        .padding(Space.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(AppColors.backgroundSecondary)
        )
    }
}
