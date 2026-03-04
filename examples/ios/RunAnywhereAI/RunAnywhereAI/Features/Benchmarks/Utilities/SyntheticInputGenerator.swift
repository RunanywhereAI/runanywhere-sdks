//
//  SyntheticInputGenerator.swift
//  RunAnywhereAI
//
//  Generates deterministic synthetic inputs for benchmarking.
//

import Darwin
import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum SyntheticInputGenerator {

    // MARK: - Audio

    /// Generate silent PCM Int16 mono audio data.
    static func silentAudio(durationSeconds: Double, sampleRate: Int = 16000) -> Data {
        let sampleCount = Int(durationSeconds * Double(sampleRate))
        return Data(count: sampleCount * MemoryLayout<Int16>.size)
    }

    /// Generate a sine wave PCM Int16 mono audio buffer.
    static func sineWaveAudio(durationSeconds: Double, frequencyHz: Double = 440.0, sampleRate: Int = 16000) -> Data {
        let sampleCount = Int(durationSeconds * Double(sampleRate))
        var data = Data(count: sampleCount * MemoryLayout<Int16>.size)
        data.withUnsafeMutableBytes { buffer in
            let samples = buffer.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                let t = Double(i) / Double(sampleRate)
                let value = sin(2.0 * .pi * frequencyHz * t) * Double(Int16.max / 2)
                samples[i] = Int16(value)
            }
        }
        return data
    }

    // MARK: - Images

    #if canImport(UIKit)
    /// Generate a solid-color UIImage.
    static func solidColorImage(width: Int = 224, height: Int = 224, color: UIColor = .red) -> UIImage {
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// Generate a gradient UIImage.
    static func gradientImage(width: Int = 224, height: Int = 224, fromColor: UIColor = .blue, toColor: UIColor = .green) -> UIImage {
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let colors = [fromColor.cgColor, toColor.cgColor] as CFArray
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: nil) else { return }
            ctx.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )
        }
    }
    #endif

    // MARK: - Memory

    /// Returns the current available memory in bytes.
    /// Uses `os_proc_available_memory` on iOS/tvOS/watchOS and `ProcessInfo` on macOS.
    static func availableMemoryBytes() -> Int64 {
        #if os(macOS)
        return Int64(ProcessInfo.processInfo.physicalMemory)
        #else
        return Int64(os_proc_available_memory())
        #endif
    }
}
