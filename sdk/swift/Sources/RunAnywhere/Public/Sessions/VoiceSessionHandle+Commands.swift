// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Command surface for a running voice-agent session. All calls are async
// so UI code can `await` them naturally.

import Foundation
import CRACommonsCore

public extension VoiceSessionHandle {

    /// Force the pipeline to process whatever audio it currently has
    /// buffered — mirrors the push-to-talk "send now" UI affordance.
    func sendNow() async {
        session.bargeIn()
    }

    /// Inject an out-of-band user utterance. Text injection is reserved
    /// for a follow-up C ABI hook; today this just triggers barge-in.
    func sendNow(text: String) async {
        _ = text
        session.bargeIn()
    }

    /// Re-arm the pipeline for further listening after a `pause`.
    /// Currently a no-op — v2 keeps the mic open across utterances —
    /// but kept async for API parity.
    func resumeListening() async {
        // Reserved for a future explicit "resume" hook.
    }

    /// Stop any in-flight TTS playback via the barge-in path.
    func interruptPlayback() async {
        session.bargeIn()
    }
}
