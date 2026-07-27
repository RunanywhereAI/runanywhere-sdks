//
//  ComputerUseAgentViewModel.swift
//  RunAnywhereAI
//
//  Drives one computer-use-agent step over `RunAnywhere.CUA` + the VLM APIs.
//  The SDK owns everything model-specific: `CUA.systemPrompt` renders the agent
//  prompt for a profile, and `CUA.parseAction` turns the raw model output into a
//  viewport-scaled `CuaAction`. This view model only supplies a screenshot and a
//  goal, then renders what comes back — the CUA scaffold is deliberately
//  stateless, so owning the loop is the app's job (see rac_cua.h).
//

import Foundation
import RunAnywhere
import SwiftUI
import os.log

#if canImport(UIKit)
import UIKit
typealias AgentImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias AgentImage = NSImage
#endif

@MainActor
@Observable
final class ComputerUseAgentViewModel {
    // MARK: - State

    private(set) var isModelLoaded = false
    private(set) var loadedModelName: String?
    /// The loaded model's declared CUA profile (`ModelInfo.cuaProfile`), or nil
    /// when the model is not a computer-use agent. Everything is driven off this
    /// rather than assuming Fara: other multimodal models in the catalog share
    /// the same `<tool_call>` format but emit absolute-pixel coordinates, so
    /// running them through a CUA profile yields confidently wrong targets.
    private(set) var loadedCuaProfile: String?

    var isCuaCapable: Bool { loadedCuaProfile != nil }
    private(set) var isRunning = false
    /// Raw model output, streamed in as it arrives.
    private(set) var rawOutput = ""
    /// The parsed action for the last step, if the model emitted a valid tool call.
    private(set) var action: CuaAction?
    private(set) var error: String?
    private(set) var statusMessage = ""

    /// Screenshot the agent reasons over.
    var screenshot: AgentImage?
    /// What the user wants the agent to do.
    var task: String = "Click the search box."

    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "CUA")

    private static let maxTokens: Int32 = 256

    // MARK: - Model lifecycle

    func refreshModelStatus() {
        // Needs the populated ModelInfo (not the bare snapshot) to read the
        // catalog-declared cuaProfile.
        guard let model = RunAnywhere.modelInfoForCategory(.multimodal) else {
            isModelLoaded = false
            loadedModelName = nil
            loadedCuaProfile = nil
            return
        }
        isModelLoaded = true
        loadedModelName = model.name.isEmpty ? (model.id.isEmpty ? nil : model.id) : model.name
        loadedCuaProfile = model.cuaProfile.isEmpty ? nil : model.cuaProfile
    }

    func loadModelFromSelection(_ model: RAModelInfo) async {
        statusMessage = "Loading \(model.name)…"
        error = nil

        var loadRequest = RAModelLoadRequest()
        loadRequest.modelID = model.id
        loadRequest.category = .multimodal
        let loadResult = await RunAnywhere.loadModel(loadRequest)
        guard loadResult.success else {
            error = loadResult.errorMessage.isEmpty ? "Model load failed." : loadResult.errorMessage
            statusMessage = ""
            return
        }
        refreshModelStatus()
        statusMessage = isCuaCapable
            ? ""
            : "\(model.name.isEmpty ? model.id : model.name) is not a computer-use model — pick one that declares a CUA profile."
    }

    // MARK: - One agent step

    /// The full CUA round-trip: render the profile's system prompt, run the VLM
    /// over the screenshot, then parse the reply into a viewport-scaled action.
    func runStep() async {
        guard let screenshot, !isRunning else { return }
        // Drive the model's OWN declared profile. Never fall back to Fara: a
        // non-CUA multimodal model would be handed Fara's tool schema and could
        // emit a well-formed tool call in a different coordinate convention,
        // which then rescales into a confidently wrong target.
        guard let profile = loadedCuaProfile else {
            error = "The loaded model does not declare a CUA profile."
            return
        }

        isRunning = true
        error = nil
        rawOutput = ""
        action = nil

        defer { isRunning = false }

        // 1. The agent prompt for this profile — identity + the computer_use tool
        //    schema — comes from commons, not from this app.
        // No `display:` — the SDK already defaults to the profile's own native
        // coordinate space. Naming it here would duplicate a model-specific
        // constant in the app and go stale if a profile ever changes upstream.
        guard let systemPrompt = RunAnywhere.CUA.systemPrompt(profile: profile) else {
            error = "Unknown CUA profile: \(profile)"
            return
        }

        do {
            guard let image = Self.vlmImage(from: screenshot) else {
                error = "Could not convert the screenshot for the model"
                return
            }

            var options = RAVLMGenerationOptions.defaults(prompt: task)
            options.systemPrompt = systemPrompt
            options.maxTokens = Self.maxTokens

            let stream = try await RunAnywhere.processImageStream(image, options: options)
            for await event in stream {
                switch event.kind {
                case .token:
                    if !event.token.isEmpty { rawOutput += event.token }
                case .error:
                    throw NSError(
                        domain: "com.runanywhere.RunAnywhereAI",
                        code: Int(event.errorCode),
                        userInfo: [NSLocalizedDescriptionKey:
                            event.errorMessage.isEmpty ? "VLM stream failed" : event.errorMessage]
                    )
                default:
                    break
                }
            }

            // 2. Parse into an action, rescaled from the profile's 1000x1000
            //    space to the screenshot's real pixel size.
            let viewport = Self.pixelSize(of: screenshot)
            action = RunAnywhere.CUA.parseAction(
                rawOutput,
                profile: profile,
                viewport: viewport
            )
            if action?.isValid == false {
                statusMessage = "No tool call in the model's reply"
            } else {
                statusMessage = ""
            }
        } catch {
            self.error = error.localizedDescription
            logger.error("CUA step failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func cancel() {
        Task { await RunAnywhere.cancelVLMGeneration() }
    }

    func clearResult() {
        rawOutput = ""
        action = nil
        error = nil
        statusMessage = ""
    }

    // MARK: - Platform image helpers

    private static func vlmImage(from image: AgentImage) -> RAVLMImage? {
        #if canImport(UIKit)
        return RAVLMImage.fromUIImage(image)
        #else
        return RAVLMImage.fromNSImage(image)
        #endif
    }

    /// Pixel dimensions of the screenshot — the viewport the SDK scales into.
    static func pixelSize(of image: AgentImage) -> (width: Int, height: Int) {
        #if canImport(UIKit)
        return (Int(image.size.width * image.scale), Int(image.size.height * image.scale))
        #else
        let rep = image.representations.first
        return (rep?.pixelsWide ?? Int(image.size.width), rep?.pixelsHigh ?? Int(image.size.height))
        #endif
    }
}
