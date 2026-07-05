//
//  ComponentVTable.swift
//  RunAnywhere SDK
//
//  Per-modality vtable describing the 5 ops that vary across the
//  LLM / STT / TTS / VAD / VLM component actor scaffolds. The rest of
//  the actor (handle caching, error wrapping, lifecycle gates) is
//  generic and lives in `CppBridge.ComponentActor`.
//
//  VoiceAgent is intentionally NOT modeled here — its handle type
//  is `rac_voice_agent_handle_t` (a struct pointer), and `create` is
//  async + composite (it must gather LLM/STT/TTS/VAD handles first).
//  VoiceAgent keeps its own bespoke actor scaffold.
//
//  This collapses ~885 LOC of duplicated boilerplate.
//

import CRACommons

extension CppBridge {

    /// Function-pointer table parameterizing one modality's component actor.
    ///
    /// Five ops vary per modality; the actor scaffold (lazy create,
    /// `isLoaded`, `loadModel`, `unload`, `destroy`) is shared.
    public struct ComponentVTable: Sendable {

        // MARK: - Identity

        /// The proto-canonical component identity. Used for log/error labels
        /// and for keying lifecycle state across components.
        public let component: RASDKComponent

        // MARK: - Lifecycle ops

        /// Create the C++ component, writing the new opaque handle into `out`.
        public let create: @Sendable (_ out: UnsafeMutablePointer<rac_handle_t?>) -> rac_result_t

        /// Query whether the component has a model/voice currently loaded.
        public let isLoaded: @Sendable (_ handle: rac_handle_t) -> rac_bool_t

        /// Cleanup (unload) the loaded asset, leaving the component reusable.
        public let cleanup: @Sendable (_ handle: rac_handle_t) -> Void

        /// Destroy the underlying C++ component and release its resources.
        public let destroy: @Sendable (_ handle: rac_handle_t) -> Void

        /// Load a model/voice given (path, id, name). `nil` means the modality
        /// has no path-based load (e.g. richer custom signatures live on the
        /// per-modality extension). Stays optional so VLM (extra projector
        /// path) can opt out without adding a third arg shape here.
        public let loadModel: (@Sendable (
            _ handle: rac_handle_t,
            _ path: UnsafePointer<CChar>?,
            _ id: UnsafePointer<CChar>?,
            _ name: UnsafePointer<CChar>?
        ) -> rac_result_t)?
    }
}

// MARK: - Static vtable instances

extension CppBridge.ComponentVTable {

    /// LLM component vtable — `rac_llm_component_*` family.
    public static let llm = CppBridge.ComponentVTable(
        component: .llm,
        create: { rac_llm_component_create($0) },
        isLoaded: { rac_llm_component_is_loaded($0) },
        cleanup: { _ = rac_llm_component_cleanup($0) },
        destroy: { rac_llm_component_destroy($0) },
        loadModel: { handle, path, id, name in
            rac_llm_component_load_model(handle, path, id, name)
        }
    )

    /// STT component vtable — `rac_stt_component_*` family.
    public static let stt = CppBridge.ComponentVTable(
        component: .stt,
        create: { rac_stt_component_create($0) },
        isLoaded: { rac_stt_component_is_loaded($0) },
        cleanup: { _ = rac_stt_component_cleanup($0) },
        destroy: { rac_stt_component_destroy($0) },
        loadModel: { handle, path, id, name in
            rac_stt_component_load_model(handle, path, id, name)
        }
    )

    /// TTS component vtable — `rac_tts_component_*` family.
    /// The "model" generic name aliases TTS's "voice" terminology at the C ABI.
    public static let tts = CppBridge.ComponentVTable(
        component: .tts,
        create: { rac_tts_component_create($0) },
        isLoaded: { rac_tts_component_is_loaded($0) },
        cleanup: { _ = rac_tts_component_cleanup($0) },
        destroy: { rac_tts_component_destroy($0) },
        loadModel: { handle, path, id, name in
            rac_tts_component_load_voice(handle, path, id, name)
        }
    )

    /// VAD component vtable — `rac_vad_component_*` family.
    public static let vad = CppBridge.ComponentVTable(
        component: .vad,
        create: { rac_vad_component_create($0) },
        isLoaded: { rac_vad_component_is_loaded($0) },
        cleanup: { _ = rac_vad_component_cleanup($0) },
        destroy: { rac_vad_component_destroy($0) },
        loadModel: { handle, path, id, name in
            rac_vad_component_load_model(handle, path, id, name)
        }
    )

    /// VLM component vtable — `rac_vlm_component_*` family.
    ///
    /// The level-3 VLM handle is never loaded with a model, so the
    /// `loadModel` slot is dead in practice. The slot is kept here only so
    /// the `ComponentVTable` shape stays uniform with the sibling modalities
    /// (LLM, STT, TTS, VAD). Inference and cancel route through the
    /// lifecycle service via the proto ABI.
    public static let vlm = CppBridge.ComponentVTable(
        component: .vlm,
        create: { rac_vlm_component_create($0) },
        isLoaded: { rac_vlm_component_is_loaded($0) },
        cleanup: { _ = rac_vlm_component_cleanup($0) },
        destroy: { rac_vlm_component_destroy($0) },
        loadModel: { handle, path, id, name in
            // Passing nil for vision_projector_path covers single-artifact
            // VLMs; the multi-artifact VLM path stays on the modality
            // extension where it can pass the projector explicitly.
            rac_vlm_component_load_model(handle, path, nil, id, name)
        }
    )
}
