//
//  ConversationDrawerView.swift
//  RunAnywhereAI
//
//  Lightweight consumer drawer for chat creation, search, and settings.
//

import Foundation
import SwiftUI

struct ConversationDrawerView: View {
    @StateObject private var store = ConversationStore.shared
    @State private var searchQuery = ""
    @State private var conversationToDelete: Conversation?
    @State private var showingDeleteConfirmation = false
    @FocusState private var isSearchFocused: Bool

    let onSelectConversation: (Conversation) -> Void
    let onCreateConversation: () -> Void
    let onOpenSettings: () -> Void
    let onOpenMore: () -> Void
    let onClose: () -> Void

    private var filteredConversations: [Conversation] {
        store.searchConversations(query: searchQuery.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        VStack(spacing: 0) {
            drawerHeader
            searchField

            Text("Recent")
                .font(AppTypography.caption2Bold)
                .foregroundColor(AppColors.textSecondary)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppSpacing.large)
                .padding(.top, AppSpacing.smallMedium)

            conversationList

            Divider()

            moreRow
            settingsRow
        }
        .background(AppColors.backgroundPrimary)
        .alert("Delete Conversation?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { conversationToDelete = nil }
            Button("Delete", role: .destructive) {
                if let conversationToDelete {
                    store.deleteConversation(conversationToDelete)
                }
                conversationToDelete = nil
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private var drawerHeader: some View {
        HStack(spacing: AppSpacing.mediumLarge) {
            Image("runanywhere_logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text("RunAnywhere")
                    .font(AppTypography.headline)
                Text("Private assistant")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: AdaptiveSizing.toolbarButtonSize, height: AdaptiveSizing.toolbarButtonSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, AppSpacing.large)
        .padding(.top, AppSpacing.large)
        .padding(.bottom, AppSpacing.mediumLarge)
    }

    private var moreRow: some View {
        drawerFooterRow(icon: "square.grid.2x2", title: "More", action: onOpenMore)
    }

    private var settingsRow: some View {
        drawerFooterRow(icon: "gearshape.fill", title: "Settings", action: onOpenSettings)
    }

    private func drawerFooterRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: AppSpacing.mediumLarge) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppColors.textSecondary)
                    .frame(width: 20)

                Text(title)
                    .font(AppTypography.subheadlineMedium)
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.vertical, AppSpacing.regular)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: AppSpacing.smallMedium) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppColors.textSecondary)

            TextField("Search chats", text: $searchQuery)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, AppSpacing.mediumLarge)
        .padding(.vertical, AppSpacing.medium)
        .background(AppColors.backgroundGray5)
        .cornerRadius(AppSpacing.cornerRadiusLarge)
        .padding(.horizontal, AppSpacing.large)
        .padding(.top, AppSpacing.mediumLarge)
        .padding(.bottom, AppSpacing.mediumLarge)
    }

    private var conversationList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                if filteredConversations.isEmpty {
                    emptyState
                } else {
                    ForEach(filteredConversations) { conversation in
                        DrawerConversationRow(
                            conversation: conversation,
                            isSelected: store.currentConversation?.id == conversation.id
                        ) {
                            Haptics.selection()
                            onSelectConversation(conversation)
                        } onDelete: {
                            conversationToDelete = conversation
                            showingDeleteConfirmation = true
                        }
                    }
                }
            }
            .padding(.horizontal, AppSpacing.xSmall)
            .padding(.top, AppSpacing.xSmall)
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.mediumLarge) {
            Image(systemName: searchQuery.isEmpty ? "bubble.left.and.bubble.right" : "magnifyingglass")
                .font(AppTypography.system28)
                .foregroundColor(AppColors.textSecondary.opacity(0.5))
            Text(searchQuery.isEmpty ? "No chats yet" : "No chats found")
                .font(AppTypography.subheadlineMedium)
                .foregroundColor(AppColors.textPrimary)
            Text(searchQuery.isEmpty ? "Start a new private conversation." : "Try a different keyword.")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xxxLarge)
    }

}

private struct DrawerConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: AppSpacing.mediumLarge) {
                Text(conversation.title)
                    .font(AppTypography.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: AppSpacing.smallMedium)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppColors.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete chat")
            }
            .padding(.leading, AppSpacing.large)
            .padding(.trailing, AppSpacing.xSmall)
            .padding(.vertical, AppSpacing.medium)
            .background(isSelected ? AppColors.primaryAccent.opacity(0.10) : Color.clear)
            .cornerRadius(AppSpacing.cornerRadiusLarge)
        }
        .buttonStyle(.plain)
    }
}
