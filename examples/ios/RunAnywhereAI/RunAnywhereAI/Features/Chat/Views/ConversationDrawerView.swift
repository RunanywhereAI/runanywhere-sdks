//
//  ConversationDrawerView.swift
//  RunAnywhereAI
//
//  Lightweight consumer drawer for recents, search, settings, and new chat.
//

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
    let onClose: () -> Void

    private var filteredConversations: [Conversation] {
        store.searchConversations(query: searchQuery.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        VStack(spacing: 0) {
            drawerHeader
            searchField
            settingsButton
            conversationList
            bottomActions
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
        .background(AppColors.backgroundSecondary)
        .cornerRadius(AppSpacing.cornerRadiusRegular)
        .padding(.horizontal, AppSpacing.large)
        .padding(.bottom, AppSpacing.mediumLarge)
    }

    private var settingsButton: some View {
        Button(action: onOpenSettings) {
            HStack(spacing: AppSpacing.mediumLarge) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppColors.primaryAccent)
                    .frame(width: 28, height: 28)
                    .background(AppColors.primaryAccent.opacity(0.12))
                    .cornerRadius(AppSpacing.cornerRadiusMedium)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Settings")
                        .font(AppTypography.subheadlineMedium)
                        .foregroundColor(AppColors.textPrimary)
                    Text("Personalization, models, privacy")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.vertical, AppSpacing.mediumLarge)
        }
        .buttonStyle(.plain)
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
                            onSelectConversation(conversation)
                        } onDelete: {
                            conversationToDelete = conversation
                            showingDeleteConfirmation = true
                        }
                    }
                }
            }
            .padding(.horizontal, AppSpacing.smallMedium)
            .padding(.top, AppSpacing.smallMedium)
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

    private var bottomActions: some View {
        VStack(spacing: AppSpacing.smallMedium) {
            Divider()

            Button(action: onCreateConversation) {
                HStack {
                    Image(systemName: "square.and.pencil")
                    Text("New Chat")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(AppTypography.caption)
                }
                .font(AppTypography.subheadlineMedium)
                .foregroundColor(AppColors.textWhite)
                .padding(.horizontal, AppSpacing.large)
                .padding(.vertical, AppSpacing.mediumLarge)
                .background(AppColors.primaryAccent)
                .cornerRadius(AppSpacing.cornerRadiusRegular)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppSpacing.large)
            .padding(.bottom, AppSpacing.large)
        }
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
                Image(systemName: "message.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isSelected ? AppColors.primaryAccent : AppColors.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(
                        (isSelected ? AppColors.primaryAccent : AppColors.textSecondary)
                            .opacity(isSelected ? 0.14 : 0.08)
                    )
                    .cornerRadius(AppSpacing.cornerRadiusMedium)

                Text(conversation.title)
                    .font(AppTypography.subheadline)
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)

                Spacer()

                Menu {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppSpacing.smallMedium)
            .padding(.vertical, AppSpacing.medium)
            .background(isSelected ? AppColors.primaryAccent.opacity(0.08) : Color.clear)
            .cornerRadius(AppSpacing.cornerRadiusRegular)
        }
        .buttonStyle(.plain)
    }
}
