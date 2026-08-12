//
//  ContentView.swift
//  RunAnywhereAI
//
//  Consumer assistant shell. Chat is the product; advanced SDK demos live behind
//  the sidebar's Library section instead of top-level tabs.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        Group {
            #if os(macOS)
            ConsumerMacShell()
            #else
            ConsumerCompactShell()
            #endif
        }
        // `.tint` and not `.accentColor`: the latter is deprecated and, on
        // macOS, does not reach controls that read the tint from the
        // environment (sidebar selection, toolbar buttons, Form switches).
        .tint(AppColors.primaryAccent)
    }
}

#if os(macOS)
private struct ConsumerMacShell: View {
    @StateObject private var store = ConversationStore.shared
    @State private var viewModel = LLMViewModel()
    // Sidebar width and selection survive a relaunch because a window that
    // reopens with the columns the user left is the difference between a
    // document app and a demo.
    @SceneStorage("mac.sidebar.visibility") private var storedVisibility: String?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selection: MacSidebarSelection?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            MacSidebar(
                store: store,
                selection: $selection,
                onNewConversation: newConversation
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear(perform: restoreState)
        .onChange(of: columnVisibility) { _, visibility in
            storedVisibility = visibility == .detailOnly ? "detailOnly" : "all"
        }
        // The canvas wants the whole window. A 260pt sidebar next to a graph
        // editor is the first thing that makes it feel cramped, so entering
        // Workflows collapses it and leaving restores it.
        .onChange(of: selection) { oldValue, newValue in
            if newValue == .workflows {
                columnVisibility = .detailOnly
            } else if oldValue == .workflows {
                columnVisibility = .all
            }
        }
        .onChange(of: selection) { _, newValue in
            switch newValue {
            case .conversation(let id):
                guard let conversation = store.loadConversation(id) else { return }
                viewModel.loadConversation(conversation)
            case .chat:
                // `.chat` is an intent ("show me the transcript"), not a place.
                // Resolving it to the open conversation keeps exactly one row
                // highlighted for one destination — two rows lighting up for the
                // same detail view is how a sidebar starts to feel arbitrary.
                if let id = viewModel.currentConversation?.id {
                    selection = .conversation(id)
                }
            case .models, .workflows, .advanced, .none:
                break
            }
        }
        // Keep the sidebar's highlight on whichever conversation the chat is
        // actually showing, including one created from ⌘N or from the composer.
        .onChange(of: viewModel.currentConversation?.id) { _, id in
            guard let id else { return }
            if case .conversation(let selected) = selection, selected == id { return }
            selection = .conversation(id)
        }
        // The shell owns which column is showing, so the View menu's ⌘1/⌘2/⌘3
        // are published from here rather than from the chat — the chat cannot
        // navigate away from itself.
        .focusedSceneValue(\.shellNavigationActions, ShellNavigationActions(
            showChat: showChat,
            showModels: { selection = .models },
            showAdvanced: { selection = .advanced }
        ))
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .models:
            NavigationStack { SimplifiedModelsView() }
        case .workflows:
            NavigationStack { WorkflowCanvasView() }
        case .advanced:
            NavigationStack { ConsumerAdvancedHubView() }
        case .chat, .conversation, .none:
            ChatInterfaceView(viewModel: viewModel)
        }
    }

    private func newConversation() {
        viewModel.createNewConversation()
        if let id = viewModel.currentConversation?.id {
            selection = .conversation(id)
        }
    }

    /// Return to the transcript without discarding it. Falls back to `.chat`
    /// when nothing has been saved yet, so ⌘1 always lands somewhere real.
    private func showChat() {
        if let id = viewModel.currentConversation?.id {
            selection = .conversation(id)
        } else {
            selection = .chat
        }
    }

    private func restoreState() {
        if storedVisibility == "detailOnly" {
            columnVisibility = .detailOnly
        }
        guard selection == nil else { return }
        // Never leave the sidebar with nothing highlighted: a split view whose
        // first column has no selection reads as "not loaded yet".
        selection = viewModel.currentConversation.map { .conversation($0.id) } ?? .chat
    }
}
#else
private struct ConsumerCompactShell: View {
    var body: some View {
        ChatInterfaceView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif

#Preview {
    ContentView()
}
