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
    @State private var isSearchingChats = false
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
            drawerActions

            if isSearchingChats {
                Divider()
                searchField
                conversationList
            } else {
                Spacer(minLength: 0)
            }
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

    private var drawerActions: some View {
        VStack(spacing: AppSpacing.smallMedium) {
            drawerActionButton(
                title: "New Chat",
                subtitle: "Start a clean conversation",
                systemImage: "square.and.pencil",
                accent: AppColors.primaryAccent,
                action: onCreateConversation
            )

            drawerActionButton(
                title: "Search Chats",
                subtitle: "Find saved conversations",
                systemImage: "magnifyingglass",
                accent: AppColors.primaryAccent
            ) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isSearchingChats = true
                }
                DispatchQueue.main.async {
                    isSearchFocused = true
                }
            }

            drawerActionButton(
                title: "Settings",
                subtitle: "Models, tools, privacy, and downloads",
                systemImage: "gearshape.fill",
                accent: AppColors.primaryAccent,
                action: onOpenSettings
            )
        }
        .padding(.horizontal, AppSpacing.large)
        .padding(.bottom, AppSpacing.large)
    }

    private func drawerActionButton(
        title: String,
        subtitle: String,
        systemImage: String,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.mediumLarge) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(accent)
                    .frame(width: 28, height: 28)
                    .background(accent.opacity(0.12))
                    .cornerRadius(AppSpacing.cornerRadiusMedium)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(AppTypography.subheadlineMedium)
                        .foregroundColor(AppColors.textPrimary)
                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding(.horizontal, AppSpacing.mediumLarge)
            .padding(.vertical, AppSpacing.mediumLarge)
            .background(AppColors.backgroundSecondary)
            .cornerRadius(AppSpacing.cornerRadiusRegular)
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
        .background(AppColors.backgroundSecondary)
        .cornerRadius(AppSpacing.cornerRadiusRegular)
        .padding(.horizontal, AppSpacing.large)
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
