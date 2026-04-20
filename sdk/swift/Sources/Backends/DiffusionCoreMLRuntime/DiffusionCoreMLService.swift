// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// CoreML Stable Diffusion bridge. Wires the apple/ml-stable-diffusion
// Swift package into the `engines/diffusion-coreml` plugin via
// `ra_diffusion_coreml_set_callbacks`.
//
// Sample apps opt in by linking the `StableDiffusion` SPM package; when
// present, `canImport(StableDiffusion)` gates the real implementation.

import Foundation
import CRACommonsCore

#if canImport(StableDiffusion) && canImport(CoreML)
import StableDiffusion
import CoreML
#endif

final class DiffusionSessionBox {
    #if canImport(StableDiffusion) && canImport(CoreML)
    let pipeline: StableDiffusionPipelineProtocol
    let computeUnits: MLComputeUnits
    init(pipeline: StableDiffusionPipelineProtocol, computeUnits: MLComputeUnits) {
        self.pipeline = pipeline
        self.computeUnits = computeUnits
    }
    #else
    init() {}
    #endif
}

public enum DiffusionCoreMLService {

    private nonisolated(unsafe) static var handles: [OpaquePointer: DiffusionSessionBox] = [:]
    private static let handlesLock = NSLock()

    /// Install the callback table with the C plugin. Idempotent.
    public static func installCallbacks() {
        var cbs = ra_diffusion_coreml_callbacks_t()
        cbs.create    = { folder, units, _ in
            DiffusionCoreMLService.create(folder: folder, units: units)
        }
        cbs.destroy   = { handle, _ in
            DiffusionCoreMLService.destroy(handle: handle)
        }
        cbs.generate  = { handle, prompt, neg, seed, steps, guidance,
                            width, height, onStep, onStepUD,
                            outBytes, outSize, _ in
            DiffusionCoreMLService.generate(
                handle: handle, prompt: prompt, neg: neg, seed: seed,
                steps: steps, guidance: guidance,
                width: width, height: height,
                onStep: onStep, onStepUD: onStepUD,
                outBytes: outBytes, outSize: outSize)
        }
        cbs.cancel    = { _, _ in ra_status_t(RA_OK) }  // ml-stable-diffusion is synchronous
        cbs.bytes_free = { ptr, _ in if let p = ptr { free(p) } }
        cbs.user_data = nil
        _ = withUnsafePointer(to: cbs) { ra_diffusion_coreml_set_callbacks($0) }
    }

    // MARK: - Bridge implementation

    private static func create(
        folder: UnsafePointer<CChar>?, units: Int32
    ) -> OpaquePointer? {
        #if canImport(StableDiffusion) && canImport(CoreML)
        guard let folder = folder else { return nil }
        let path = String(cString: folder)
        guard !path.isEmpty else { return nil }
        let mlUnits: MLComputeUnits = {
            switch units {
            case 0: return .cpuAndGPU
            case 1: return .cpuAndNeuralEngine
            default: return .all
            }
        }()
        let url = URL(fileURLWithPath: path)
        do {
            let config = MLModelConfiguration()
            config.computeUnits = mlUnits
            let pipeline = try StableDiffusionPipeline(
                resourcesAt: url, configuration: config,
                disableSafety: true, reduceMemory: true)
            try pipeline.loadResources()
            let box = DiffusionSessionBox(pipeline: pipeline, computeUnits: mlUnits)
            let raw = OpaquePointer(Unmanaged.passRetained(box).toOpaque())
            storeHandle(raw, box)
            return raw
        } catch {
            return nil
        }
        #else
        _ = folder; _ = units
        return nil
        #endif
    }

    private static func destroy(handle: OpaquePointer?) {
        guard let handle = handle else { return }
        if let box = takeHandle(handle) {
            Unmanaged.passUnretained(box).release()
        }
    }

    private static func generate(
        handle: OpaquePointer?,
        prompt: UnsafePointer<CChar>?,
        neg: UnsafePointer<CChar>?,
        seed: Int64, steps: Int32, guidance: Float,
        width: Int32, height: Int32,
        onStep: ((Int32, Int32, UnsafeMutableRawPointer?) -> Void)?,
        onStepUD: UnsafeMutableRawPointer?,
        outBytes: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
        outSize: UnsafeMutablePointer<Int32>?
    ) -> ra_status_t {
        guard let handle = handle, let prompt = prompt,
              let outBytes = outBytes, let outSize = outSize else {
            return ra_status_t(RA_ERR_INVALID_ARGUMENT)
        }
        #if canImport(StableDiffusion) && canImport(CoreML)
        guard let box = lookupHandle(handle) else {
            return ra_status_t(RA_ERR_INVALID_ARGUMENT)
        }
        let promptStr = String(cString: prompt)
        let negStr    = neg.flatMap { String(cString: $0) } ?? ""
        let finalSeed: UInt32 = seed < 0
            ? UInt32.random(in: 0...UInt32.max)
            : UInt32(truncatingIfNeeded: seed)

        var config = StableDiffusionPipeline.Configuration(prompt: promptStr)
        config.negativePrompt       = negStr
        config.stepCount            = Int(steps)
        config.seed                 = finalSeed
        config.guidanceScale        = guidance
        _ = width; _ = height  // ml-stable-diffusion uses the model's native size

        do {
            let images = try box.pipeline.generateImages(
                configuration: config,
                progressHandler: { progress in
                    if let cb = onStep {
                        cb(Int32(progress.step), Int32(progress.stepCount), onStepUD)
                    }
                    return true
                })

            guard let first = images.first ?? nil else {
                return ra_status_t(RA_ERR_INTERNAL)
            }

            // Encode CGImage → PNG bytes.
            let mutable = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(
                mutable as CFMutableData,
                "public.png" as CFString, 1, nil) else {
                return ra_status_t(RA_ERR_INTERNAL)
            }
            CGImageDestinationAddImage(dest, first, nil)
            guard CGImageDestinationFinalize(dest) else {
                return ra_status_t(RA_ERR_INTERNAL)
            }

            let len = mutable.length
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: len)
            mutable.getBytes(buf, length: len)
            outBytes.pointee = buf
            outSize.pointee  = Int32(len)
            return ra_status_t(RA_OK)
        } catch {
            return ra_status_t(RA_ERR_INTERNAL)
        }
        #else
        _ = prompt; _ = neg; _ = seed; _ = steps; _ = guidance
        _ = width; _ = height; _ = onStep; _ = onStepUD
        return ra_status_t(RA_ERR_CAPABILITY_UNSUPPORTED)
        #endif
    }

    // MARK: - Registry helpers

    private static func storeHandle(_ raw: OpaquePointer, _ box: DiffusionSessionBox) {
        handlesLock.lock(); defer { handlesLock.unlock() }
        handles[raw] = box
    }

    private static func lookupHandle(_ raw: OpaquePointer) -> DiffusionSessionBox? {
        handlesLock.lock(); defer { handlesLock.unlock() }
        return handles[raw]
    }

    private static func takeHandle(_ raw: OpaquePointer) -> DiffusionSessionBox? {
        handlesLock.lock(); defer { handlesLock.unlock() }
        return handles.removeValue(forKey: raw)
    }
}

#if canImport(CoreGraphics) && canImport(ImageIO) && canImport(UniformTypeIdentifiers)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#endif
