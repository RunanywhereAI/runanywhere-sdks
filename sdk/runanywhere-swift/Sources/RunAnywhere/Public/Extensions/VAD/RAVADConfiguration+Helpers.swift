//
//  RAVADConfiguration+Helpers.swift
//  RunAnywhere SDK
//
//  Ergonomic helpers for canonical VAD proto types.
//
//  defaults() / validate() factories live in
//  Generated/RAConvenience.swift, emitted by
//  idl/codegen/generate_swift_convenience.py from the rac_default /
//  rac_min / rac_max / rac_min_float / rac_max_float annotations in
//  idl/vad_options.proto.
//

import Foundation

// MARK: - RAVADConfiguration

extension RAVADConfiguration {
    public var frameLengthSeconds: Float { Float(frameLengthMs) / 1000.0 }
}

// MARK: - RAVADResult

extension RAVADResult {
    public var duration: TimeInterval { TimeInterval(durationMs) / 1000.0 }
}

// MARK: - RASpeechActivityEvent

extension RASpeechActivityEvent {
    public var timestamp: Date {
        Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000.0)
    }

    public var duration: TimeInterval { TimeInterval(durationMs) / 1000.0 }
}

// MARK: - RASpeechActivityKind

extension RASpeechActivityKind {
    public var isTransition: Bool {
        self == .speechStarted || self == .speechEnded
    }
}
