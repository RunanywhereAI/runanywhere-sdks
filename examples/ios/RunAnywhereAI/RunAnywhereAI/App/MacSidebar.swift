//
//  MacSidebar.swift
//  RunAnywhereAI
//
//  The Mac sidebar: three destinations, and the document list belonging to the
//  one that is open.
//
//  This replaces a modal drawer that slid over the chat and dimmed it. A drawer
//  is a phone affordance — on a 1200pt window there is room for the list and the
//  conversation at the same time, and a Mac user expects to switch chats without
//  a mode change. Destination *and* document live in one `List(selection:)` so
//  ↑/↓ walks the whole sidebar the way it does in Mail and Notes.
//
//  The list is scoped to the open destination. A sidebar that offers "Search
//  chats" and twelve conversation rows while the detail column is showing Models
//  is describing a screen the user is not looking at: the search field cannot
//  find anything they can see, and the bulk of the column is noise. So the
//  conversation list and its search field appear under Chat and nowhere else,
//  while the three destinations are always present — otherwise there would be no
//  way back.
//

import SwiftUI

#if os(macOS)

/// Which destination owns the sidebar's list right now.
enum MacSidebarScope: Hashable {
    case chat
    case models
    case workflows
    case advanced
}

/// What the detail column is showing.
enum MacSidebarSelection: Hashable {
    /// The transcript, whichever conversation is current. Distinct from
    /// `.conversation` so ⌘1 can return to the chat before anything is saved.
    case chat
    case conversation(String)
    case models
    case workflows
    case advanced

    var scope: MacSidebarScope {
        switch self {
        case .chat, .conversation: return .chat
        case .models: return .models
        case .workflows: return .workflows
        case .advanced: return .advanced
        }
    }
}

struct MacSidebar: View {
    @ObservedObject var store: ConversationStore
    @Binding var selection: MacSidebarSelection?
    let onNewConversation: () -> Void

    @State private var searchText = ""
    @State private var conversationPendingDeletion: Conversation?
    @State private var conversationBeingRenamed: Conversation?
    @State private var draftTitle = ""

    private var scope: MacSidebarScope {
        selection?.scope ?? .chat
    }

    private var conversations: [Conversation] {
        store.searchConversations(query: searchText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        Group {
            if scope == .chat {
                // `.searchable` is applied here and only here. Attaching it
                // unconditionally and swapping the prompt would still put a live
                // text field over a list that does not exist on Models.
                list.searchable(text: $searchText, placement: .sidebar, prompt: "Search chats")
            } else {
                list
            }
        }
        .navigationTitle("RunAnywhere")
        .toolbar {
            ToolbarItem {
                Button(action: onNewConversation) {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
                .help("New Chat (⌘N)")
            }
        }
        // A filter typed under Chat must not survive a trip to Models and come
        // back silently hiding rows.
        .onChange(of: scope) { _, newScope in
            if newScope != .chat { searchText = "" }
        }
        .confirmationDialog(
            "Delete this chat?",
            isPresented: Binding(
                get: { conversationPendingDeletion != nil },
                set: { if !$0 { conversationPendingDeletion = nil } }
            ),
            presenting: conversationPendingDeletion
        ) { conversation in
            Button("Delete", role: .destructive) {
                store.deleteConversation(conversation)
                conversationPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { conversationPendingDeletion = nil }
        } message: { conversation in
            Text("“\(conversation.title)” will be removed from this Mac. This can't be undone.")
        }
        .alert("Rename Chat", isPresented: Binding(
            get: { conversationBeingRenamed != nil },
            set: { if !$0 { conversationBeingRenamed = nil } }
        )) {
            TextField("Name", text: $draftTitle)
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) { conversationBeingRenamed = nil }
        }
    }

    private var list: some View {
        List(selection: $selection) {
            Section {
                Label("Chat", systemImage: "bubble.left.and.bubble.right")
                    .tag(MacSidebarSelection.chat)
                Label("Models", systemImage: "square.stack.3d.up")
                    .tag(MacSidebarSelection.models)
                Label("Workflows", systemImage: "point.3.connected.trianglepath.dotted")
                    .tag(MacSidebarSelection.workflows)
                Label("Advanced", systemImage: "slider.horizontal.3")
                    .tag(MacSidebarSelection.advanced)
            }

            if scope == .chat {
                Section("Chats") {
                    if conversations.isEmpty {
                        emptyChatsRow
                    } else {
                        ForEach(conversations) { conversation in
                            row(for: conversation)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func row(for conversation: Conversation) -> some View {
        MacConversationRow(conversation: conversation)
            .tag(MacSidebarSelection.conversation(conversation.id))
            .contextMenu {
                Button("Rename…") {
                    draftTitle = conversation.title
                    conversationBeingRenamed = conversation
                }
                Divider()
                Button("Delete", role: .destructive) {
                    conversationPendingDeletion = conversation
                }
            }
    }

    private var emptyChatsRow: some View {
        // Not `ContentUnavailableView` — that is a full-screen figure, and a
        // sidebar section needs one quiet line, not a hero.
        Text(searchText.isEmpty ? "No chats yet" : "No matches")
            .appType(.caption)
            .foregroundStyle(AppColors.textSecondary)
            .padding(.vertical, Space.xs)
    }

    private func commitRename() {
        guard var conversation = conversationBeingRenamed else { return }
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        conversationBeingRenamed = nil
        guard !trimmed.isEmpty, trimmed != conversation.title else { return }
        conversation.title = trimmed
        store.updateConversation(conversation)
    }
}

/// Two lines: what the chat is, and when it last moved. The relative date is the
/// only thing that makes a list of twelve "New Chat" rows navigable.
private struct MacConversationRow: View {
    let conversation: Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(conversation.title)
                .appType(.body)
                .lineLimit(1)

            Text(conversation.updatedAt.formatted(.relative(presentation: .named)))
                .appType(.caption)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
        }
        .padding(.vertical, 1)
    }
}

#endif
