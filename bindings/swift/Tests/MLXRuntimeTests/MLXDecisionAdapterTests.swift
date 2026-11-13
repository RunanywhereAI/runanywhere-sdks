// The MLX decision adapter: how a C request's controls become runtime options,
// which checkpoint runtime is picked, how refusals map to result codes, and
// (with local weights) that both pplx deciders answer through the adapter.
//
// Real-model cases run when these name local checkpoint directories:
//   MLX_DECIDER_FLASH_V12_PATH  perplexity-ai/pplx-decider-flash-v1.2
//   MLX_DECIDER_V11_PATH        mlx-community/pplx-decider-v1.1-27b-4bit
//
// `swift test` cannot compile MLX's Metal shaders, so those cases also need an
// `mlx.metallib` from any macOS MLX build (wally's build tree has one) copied
// beside the test binary, e.g. into
// `.build/debug/runanywhere-sdksPackageTests.xctest/Contents/MacOS/`.

import CoreImage
import Foundation
import MLXBackend
import MLXLLM
import MLXLMCommon
import MLXVLM
import XCTest

@testable import MLXRuntime

final class MLXDecisionAdapterTests: XCTestCase {
    // MARK: Controls

    func testDefaultOptionsAskForNothing() throws {
        let controls = MLXDecisionControls(RAC_DECISION_OPTIONS_DEFAULT)
        XCTAssertNil(controls.temperature)
        XCTAssertNoThrow(try controls.requireBasic())
        XCTAssertEqual(controls.jointOptions.grouping, .perQuestion, "the checkpoint default stands")
        XCTAssertNil(controls.jointOptions.maxLength)
    }

