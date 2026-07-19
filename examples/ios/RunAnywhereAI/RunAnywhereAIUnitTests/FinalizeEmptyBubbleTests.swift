//
//  FinalizeEmptyBubbleTests.swift
//  RunAnywhereAIUnitTests
//
//  finalizeGeneration drops a trailing empty assistant bubble on Stop and
//  preserves a real / partial reply. Headless state-assertion.
//

import XCTest
@testable import RunAnywhereAI

@MainActor
final class FinalizeEmptyBubbleTests: XCTestCase {

    private func makeConversation(id: String) -> Conversation {
        Conversation(
            id: id, title: "T", createdAt: Date(), updatedAt: Date(),
            messages: [], modelName: nil, frameworkName: nil,
            analytics: nil, performanceSummary: nil
        )
    }

    /// A Stop with no produced text leaves an empty assistant slot; finalize must
    /// drop it (no orphan bubble) and still clear isGenerating.
    func testFinalizeDropsEmptyAssistantBubble() async {
        let vm = LLMViewModel()
        let gid = UUID()
        vm.setCurrentConversation(makeConversation(id: "A"))
        vm.setMessages([Message(role: .user, content: "hi"),
                        Message(role: .assistant, content: "")])
        vm.setGeneratingConversationId("A")
        vm.setActiveGenerationID(gid)
        vm.setIsGenerating(true)

        await vm.finalizeGeneration(at: 1, generationID: gid)

        XCTAssertFalse(vm.isGenerating)
        XCTAssertEqual(vm.messagesValue.count, 1, "empty assistant bubble is dropped")
        XCTAssertEqual(vm.messagesValue.last?.role, .user)
    }

    /// A real (or partial-but-kept) reply has non-empty content and must NOT be
    /// dropped by the empty-bubble guard.
    func testFinalizeKeepsNonEmptyAssistantMessage() async {
        let vm = LLMViewModel()
        let gid = UUID()
        vm.setCurrentConversation(makeConversation(id: "A"))
        vm.setMessages([Message(role: .user, content: "hi"),
                        Message(role: .assistant, content: "a real answer")])
        vm.setGeneratingConversationId("A")
        vm.setActiveGenerationID(gid)
        vm.setIsGenerating(true)

        await vm.finalizeGeneration(at: 1, generationID: gid)

        XCTAssertFalse(vm.isGenerating)
        XCTAssertEqual(vm.messagesValue.count, 2, "non-empty assistant reply is preserved")
        XCTAssertEqual(vm.messagesValue.last?.content, "a real answer")
    }

    /// The helper only removes a genuinely blank trailing assistant bubble.
    func testRemoveTrailingEmptyAssistantMessageIsPrecise() {
        let vm = LLMViewModel()

        vm.setMessages([Message(role: .user, content: "q"),
                        Message(role: .assistant, content: "   ")])
        vm.removeTrailingEmptyAssistantMessage()
        XCTAssertEqual(vm.messagesValue.count, 1, "blank assistant removed")

        vm.setMessages([Message(role: .user, content: "q"),
                        Message(role: .assistant, content: "answer")])
        vm.removeTrailingEmptyAssistantMessage()
        XCTAssertEqual(vm.messagesValue.count, 2, "non-blank assistant kept")

        vm.setMessages([Message(role: .user, content: "q")])
        vm.removeTrailingEmptyAssistantMessage()
        XCTAssertEqual(vm.messagesValue.count, 1, "a user turn is never removed")
    }
}
