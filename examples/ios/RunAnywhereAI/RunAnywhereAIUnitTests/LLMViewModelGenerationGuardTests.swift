//
//  LLMViewModelGenerationGuardTests.swift
//  RunAnywhereAIUnitTests
//
//  State-assertion tests for the generation-identity guards added for Tier-1
//  bugs #1 (switching conversations mid-generation corrupts data) and #5
//  (stopGeneration allows a second overlapping generation), plus the
//  adversarial-review follow-ups (generation identity / supersession and the
//  makeHistory stale-index crash clamp).
//
//  These drive the real ViewModel state API (@testable) and touch no SDK
//  inference / network / hardware, so they run headlessly under `swift test`.
//

import RunAnywhere
import XCTest
@testable import RunAnywhereAI

@MainActor
final class LLMViewModelGenerationGuardTests: XCTestCase {

    private func makeConversation(id: String, messages: [Message] = []) -> Conversation {
        Conversation(
            id: id,
            title: "T",
            createdAt: Date(),
            updatedAt: Date(),
            messages: messages,
            modelName: nil,
            frameworkName: nil,
            analytics: nil,
            performanceSummary: nil
        )
    }

    /// A user turn plus the empty assistant slot that streamed tokens write into.
    private func streamingMessages() -> [Message] {
        [Message(role: .user, content: "hi"),
         Message(role: .assistant, content: "")]
    }

    // MARK: - Bug #1: conversation-identity guard

    /// While the generation still owns the visible conversation, streamed tokens
    /// are written into the assistant slot as normal.
    func testStreamingTokenWrittenWhileGenerationOwnsConversation() {
        let vm = LLMViewModel()
        vm.setCurrentConversation(makeConversation(id: "A"))
        vm.setMessages(streamingMessages())
        vm.setGeneratingConversationId("A")

        XCTAssertTrue(vm.isActiveGenerationTarget)
        vm.updateMessageContent(at: 1, content: "partial answer")
        XCTAssertEqual(vm.messagesValue[1].content, "partial answer")
    }

    /// After the user switches to another conversation, a late streamed token
    /// from the previous generation must NOT mutate the newly-selected
    /// conversation. This is the exact corruption reported in bug #1.
    func testStreamingTokenDroppedAfterSwitchingConversation() {
        let vm = LLMViewModel()
        vm.setCurrentConversation(makeConversation(id: "A"))
        vm.setMessages(streamingMessages())
        vm.setGeneratingConversationId("A")

        // User navigates to conversation B; its messages replace the buffer.
        vm.setCurrentConversation(makeConversation(id: "B"))
        vm.setMessages([Message(role: .user, content: "different question"),
                        Message(role: .assistant, content: "B's real answer")])

        XCTAssertFalse(vm.isActiveGenerationTarget)
        // A trailing token from generation A tries to write into index 1.
        vm.updateMessageContent(at: 1, content: "LEAK FROM A")
        // Conversation B's assistant message is untouched.
        XCTAssertEqual(vm.messagesValue[1].content, "B's real answer")
    }

    /// A cancelled generation clears its target + identity and (unlike a Stop on
    /// the same conversation) restores the send control immediately.
    func testCancelActiveGenerationClearsStateAndRestoresInput() {
        let vm = LLMViewModel()
        vm.setCurrentConversation(makeConversation(id: "A"))
        vm.setMessages(streamingMessages())
        vm.setGeneratingConversationId("A")
        vm.setActiveGenerationID(UUID())
        vm.setIsGenerating(true)

        vm.cancelActiveGeneration()

        XCTAssertNil(vm.generatingConversationId)
        XCTAssertNil(vm.activeGenerationID)
        XCTAssertFalse(vm.isGenerating, "navigating away restores the send control eagerly")
        XCTAssertFalse(vm.isActiveGenerationTarget)
        // A trailing write from the abandoned generation is dropped.
        vm.updateMessageContent(at: 1, content: "LEAK AFTER CANCEL")
        XCTAssertEqual(vm.messagesValue[1].content, "")
    }

    /// `isActiveGenerationTarget` is a strict match: a nil target is never active.
    func testNilTargetIsNeverActive() {
        let vm = LLMViewModel()
        vm.setCurrentConversation(makeConversation(id: "A"))
        vm.setGeneratingConversationId(nil)
        XCTAssertFalse(vm.isActiveGenerationTarget)
    }

    // MARK: - Bug #5 / generation identity: single owner of isGenerating

