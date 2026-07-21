//
//  CppBridge+Vocoder.swift
//  RunAnywhere SDK
//
//  Neural-vocoder bridge over the canonical lifecycle proto ABI.
//

import CRACommons
import Foundation

private enum VocoderLifecycleProtoABI {
    static let vocodeName = "rac_vocoder_vocode_lifecycle_proto"
    static let vocode: NativeProtoABI.ProtoRequest? = {
        // RACommons is a static archive on Apple platforms. Keep a typed
        // reference so the linker retains the vocoder archive member even
        // when RTLD_DEFAULT cannot enumerate executable symbols.
        let linked: NativeProtoABI.ProtoRequest = rac_vocoder_vocode_lifecycle_proto
        return NativeProtoABI.load(
            vocodeName,
            as: NativeProtoABI.ProtoRequest.self
        ) ?? linked
    }()
}

extension CppBridge {
    /// Stateless neural-vocoder namespace.
    ///
    /// Commons owns the loaded model through the canonical model lifecycle;
    /// Swift does not create or retain a second component handle. This keeps
    /// unload and active-inference draining identical across SDK consumers.
    public enum Vocoder {
        /// Convert one packed float32 mel tensor into waveform samples with
        /// the lifecycle-loaded vocoder model.
        public static func vocode(
            _ request: RAVocoderRequest
        ) async throws -> RAVocoderResult {
            try await Task.detached(priority: .userInitiated) {
                try NativeProtoABI.invoke(
                    request,
                    symbol: VocoderLifecycleProtoABI.vocode,
                    symbolName: VocoderLifecycleProtoABI.vocodeName,
                    responseType: RAVocoderResult.self
                )
            }.value
        }
    }
}
