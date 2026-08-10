//
//  ChatTopBar.swift
//  RunAnywhereAI
//
//  The iPhone chat header: chats, the loaded model, new chat.
//
//  iOS-only by construction. The Mac gets these three facts from the window it
//  already has — `MacSidebar` for chats, `.navigationTitle` +
//  `.navigationSubtitle` for identity, and the sidebar's compose button for a
//  new chat — so painting a second strip beneath the unified title bar there
//  would duplicate every one of them.
//
//  Split out of `ChatInterfaceView`, which was carrying the shell, the toolbar,
//  the sheets, the file importers, and this bar in one 900-line file. Extracted
//  as a value type with explicit inputs rather than an extension: the bar reads
//  four facts and raises three intents, and saying so in a signature is what
//  makes it reviewable in isolation.
//

#if os(iOS)
import SwiftUI
import RunAnywhere

/// What the header needs to know about the model that answers.
///
/// A struct rather than five loose parameters so a new fact (a second backend, a
/// warming state) is one field here instead of a fifth argument at the call site
/// — and so the header never reaches into `LLMViewModel` for something it wasn't
/// given.
struct ChatModelSummary {
    let name: String?
    let isLoading: Bool
    let backendLabel: String
    let backendIcon: String
    let backendColor: Color

    /// Whether to show a spinner instead of an identity: loading is only worth
    /// announcing while there is no model to name. Swapping a named model for
    /// "Loading model…" mid-conversation loses more than it says.
    var showsLoadingState: Bool { isLoading && name == nil }
}

struct ChatTopBar: View {
    let model: ChatModelSummary
    let onOpenChats: () -> Void
    let onChooseModel: () -> Void
    let onNewChat: () -> Void

    var body: some View {
        HStack(spacing: Space.sm) {
            iconCircleButton(systemImage: "line.3.horizontal", action: onOpenChats)
                .accessibilityLabel("Chats")

            Spacer(minLength: Space.sm)

            modelChip

            Spacer(minLength: Space.sm)

            iconCircleButton(systemImage: "square.and.pencil", action: onNewChat)
                .accessibilityLabel("New Chat")
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.separator)
                .frame(height: Hairline.width)
        }
    }

    // MARK: - Model Chip

    /// The center control: what is answering, and a way to change it.
    private var modelChip: some View {
        Button {
            Haptics.light()
            onChooseModel()
        } label: {
            HStack(spacing: Space.sm) {
                chipContent
            }
            .padding(.horizontal, Space.md)
            .frame(height: Measure.hitTarget)
            .background(Capsule().fill(AppColors.backgroundSecondary))
            .overlay(Capsule().strokeBorder(AppColors.separator, lineWidth: Hairline.width))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder private var chipContent: some View {
        if model.showsLoadingState {
            ProgressView()
                .controlSize(.small)
            Text("Loading model…")
                .appType(.caption)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
        } else if let name = model.name {
            Image(getModelLogo(for: name))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))

            VStack(alignment: .leading, spacing: Space.hair) {
                Text(name.shortModelName(maxLength: 16))
                    .appType(.caption)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: Space.hair) {
                    Image(systemName: model.backendIcon)
                        .font(.system(size: 9))
                    Text(model.backendLabel)
                        .appType(.caption)
                }
                .foregroundStyle(model.backendColor)
            }
        } else {
            Image(systemName: "cube")
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)
            Text("Choose Model")
                .appType(.caption)
                .foregroundStyle(AppColors.textPrimary)
        }
    }

    private var accessibilityLabel: String {
        if model.showsLoadingState { return "Loading model" }
        guard let name = model.name else { return "Choose a model" }
        return "\(name), \(model.backendLabel). Choose a different model"
    }

    // MARK: - Icon Buttons

    private func iconCircleButton(systemImage: String, action: @escaping () -> Void) -> some View {
        let tap = {
            Haptics.light()
            action()
        }
        return Button(action: tap) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .frame(width: Measure.hitTarget, height: Measure.hitTarget)
                .background(
                    Circle()
                        .fill(AppColors.backgroundSecondary)
                        .overlay(Circle().strokeBorder(AppColors.separator, lineWidth: Hairline.width))
                )
        }
        .buttonStyle(.plain)
    }
}
#endif
