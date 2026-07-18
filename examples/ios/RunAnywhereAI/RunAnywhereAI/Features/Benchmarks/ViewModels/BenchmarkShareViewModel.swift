//
//  BenchmarkShareViewModel.swift
//  RunAnywhereAI
//
//  Main-actor state and platform operations for benchmark share cards.
//

import Foundation
import Observation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum BenchmarkShareTarget: String, Identifiable, Sendable {
    case instagram
    case x

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .instagram: return "Instagram"
        case .x: return "X"
        }
    }
}

enum BenchmarkShareAvailability: Equatable, Sendable {
    case checking
    case available
    case unavailable
}

enum BenchmarkShareRenderState: Equatable, Sendable {
    case idle
    case rendering
    case ready
    case failed(BenchmarkShareError)
}

enum BenchmarkShareError: Error, Equatable, Identifiable, Sendable {
    case renderingFailed
    case imageEncodingFailed
    case invalidTargetURL(BenchmarkShareTarget)
    case targetUnavailable(BenchmarkShareTarget)
    case appOpenFailed(BenchmarkShareTarget)

    var id: String {
        switch self {
        case .renderingFailed: return "rendering-failed"
        case .imageEncodingFailed: return "image-encoding-failed"
        case let .invalidTargetURL(target): return "invalid-url-\(target.id)"
        case let .targetUnavailable(target): return "unavailable-\(target.id)"
        case let .appOpenFailed(target): return "open-failed-\(target.id)"
        }
    }

    var message: String {
        switch self {
        case .renderingFailed:
            return "The benchmark card could not be rendered. Try creating the image again."
        case .imageEncodingFailed:
            return "The benchmark image could not be prepared for Instagram. Use More to share with the system sheet."
        case let .invalidTargetURL(target):
            return "A valid \(target.displayName) share URL could not be created. "
                + "Use More to share with the system sheet."
        case let .targetUnavailable(target):
            return "\(target.displayName) is not available. Use More to share with another app."
        case let .appOpenFailed(target):
            return "\(target.displayName) could not be opened. Use More to share with the system sheet."
        }
    }
}

@MainActor
@Observable
final class BenchmarkShareViewModel {
    private static let rendererScale: CGFloat = 3
    private static let pasteboardLifetime: TimeInterval = 300

    private var run: BenchmarkRun?

    var selectedCategory: BenchmarkCategory?
    private(set) var renderState: BenchmarkShareRenderState = .idle
    private(set) var targetAvailability: [BenchmarkShareTarget: BenchmarkShareAvailability] = [
        .instagram: .checking,
        .x: .checking
    ]
    private(set) var activeTarget: BenchmarkShareTarget?
    private(set) var error: BenchmarkShareError?

    #if canImport(UIKit)
    private(set) var renderedImage: UIImage?
    #elseif canImport(AppKit)
    private(set) var renderedImage: NSImage?
    #endif

    var modalities: [BenchmarkCategory] {
        run.map(ShareCardData.availableModalities) ?? []
    }

    var data: ShareCardData? {
        guard let run, let category = selectedCategory ?? modalities.first else { return nil }
        return ShareCardData.from(run, category: category)
    }

    var caption: String {
        data?.shareMessage ?? Self.fallbackCaption
    }

    func prepare(run: BenchmarkRun) {
        self.run = run
        if let selectedCategory, !modalities.contains(selectedCategory) {
            self.selectedCategory = nil
        }
        if selectedCategory == nil {
            selectedCategory = modalities.first
        }
        refreshTargetAvailability()
        renderCurrentCard()
    }

    func selectCategory(_ category: BenchmarkCategory) {
        guard modalities.contains(category) else { return }
        selectedCategory = category
        renderCurrentCard()
    }

    func availability(for target: BenchmarkShareTarget) -> BenchmarkShareAvailability {
        targetAvailability[target] ?? .unavailable
    }

    func retryRendering() {
        renderCurrentCard()
    }

    func dismissError() {
        error = nil
    }

    #if canImport(UIKit)
    func share(to target: BenchmarkShareTarget) {
        guard activeTarget == nil else { return }
        guard availability(for: target) == .available else {
            error = .targetUnavailable(target)
            return
        }
        guard renderState == .ready, let renderedImage else {
            error = .renderingFailed
            return
        }

        let targetURL: URL?
        switch target {
        case .instagram:
            guard let png = renderedImage.pngData() else {
                error = .imageEncodingFailed
                return
            }
            guard let bundleID = Bundle.main.bundleIdentifier else {
                error = .invalidTargetURL(target)
                return
            }
            UIPasteboard.general.setItems(
                [["com.instagram.sharedSticker.backgroundImage": png]],
                options: [.expirationDate: Date().addingTimeInterval(Self.pasteboardLifetime)]
            )
            targetURL = URL(string: "instagram-stories://share?source_application=\(bundleID)")
        case .x:
            UIPasteboard.general.image = renderedImage
            targetURL = xURL(caption: caption)
        }

        guard let targetURL else {
            error = .invalidTargetURL(target)
            return
        }
        open(targetURL, for: target)
    }

    private func refreshTargetAvailability() {
        targetAvailability[.instagram] = availability(for: ["instagram-stories://share"])
        targetAvailability[.x] = availability(for: ["twitter://post", "x://post"])
    }

    private func availability(for schemes: [String]) -> BenchmarkShareAvailability {
        schemes.contains { scheme in
            URL(string: scheme).map(UIApplication.shared.canOpenURL) ?? false
        } ? .available : .unavailable
    }

    private func xURL(caption: String) -> URL? {
        ["twitter", "x"]
            .compactMap { scheme -> URL? in
                var components = URLComponents()
                components.scheme = scheme
                components.host = "post"
                components.queryItems = [URLQueryItem(name: "message", value: caption)]
                return components.url
            }
            .first(where: UIApplication.shared.canOpenURL)
    }

    private func open(_ url: URL, for target: BenchmarkShareTarget) {
        activeTarget = target
        Task { [weak self] in
            let didOpen = await UIApplication.shared.open(url, options: [:])
            guard let self else { return }
            activeTarget = nil
            if !didOpen {
                targetAvailability[target] = .unavailable
                error = .appOpenFailed(target)
            }
        }
    }
    #else
    private func refreshTargetAvailability() {
        targetAvailability[.instagram] = .unavailable
        targetAvailability[.x] = .unavailable
    }
    #endif

    private func renderCurrentCard() {
        guard let data else {
            renderState = .idle
            renderedImage = nil
            return
        }

        renderState = .rendering
        let renderer = ImageRenderer(content: BenchmarkShareCardView(data: data))
        renderer.scale = Self.rendererScale
        #if canImport(UIKit)
        renderedImage = renderer.uiImage
        #elseif canImport(AppKit)
        renderedImage = renderer.nsImage
        #endif
        renderState = renderedImage == nil ? .failed(.renderingFailed) : .ready
    }

    private static let fallbackCaption = """
    Running AI models 100% on-device with @runanywhereai ⚡
    No cloud. No API keys. Full privacy.

    Download the RunAnywhere app → runanywhere.ai
    """
}
