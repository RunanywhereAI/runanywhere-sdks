//
//  ComputerUseAgentSurfaceTests.swift
//  RunAnywhere SDK
//
//  Public-surface tests for `RunAnywhere.CUA`. These need no model and no SDK
//  init — the scaffold is stateless, so every case runs the real commons path
//  (rac_cua_system_prompt / rac_cua_parse_action_proto) through the Swift facade.
//
//  The facade is deliberately covered separately from the commons unit tests:
//  the bug in `testNoToolCallIsNotConfusedWithUnknownProfile` existed ONLY in
//  the Swift bridging layer while commons was correct, so C++ coverage alone
//  could never have caught it.
//

import XCTest

@testable import RunAnywhere

final class ComputerUseAgentSurfaceTests: XCTestCase {
    private let viewport = (width: 1440, height: 900)

    // MARK: - System prompt

    func testFaraSystemPromptCarriesTheToolSchema() {
        guard let prompt = RunAnywhere.CUA.systemPrompt() else {
            return XCTFail("built-in fara profile must resolve")
        }
        XCTAssertTrue(prompt.contains("<tools>"), "prompt must carry the tool block")
        XCTAssertTrue(prompt.contains("computer_use"), "prompt must name the computer_use tool")
        XCTAssertTrue(prompt.contains("1000x1000"), "prompt must declare the coordinate space")
    }

    func testUnknownProfileReturnsNilPrompt() {
        XCTAssertNil(RunAnywhere.CUA.systemPrompt(profile: "does-not-exist"))
    }

    // MARK: - Parsing

    func testGoldenLeftClickScalesIntoTheViewport() {
        let output = """
        I will click on the search box.
        <tool_call>
        {"name": "computer_use", "arguments": {"action": "left_click", "coordinate": [500, 382]}}
        </tool_call>
        """
        guard let action = RunAnywhere.CUA.parseAction(output, viewport: viewport) else {
            return XCTFail("recognized profile must not return nil")
        }
        XCTAssertTrue(action.isValid)
        XCTAssertEqual(action.kind, .leftClick)
        XCTAssertEqual(action.coordinate?.x, 720, "500 * 1440/1000")
        XCTAssertEqual(action.coordinate?.y, 344, "382 * 900/1000, rounded")
        XCTAssertTrue(action.reasoning.contains("search box"))
    }

    func testUnknownProfileReturnsNilAction() {
        let output = "<tool_call>{\"arguments\": {\"action\": \"left_click\"}}</tool_call>"
        XCTAssertNil(RunAnywhere.CUA.parseAction(output, profile: "does-not-exist", viewport: viewport))
    }

    /// REGRESSION: an all-defaults CuaAction (no tool call found) serializes to
    /// ZERO proto bytes. Guarding on `size > 0` made Swift return nil — the value
    /// reserved for an unknown profile — so callers could not tell "the model
    /// emitted no action" from "that profile does not exist". Every other SDK
    /// decoded this correctly; Swift was the outlier.
    func testNoToolCallIsNotConfusedWithUnknownProfile() {
        guard let action = RunAnywhere.CUA.parseAction("just prose, no tool call", viewport: viewport) else {
            return XCTFail("a known profile with no tool call must NOT return nil")
        }
        XCTAssertFalse(action.isValid, "no tool call means isValid == false")
        XCTAssertNil(action.coordinate)
    }

    // MARK: - Fail-closed extraction (these all fabricated values before)

    func testNullCoordinateDoesNotBorrowAnotherArray() {
        let output = """
        <tool_call>{"arguments": {"action": "left_click", "coordinate": null, "keys": [7, 8]}}</tool_call>
        """
        let action = RunAnywhere.CUA.parseAction(output, viewport: viewport)
        XCTAssertEqual(action?.kind, .leftClick)
        XCTAssertNil(action?.coordinate, "must not read the keys array as a click point")
    }

    func testSingleElementCoordinateIsRejected() {
        let output = "<tool_call>{\"arguments\": {\"action\": \"left_click\", \"coordinate\": [500]}}</tool_call>"
        XCTAssertNil(RunAnywhere.CUA.parseAction(output, viewport: viewport)?.coordinate)
    }

    func testNullStringDoesNotReturnTheNextKeyName() {
        let output = """
        <tool_call>{"arguments": {"action": "visit_url", "url": null, "note": "hello"}}</tool_call>
        """
        let action = RunAnywhere.CUA.parseAction(output, viewport: viewport)
        XCTAssertEqual(action?.kind, .visitURL)
        XCTAssertEqual(action?.text, "", "must be empty, not the next key's name")
    }

    // MARK: - Per-action arguments

    func testKeyActionJoinsTheChord() {
        let output = "<tool_call>{\"arguments\": {\"action\": \"key\", \"keys\": [\"ctrl\", \"l\"]}}</tool_call>"
        let action = RunAnywhere.CUA.parseAction(output, viewport: viewport)
        XCTAssertEqual(action?.kind, .key)
        XCTAssertEqual(action?.text, "ctrl l", "documented contract: KEY -> space-joined keys")
    }

    func testTerminateCarriesTheAnswer() {
        let output = """
        <tool_call>{"arguments": {"action": "terminate", "answer": "done"}}</tool_call>
        """
        let action = RunAnywhere.CUA.parseAction(output, viewport: viewport)
        XCTAssertEqual(action?.kind, .terminate)
        XCTAssertEqual(action?.text, "done")
        XCTAssertNil(action?.coordinate)
    }

    func testTypeActionCarriesTheText() {
        let output = """
        <tool_call>{"arguments": {"action": "type", "text": "hello world"}}</tool_call>
        """
        let action = RunAnywhere.CUA.parseAction(output, viewport: viewport)
        XCTAssertEqual(action?.kind, .type)
        XCTAssertEqual(action?.text, "hello world")
    }

    /// `CuaAction.Kind` is deliberately hand-mirrored so the public surface
    /// stays proto-free (every SDK does the same), which makes this test the
    /// thing that ties it back to the IDL. Pair every generated
    /// `runanywhere.v1.CuaActionType` case to its `Kind`: unequal ordinals
    /// silently re-label every action crossing the bridge, and a proto case
    /// added without a mirror fails the count check rather than decoding to
    /// `.unknown` in the field.
    func testKindOrdinalsMatchTheGeneratedProtoEnum() {
        let mirrored: [(RACuaActionType, CuaAction.Kind)] = [
            (.unspecified, .unknown),
            (.leftClick, .leftClick),
            (.rightClick, .rightClick),
            (.doubleClick, .doubleClick),
            (.tripleClick, .tripleClick),
            (.mouseMove, .mouseMove),
            (.leftClickDrag, .leftClickDrag),
            (.type, .type),
            (.key, .key),
            (.scroll, .scroll),
            (.hscroll, .hscroll),
            (.visitURL, .visitURL),
            (.historyBack, .historyBack),
            (.webSearch, .webSearch),
            (.readPageAnswer, .readPageAnswer),
            (.pauseMemorize, .pauseMemorize),
            (.askUser, .askUser),
            (.wait, .wait),
            (.terminate, .terminate)
        ]

        XCTAssertEqual(
            mirrored.count,
            RACuaActionType.allCases.count,
            "cua.proto gained a CuaActionType case — mirror it in CuaAction.Kind and here"
        )
        for (proto, kind) in mirrored {
            XCTAssertEqual(kind.rawValue, proto.rawValue, "ordinal drift for \(kind)")
            XCTAssertEqual(CuaAction.Kind(rawValue: proto.rawValue), kind)
        }
    }
}
