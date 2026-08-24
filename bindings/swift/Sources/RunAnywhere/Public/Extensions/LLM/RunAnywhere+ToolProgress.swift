//
//  RunAnywhere+ToolProgress.swift
//  RunAnywhere SDK
//
//  Stage-by-stage progress from a tool that does real work.
//
//  ARCHITECTURE:
//  - Commons owns the sink (`rac_tool_progress_sink_register`), which is
//    process-wide and single-slot, exactly like the HTTP transport.
//  - Swift installs that one sink and fans it out per run-loop handle, the
//    same pattern every SDK already applies to the single proto-byte callback
//    a component handle allows.
//

import CRACommons
import Foundation
import os.lock
import SwiftProtobuf

// MARK: - ToolProgress

/// One stage of a tool's work, as the tool reported it.
///
/// Stages are provider-defined rather than an enum: commons does not know that
/// `web_research` has four steps, and a tool added later with three or nine
/// needs no SDK change. Render `label` and key off `stageID`.
public struct ToolProgress: Sendable, Identifiable {
    /// Status of one stage.
    public enum Status: Sendable {
        case started
        case completed
        case failed

        init?(proto: RAToolProgressStatus) {
            switch proto {
            case .started: self = .started
            case .completed: self = .completed
            case .failed: self = .failed
            default: return nil
            }
        }
    }

    /// Tool that emitted this, matching its registered name.
    public let toolName: String

    /// Provider-defined stage key, e.g. `generating_questions`. Stable across
    /// runs, so it is safe to switch on for icons or grouping.
    public let stageID: String

    /// What a person should read, e.g. "Generating questions".
    public let label: String

    public let status: Status

    /// Optional free text: the questions actually generated, the query being
    /// searched, the reason a stage failed.
    public let detail: String?

    /// Monotonic within one tool call, starting at 0. Order by this rather
    /// than by arrival — the sink hops threads.
    public let sequence: UInt64

    /// Distinct per emitted event within one generation.
    public var id: UInt64 { sequence }

    init?(proto: RAToolProgress) {
        guard let status = Status(proto: proto.status) else { return nil }
        self.toolName = proto.toolName
        self.stageID = proto.stageID
        self.label = proto.label
        self.status = status
        self.detail = proto.hasDetail && !proto.detail.isEmpty ? proto.detail : nil
        self.sequence = proto.sequence
    }
}

// MARK: - Native ABI binding

private enum ToolProgressABI {
    typealias SinkCallback = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutableRawPointer?
    ) -> rac_bool_t
    typealias Register = @convention(c) (SinkCallback?, UnsafeMutableRawPointer?) -> rac_result_t
    typealias RegisterTool = @convention(c) () -> rac_result_t

    static let registerName = "rac_tool_progress_sink_register"
    static let webResearchRegisterName = "rac_tool_web_research_register"
    static let webResearchUnregisterName = "rac_tool_web_research_unregister"

    static let register = NativeProtoABI.load(registerName, as: Register.self)
    static let registerWebResearch = NativeProtoABI.load(
        webResearchRegisterName, as: RegisterTool.self
    )
    static let unregisterWebResearch = NativeProtoABI.load(
        webResearchUnregisterName, as: RegisterTool.self
    )
}

/// Commons calls this on the thread running the tool, so it must hand off
/// rather than block. Returning false tells the provider to abandon the run;
/// we only say that when nobody is listening for its handle any more.
private let toolProgressSink: ToolProgressABI.SinkCallback = { bytes, size, _ in
    guard let bytes, size > 0 else { return RAC_TRUE }
    let data = Data(bytes: bytes, count: size)
    guard let proto = try? RAToolProgress(serializedBytes: data),
          let progress = ToolProgress(proto: proto) else {
        return RAC_TRUE
    }
    return ToolProgressHub.shared.deliver(progress, handle: proto.runLoopHandle)
        ? RAC_TRUE
        : RAC_FALSE
}

// MARK: - Fan-out

/// Routes the one process-wide sink to per-call observers.
///
/// The single slot in commons is why this exists: two concurrent
/// `generateWithTools` calls would otherwise overwrite each other's sink. The
/// run-loop handle stamped on every event is what keeps them apart.
final class ToolProgressHub: @unchecked Sendable {
    static let shared = ToolProgressHub()

    private let lock = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var installed = false
        var observers: [UInt64: @Sendable (ToolProgress) -> Void] = [:]
    }

    /// Install the native sink once, on first use, so an app that never uses a
    /// progress-reporting tool pays nothing.
    private func installIfNeeded() {
        let needsInstall = lock.withLock { state -> Bool in
            guard !state.installed else { return false }
            state.installed = true
            return true
        }
        guard needsInstall, let register = ToolProgressABI.register else { return }
        _ = register(toolProgressSink, nil)
    }

    func addObserver(handle: UInt64, _ observer: @escaping @Sendable (ToolProgress) -> Void) {
        installIfNeeded()
        lock.withLock { $0.observers[handle] = observer }
    }

    func removeObserver(handle: UInt64) {
        lock.withLock { _ = $0.observers.removeValue(forKey: handle) }
    }

    /// - Returns: false when nothing is listening for this handle, which tells
    ///   the provider to stop working.
    func deliver(_ progress: ToolProgress, handle: UInt64) -> Bool {
        let observer = lock.withLock { $0.observers[handle] }
        guard let observer else {
            // A handle of 0 means the tool ran outside a run loop, and an
            // unknown handle means its caller has already returned. Neither is
            // a reason to kill a tool that is still doing useful work.
            return true
        }
        observer(progress)
        return true
    }
}

// MARK: - Built-in research tool

public extension RunAnywhere {
    /// Register the commons `web_research` tool.
    ///
    /// It plans several sub-questions, searches each on DuckDuckGo, and answers
    /// from what came back, reporting each stage through the `onProgress`
    /// closure on ``generateWithTools(prompt:options:toolOptions:toolChoice:forcedToolName:validateCalls:parallelToolCalls:history:onProgress:)``.
    ///
    /// The implementation lives in C++, so Kotlin and Web get the same tool
    /// without reimplementing it. Registration is explicit because a tool that
    /// reaches the network should be something an app turns on.
    @discardableResult
    static func registerWebResearchTool() -> Bool {
        guard let register = ToolProgressABI.registerWebResearch else { return false }
        return register() == RAC_SUCCESS
    }

    /// Remove the `web_research` tool again.
    @discardableResult
    static func unregisterWebResearchTool() -> Bool {
        guard let unregister = ToolProgressABI.unregisterWebResearch else { return false }
        return unregister() == RAC_SUCCESS
    }
}