    func testEveryControlIsCopiedOutOfTheCStruct() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x01])
        let controls = png.withUnsafeBytes { bytes -> MLXDecisionControls in
            "image/png".withCString { mime in
                var image = rac_decision_image_t(
                    data: bytes.bindMemory(to: UInt8.self).baseAddress,
                    size: bytes.count,
                    mime_type: mime
                )
                return withUnsafePointer(to: &image) { pointer in
                    var options = RAC_DECISION_OPTIONS_DEFAULT
                    options.temperature = 1.25
                    options.grouping = RAC_DECISION_GROUPING_JOINT
                    options.max_length = 4096
                    options.max_pixels = 1_638_400
                    options.min_pixels = 65_536
                    options.images = pointer
                    options.image_count = 1
                    return MLXDecisionControls(options)
                }
            }
        }
        // The C buffers are gone by now; the copy must stand on its own.
        XCTAssertEqual(controls.images.first?.data, png)
        XCTAssertEqual(controls.images.first?.mimeType, "image/png")
        let options = controls.jointOptions
        XCTAssertEqual(options.temperature, 1.25)
        XCTAssertEqual(options.grouping, .joint)
        XCTAssertEqual(options.maxLength, 4096)
        XCTAssertEqual(options.maxPixels, 1_638_400)
        XCTAssertEqual(options.minPixels, 65_536)
    }

    func testFixedLayoutModelsRefuseEachExtendedControlByName() {
        let cases: [(String, (inout rac_decision_options_t) -> Void)] = [
            ("grouping", { $0.grouping = RAC_DECISION_GROUPING_PER_QUESTION }),
            ("max_length", { $0.max_length = 1 }),
            ("max_pixels", { $0.max_pixels = 1 }),
            ("min_pixels", { $0.min_pixels = 1 })
        ]
        for (name, set) in cases {
            var options = RAC_DECISION_OPTIONS_DEFAULT
            set(&options)
            XCTAssertThrowsError(try MLXDecisionControls(options).requireBasic(), name) { error in
                XCTAssertTrue(
                    (error as? MLXDecisionUnsupported)?.message.contains(name) == true,
                    "\(name): \(error)")
            }
        }
        var temperatureOnly = RAC_DECISION_OPTIONS_DEFAULT
        temperatureOnly.temperature = 2
        XCTAssertNoThrow(try MLXDecisionControls(temperatureOnly).requireBasic())
    }

    func testUndecodableImageIsAnInvalidParameter() {
        let image = MLXDecisionControls.Image(data: Data([1, 2, 3]), mimeType: "image/png")
        XCTAssertThrowsError(try image.decoded()) { error in
            XCTAssertEqual(decisionResultCode(for: error), RAC_ERROR_INVALID_PARAMETER)
        }
    }

    // MARK: Result codes

    func testRefusalsAreNotInferenceFailures() {
        XCTAssertEqual(decisionResultCode(for: MLXDecisionUnsupported("x")), RAC_ERROR_NOT_SUPPORTED)
        XCTAssertEqual(
            decisionResultCode(for: DecisionError.unsupportedCheckpoint("x")), RAC_ERROR_NOT_SUPPORTED)
        XCTAssertEqual(
            decisionResultCode(for: DecisionError.invalidRequest("x")), RAC_ERROR_INVALID_PARAMETER)
        XCTAssertEqual(decisionResultCode(for: DecisionError.tooLong("x")), RAC_ERROR_INVALID_PARAMETER)
        XCTAssertEqual(
            decisionResultCode(for: MLXTextDecisionError("x")), RAC_ERROR_INFERENCE_FAILED)
    }

    // MARK: Routing

    func testJointCheckpointRoutesAheadOfTheV11Decider() throws {
        let directory = try temporaryDirectory()
        try Data("{}".utf8).write(to: directory.appending(component: "decision_config.json"))
        XCTAssertEqual(MLXTextDecisionCheckpoint.kind(at: directory), .decider)
        try Data(
            #"{"version":3,"template":"joint-question-inline-readout-v1","marker":"<|fim_suffix|>","readout_offset":0}"#
                .utf8)
            .write(to: directory.appending(component: "joint_config.json"))
        XCTAssertEqual(MLXTextDecisionCheckpoint.kind(at: directory), .jointDecider)
    }

    // MARK: Real checkpoints

    /// Commons always hands a yes/no question its normalized true/false pair.
    private static let yesNo = [ClefDecisionOption(key: "true"), ClefDecisionOption(key: "false")]

    private static let ticket = ClefDecisionRequest(
        state: "Customer ticket: since we rotated our API key yesterday every call returns 401. "
            + "Production checkout is down.",
        questions: [
            ClefDecisionQuestion(
                id: "down", kind: .noul, instructions: "Is production down?", options: yesNo),
            ClefDecisionQuestion(
                id: "team",
                kind: .choice,
                instructions: "Which team?",
                options: ["support", "billing", "sales"].map { ClefDecisionOption(key: $0) }
            )
        ])

    func testFlashV12AnswersThroughTheAdapter() async throws {
        let model = try await Qwen35JointDecider.load(
            from: try checkpoint("MLX_DECIDER_FLASH_V12_PATH"), using: TransformersTokenizerLoader())
        let pass = try MLXTextDecisions.scoreJoint(
            model, request: Self.ticket, controls: MLXDecisionControls(RAC_DECISION_OPTIONS_DEFAULT))
        XCTAssertEqual(pass.answers.count, 2)
        // Keyed back onto the request's own option keys, true side first for yes/no.
        XCTAssertGreaterThan(pass.answers[0].probabilities["true"] ?? 0, 0.9)
        let team = pass.answers[1].probabilities
        XCTAssertEqual(Set(team.keys), ["support", "billing", "sales"])
        XCTAssertEqual(team.max { $0.value < $1.value }?.key, "support")
        XCTAssertEqual(team.values.reduce(0, +), 1, accuracy: 1e-4)
        XCTAssertGreaterThan(pass.inputTokens, 0)
    }

    func testFlashV12HonoursGroupingAndImages() async throws {
        let model = try await Qwen35JointDecider.load(
            from: try checkpoint("MLX_DECIDER_FLASH_V12_PATH"), using: TransformersTokenizerLoader())
        var joint = RAC_DECISION_OPTIONS_DEFAULT
        joint.grouping = RAC_DECISION_GROUPING_JOINT
        let jointPass = try MLXTextDecisions.scoreJoint(
            model, request: Self.ticket, controls: MLXDecisionControls(joint))
        let perPass = try MLXTextDecisions.scoreJoint(
            model, request: Self.ticket, controls: MLXDecisionControls(RAC_DECISION_OPTIONS_DEFAULT))
        XCTAssertLessThan(
            jointPass.inputTokens, perPass.inputTokens, "one shared sequence encodes the state once")

        var controls = MLXDecisionControls(RAC_DECISION_OPTIONS_DEFAULT)
        controls.images = [MLXDecisionControls.Image(data: try testCardPNG(), mimeType: "image/png")]
        controls.maxPixels = 200_000
        let picture = ClefDecisionRequest(
            state: "Describe the attached picture.",
            questions: [
                ClefDecisionQuestion(
                    id: "dark",
                    kind: .noul,
                    instructions: "Is there a dark rectangle in it?",
                    options: Self.yesNo
                )
            ])
        let pass = try MLXTextDecisions.scoreJoint(model, request: picture, controls: controls)
        XCTAssertGreaterThan(pass.answers[0].probabilities["true"] ?? 0, 0.9)
    }

    func testV11DeciderAnswersAndRefusesImages() async throws {
        let directory = try checkpoint("MLX_DECIDER_V11_PATH")
        XCTAssertEqual(MLXTextDecisionCheckpoint.kind(at: directory), .decider)
        let model = try await Qwen35DeciderModel.load(
            from: directory, using: TransformersTokenizerLoader())
        let pass = MLXDecisionPass(try model.decide(Self.ticket))
        let team = pass.answers[1].probabilities
        XCTAssertEqual(team.max { $0.value < $1.value }?.key, "support")

        var controls = MLXDecisionControls(RAC_DECISION_OPTIONS_DEFAULT)
        controls.images = [MLXDecisionControls.Image(data: Data([1]), mimeType: nil)]
        XCTAssertThrowsError(try controls.requireBasic())
    }

    // MARK: Helpers

    private func checkpoint(_ variable: String) throws -> URL {
        guard let path = ProcessInfo.processInfo.environment[variable], !path.isEmpty else {
            throw XCTSkip("set \(variable) to a local checkpoint directory")
        }
        return URL(fileURLWithPath: path)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(component: "mlx-decision-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    /// 320x240: a colour gradient with a dark block in the middle.
    private func testCardPNG() throws -> Data {
        let width = 320, height = 240
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let index = (y * width + x) * 4
                let dark = (60 ..< 120).contains(y) && (100 ..< 220).contains(x)
                pixels[index] = dark ? 20 : UInt8(x * 255 / (width - 1))
                pixels[index + 1] = dark ? 20 : UInt8(y * 255 / (height - 1))
                pixels[index + 2] = dark ? 20 : UInt8((x + y) * 255 / (width + height - 2))
            }
        }
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw XCTSkip("no sRGB colour space")
        }
        let image = CIImage(
            bitmapData: Data(pixels),
            bytesPerRow: width * 4,
            size: CGSize(width: width, height: height),
            format: .RGBA8,
            colorSpace: sRGB
        )
        guard let png = CIContext().pngRepresentation(of: image, format: .RGBA8, colorSpace: sRGB) else {
            throw XCTSkip("CoreImage could not encode the test card")
        }
        return png
    }
}
