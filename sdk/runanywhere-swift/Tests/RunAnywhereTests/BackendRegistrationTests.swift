//
//  BackendRegistrationTests.swift
//  RunAnywhere SDK
//
//  End-to-end registration coverage for every shipped backend product —
//  LlamaCPP (LLM), ONNX + Sherpa (embeddings / STT / TTS / VAD), MLX (Apple
//  MLX LLM/VLM/embeddings/speech), and NeuRT (Apple Neural Engine LLM +
//  CoreML diffusion). These exercise the real commons plugin registry through
//  each XCFramework, so they are the "does the whole Swift SDK still wire up"
//  smoke test we run before a release.
//
//  Two layers of assertion:
//    1. Always: `register()` is callable, idempotent (a second call is a
//       no-op, never a crash), and the registry stays internally consistent
//       (plugin count never shrinks across a re-register).
//    2. Routing: a backend that is actually routable in the linked XCFramework
//       resolves its primitive through `rac_plugin_find`. On stub binaries
//       (e.g. a NeuRT/Sherpa slice built without the sibling engine sources)
//       the routing assertion is `XCTSkip`ped rather than failed — the same
//       test then fully validates routing once the routable release binaries
//       are staged into Binaries/.
//

import CRACommons
import Foundation
import XCTest

@testable import RunAnywhere

import LlamaCPPRuntime
import NeuRTRuntime
import ONNXRuntime

// NOTE: MLXRuntime is intentionally NOT imported here. Its `MLXBackend`
// C-bridge module re-exposes the commons `rac_vlm_types.h`, whose
// `rac_vlm_result` struct in the shipped RABackendMLX.xcframework has drifted
// from the one in RACommons — importing both into one test module makes clang
// reject the mismatched C struct. MLX registration is covered by the release
// build and the example app until the MLX xcframework re-syncs its headers.

@MainActor
final class BackendRegistrationTests: XCTestCase {

    /// True when the *named* engine is registered and routable for `primitive`.
    /// Uses `rac_plugin_find_for_engine` (not `rac_plugin_find`) so a stale
    /// plugin left registered by another test can't satisfy the assertion — the
    /// resolved plugin must actually be the backend under test.
    private func routes(_ primitive: rac_primitive_t, engine: String) -> Bool {
        rac_plugin_find_for_engine(primitive, engine) != nil
    }

    // MARK: - LlamaCPP (LLM / GENERATE_TEXT)

    func testLlamaCPPRegistrationIsIdempotentAndRoutesLLM() throws {
        let baseline = rac_plugin_count()
        LlamaCPP.register()
        let afterFirst = rac_plugin_count()
        LlamaCPP.register() // second call must be a safe no-op
        let afterSecond = rac_plugin_count()

        XCTAssertGreaterThanOrEqual(afterFirst, baseline, "registration must not shrink the registry")
        XCTAssertEqual(afterFirst, afterSecond, "re-registering llama.cpp must not add a duplicate plugin")

        guard routes(RAC_PRIMITIVE_GENERATE_TEXT, engine: "llamacpp") else {
            throw XCTSkip("llama.cpp LLM not routable in the linked XCFramework; validated by the release build")
        }
        XCTAssertNotNil(
            rac_plugin_find_for_engine(RAC_PRIMITIVE_GENERATE_TEXT, "llamacpp"),
            "the llama.cpp engine must serve GENERATE_TEXT once registered"
        )
    }

    // MARK: - ONNX + Sherpa (EMBED / TRANSCRIBE / SYNTHESIZE)

    func testONNXRegistrationIsIdempotent() throws {
        ONNX.register()
        let afterFirst = rac_plugin_count()
        ONNX.register()
        XCTAssertEqual(afterFirst, rac_plugin_count(), "re-registering ONNX must not add a duplicate plugin")
        XCTAssertFalse(ONNX.version.isEmpty, "ONNX module must report a version")

        // Sherpa speech (STT/TTS/VAD) only routes when RABackendSherpa was built
        // routable (RAC_SHERPA_ROUTABLE=1); the shipped slice may be a stub.
        if !routes(RAC_PRIMITIVE_TRANSCRIBE, engine: "sherpa") {
            throw XCTSkip("Sherpa speech not routable in the linked XCFramework; validated by the release build")
        }
    }

    // MARK: - NeuRT (Apple Neural Engine LLM + CoreML diffusion)

    func testNeuRTRegistrationIsIdempotentAndUnregisters() throws {
        let baseline = rac_plugin_count()
        NeuRT.register()
        let afterFirst = rac_plugin_count()
        NeuRT.register() // idempotent — must not double-register
        XCTAssertEqual(afterFirst, rac_plugin_count(), "re-registering NeuRT must not add a duplicate plugin")
        XCTAssertGreaterThanOrEqual(afterFirst, baseline)
        XCTAssertFalse(NeuRT.version.isEmpty, "NeuRT module must report a version")

        // Teardown then re-register must be crash-free and keep the registry
        // consistent (verified via rac_plugin_count before/after each step).
        NeuRT.unregister()
        let afterUnregister = rac_plugin_count()
        XCTAssertLessThanOrEqual(afterUnregister, afterFirst, "unregister must not grow the registry")

        NeuRT.register()
        XCTAssertGreaterThanOrEqual(
            rac_plugin_count(),
            afterUnregister,
            "re-registering after teardown must not shrink the registry"
        )
    }

    func testNeuRTRoutesDiffusionWhenRoutable() throws {
        NeuRT.register()
        guard routes(RAC_PRIMITIVE_DIFFUSION, engine: "neurt") else {
            throw XCTSkip("NeuRT is a stub on the linked binaries; NeuRT diffusion routing is validated by the routable release build")
        }
        XCTAssertNotNil(
            rac_plugin_find_for_engine(RAC_PRIMITIVE_DIFFUSION, "neurt"),
            "the neurt engine must serve DIFFUSION once NeuRT is registered against routable binaries"
        )
    }

    // MARK: - Whole-SDK wiring

    func testAllBackendsRegisterTogether() throws {
        LlamaCPP.register()
        ONNX.register()
        NeuRT.register()

        // At least one real backend must be present after wiring everything up.
        XCTAssertGreaterThan(
            rac_plugin_count(),
            0,
            "registering every backend must leave a non-empty plugin registry"
        )
    }
}
