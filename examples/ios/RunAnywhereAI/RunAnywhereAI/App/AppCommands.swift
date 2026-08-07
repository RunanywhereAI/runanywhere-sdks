//
//  AppCommands.swift
//  RunAnywhereAI
//
//  The Mac menu bar.
//
//  A Mac app whose File menu contains nothing but "Close" is not a Mac app. Every
//  action the window's toolbar offers has a keyboard route here, and every action
//  reaches the focused scene through `ChatSceneActions` rather than through a
//  global singleton — so a second window drives its own conversation.
//

import SwiftUI

#if os(macOS)

/// Actions the focused chat scene publishes to the menu bar.
///
/// `nil` closures disable their menu item automatically (the `Button` is created
/// with `action: {}` and `.disabled(true)`), which is how the menu stays honest
/// about what is possible right now.
struct ChatSceneActions {
    var newConversation: (() -> Void)?
    var openConversationList: (() -> Void)?
    var loadModel: (() -> Void)?
    var showChatDetails: (() -> Void)?
    var importDocument: (() -> Void)?
    var stopGeneration: (() -> Void)?
    var focusComposer: (() -> Void)?
}

struct ChatSceneActionsKey: FocusedValueKey {
    typealias Value = ChatSceneActions
}

extension FocusedValues {
    var chatSceneActions: ChatSceneActions? {
        get { self[ChatSceneActionsKey.self] }
        set { self[ChatSceneActionsKey.self] = newValue }
    }
}

struct AppCommands: Commands {
    @FocusedValue(\.chatSceneActions) private var actions

    var body: some Commands {
        // Replacing `.newItem` drops AppKit's default "New" (which would open a
        // second empty window before the SDK is up) and puts conversation
        // creation on ⌘N, where a chat app belongs.
        CommandGroup(replacing: .newItem) {
            menuButton("New Conversation", key: "n", action: actions?.newConversation)
            Divider()
            menuButton("Import Document…", key: "o", action: actions?.importDocument)
        }

        CommandMenu("Model") {
            menuButton("Load Model…", key: "l", modifiers: [.command, .shift], action: actions?.loadModel)
            Divider()
            menuButton("Stop Generating", key: ".", action: actions?.stopGeneration)
        }

        CommandGroup(after: .toolbar) {
            menuButton("Conversations", key: "1", action: actions?.openConversationList)
            menuButton("Chat Details", key: "i", action: actions?.showChatDetails)
            Divider()
            menuButton("Focus Composer", key: "\r", modifiers: [.command, .shift], action: actions?.focusComposer)
        }

        // The sidebar toggle and the standard text-editing verbs (⌘Z, ⌘C,
        // Emoji & Symbols) are AppKit's job — SwiftUI only installs them if
        // asked.
        SidebarCommands()
        TextEditingCommands()

        CommandGroup(replacing: .help) {
            if let url = URL(string: "https://docs.runanywhere.ai") {
                Link("RunAnywhere Documentation", destination: url)
            }
        }
    }

    @ViewBuilder
    private func menuButton(
        _ title: String,
        key: KeyEquivalent,
        modifiers: EventModifiers = .command,
        action: (() -> Void)?
    ) -> some View {
        Button(title) { action?() }
            .keyboardShortcut(key, modifiers: modifiers)
            .disabled(action == nil)
    }
}

#endif