    /// stopGeneration must NOT flip `isGenerating` synchronously. The in-flight
    /// generation's own `finalizeGeneration` owns the true->false transition, so
    /// `canSend` stays false and a second overlapping generation cannot start
    /// before the first has actually unwound.
    func testStopGenerationLeavesIsGeneratingTrue() {
        let vm = LLMViewModel()
        vm.setIsGenerating(true)

        vm.stopGeneration()

        XCTAssertTrue(
            vm.isGenerating,
            "stopGeneration must leave isGenerating true until the in-flight generation finalizes"
        )
    }

    /// A superseded generation (its id no longer the active one) must not touch
    /// isGenerating or persist — this is what makes the cross-conversation
    /// restart race and the navigate-away input-lock safe.
    func testSupersededFinalizeIsANoOp() async {
        let vm = LLMViewModel()
        vm.setIsGenerating(true)
        vm.setActiveGenerationID(UUID())   // a newer generation now owns the state

        await vm.finalizeGeneration(at: 0, generationID: UUID())  // stale id

        XCTAssertTrue(vm.isGenerating, "a superseded generation must not clear the new owner's isGenerating")
    }

    /// The generation that still owns the id is the sole clearer of isGenerating.
    func testOwnerFinalizeClearsIsGenerating() async {
        let vm = LLMViewModel()
        let gid = UUID()
        vm.setActiveGenerationID(gid)
        vm.setIsGenerating(true)

        await vm.finalizeGeneration(at: 0, generationID: gid)

        XCTAssertFalse(vm.isGenerating)
        XCTAssertNil(vm.activeGenerationID)
    }

    /// Writes are gated by generation identity, not just conversation identity,
    /// so a superseded stream cannot re-acquire the write path once a new
    /// generation re-pins the same conversation.
    func testIsCurrentGenerationIsGenerationIdentityNotConversation() {
        let vm = LLMViewModel()
        let gid = UUID()
        vm.setActiveGenerationID(gid)
        XCTAssertTrue(vm.isCurrentGeneration(gid))
        XCTAssertFalse(vm.isCurrentGeneration(UUID()), "a different (superseded) generation is not current")
        XCTAssertFalse(vm.isCurrentGeneration(nil))
        vm.setActiveGenerationID(nil)
        XCTAssertFalse(vm.isCurrentGeneration(gid), "no active generation → nothing is current")
    }

    // MARK: - makeHistory stale-index crash clamp

    /// A stale `currentUserIndex` (captured before an await, then the buffer
    /// shrank on a conversation switch) must not crash the slice.
    func testMakeHistoryClampsStaleIndexInsteadOfCrashing() {
        let messages = [Message(role: .user, content: "only one")]
        // currentUserIndex far beyond messages.count — pre-clamp this crashed.
        let history = LLMViewModel.makeHistory(from: messages, currentUserIndex: 99)
        XCTAssertEqual(history.count, 1)
    }

    func testMakeHistoryHandlesZeroAndNegativeIndex() {
        let messages = [Message(role: .user, content: "a"), Message(role: .assistant, content: "b")]
        XCTAssertTrue(LLMViewModel.makeHistory(from: messages, currentUserIndex: 0).isEmpty)
        XCTAssertTrue(LLMViewModel.makeHistory(from: messages, currentUserIndex: -3).isEmpty)
    }

    // MARK: - makeHistory turn hygiene (Tier-3 #4)

    /// An assistant error placeholder (isError == true) is excluded from history,
    /// and the resulting consecutive user turns collapse to the latest.
    func testMakeHistorySkipsErrorAssistantBubble() {
        let messages = [
            Message(role: .user, content: "q1"),
            Message(role: .assistant, content: "Generation failed: boom", isError: true),
            Message(role: .user, content: "q2")
        ]
        let history = LLMViewModel.makeHistory(from: messages, currentUserIndex: 3)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.role, .user)
        XCTAssertEqual(history.first?.content, "q2")
    }

    /// Consecutive same-role turns are collapsed (keep the most recent).
    func testMakeHistoryCollapsesConsecutiveSameRole() {
        let messages = [
            Message(role: .user, content: "u1"),
            Message(role: .user, content: "u2"),
            Message(role: .assistant, content: "a1")
        ]
        let history = LLMViewModel.makeHistory(from: messages, currentUserIndex: 3)
        XCTAssertEqual(history.map { $0.role }, [.user, .assistant])
        XCTAssertEqual(history.map { $0.content }, ["u2", "a1"])
    }

    /// A normal alternating history passes through unchanged.
    func testMakeHistoryKeepsAlternatingTurns() {
        let messages = [
            Message(role: .user, content: "u1"),
            Message(role: .assistant, content: "a1"),
            Message(role: .user, content: "u2")
        ]
        let history = LLMViewModel.makeHistory(from: messages, currentUserIndex: 3)
        XCTAssertEqual(history.map { $0.content }, ["u1", "a1", "u2"])
    }
}
