//
//  BenchmarkShareCardView.swift
//  RunAnywhereAI
//
//  Branded, shareable benchmark result card + the share sheet that rasterizes it
//  (via ImageRenderer) and hands it to Instagram / X / the system share sheet on
//  iOS, or NSSharingServicePicker-backed ShareLink on macOS. Mirrors the Android
//  share card for visual parity.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// RunAnywhere brand palette for the card (kept local so it renders identically
// regardless of the app's active color scheme).
private enum CardStyle {
    static let backgroundTop = Color(hex: 0x1A0E06)
    static let backgroundBottom = Color(hex: 0x0B0B0C)
    static let brandOrange = Color(hex: 0xFF5500)
    static let textPrimary = Color(hex: 0xF5F3F1)
    static let textSecondary = Color(hex: 0x9A938E)
    static let rowBackground = Color.white.opacity(0.08)
}

private let shareCaption = """
Running AI models 100% on-device with @runanywhereai ⚡
No cloud. No API keys. Full privacy.

Download the RunAnywhere app → runanywhere.ai
"""

// MARK: - Card

/// The branded card. Fixed 9:16 (Stories-friendly) so the captured PNG drops
/// cleanly into Instagram / X without awkward cropping.
struct BenchmarkShareCardView: View {
    let data: ShareCardData

    private let cardWidth: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 28)
            hero
            Spacer(minLength: 20)
            rows
            Spacer(minLength: 12)
            footer
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 30)
        .frame(width: cardWidth, height: cardWidth * 16 / 9, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [CardStyle.backgroundTop, CardStyle.backgroundBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image("runanywhere_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                Text("RunAnywhere")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(CardStyle.textPrimary)
            }
            Text(data.modalityLabel)
                .font(.system(size: 12, weight: .semibold))
                .tracking(2)
                .foregroundColor(CardStyle.brandOrange)
        }
    }

    @ViewBuilder private var hero: some View {
        if let hero = data.hero {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .bottom, spacing: 8) {
                    Text(hero.value)
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(CardStyle.brandOrange)
                    Text(hero.label)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(CardStyle.textSecondary)
                        .padding(.bottom, 8)
                }
                if !data.heroCaption.isEmpty {
                    Text(data.heroCaption)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(CardStyle.textPrimary)
                        .lineLimit(1)
                }
                if let secondary = data.heroSecondary {
                    Text("\(secondary.value) \(secondary.label)")
                        .font(.system(size: 12))
                        .foregroundColor(CardStyle.textSecondary)
                }
            }
        }
    }

    @ViewBuilder private var rows: some View {
        // Only additional models (beyond the hero) appear here — never a duplicate.
        if !data.rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("ALSO TESTED")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(CardStyle.textSecondary)
                ForEach(data.rows) { row in
                    ShareRowView(row: row)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(data.deviceLine)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(CardStyle.textPrimary)
                .lineLimit(1)
            HStack {
                Text("runanywhere.ai")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(CardStyle.brandOrange)
                Spacer()
                Text(data.dateLine)
                    .font(.system(size: 12))
                    .foregroundColor(CardStyle.textSecondary)
            }
        }
    }
}

private struct ShareRowView: View {
    let row: ShareCardRow

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.model)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(CardStyle.textPrimary)
                    .lineLimit(1)
                Text(row.framework)
                    .font(.system(size: 11))
                    .foregroundColor(CardStyle.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            ForEach(row.metrics) { metric in
                VStack(alignment: .trailing, spacing: 1) {
                    Text(metric.value)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(CardStyle.textPrimary)
                    Text(metric.label)
                        .font(.system(size: 10))
                        .foregroundColor(CardStyle.textSecondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(CardStyle.rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Share Sheet

/// Presents the card preview and shares it as a PNG. What the user sees is exactly
/// what gets shared (the same card view is both previewed and rasterized).
struct BenchmarkShareSheet: View {
    let run: BenchmarkRun
    @Environment(\.dismiss) private var dismiss

    #if canImport(UIKit)
    @State private var renderedImage: UIImage?
    #elseif canImport(AppKit)
    @State private var renderedImage: NSImage?
    #endif
    @State private var selected: BenchmarkCategory?

    // A run can span several modalities; each gets its own clean card so a single
    // image never has to cram LLM + STT + TTS + VLM together.
    private var modalities: [BenchmarkCategory] { ShareCardData.availableModalities(run) }
    private var currentCategory: BenchmarkCategory? { selected ?? modalities.first }
    private var data: ShareCardData? {
        currentCategory.map { ShareCardData.from(run, category: $0) }
    }

    var body: some View {
        VStack(spacing: 20) {
            if let data {
                // Modality selector — only when the run spans more than one modality.
                if modalities.count > 1 {
                    Picker("Modality", selection: Binding(
                        get: { currentCategory ?? modalities[0] },
                        set: { selected = $0; renderImage() }
                    )) {
                        ForEach(modalities) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                BenchmarkShareCardView(data: data)
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 8)

                targets
            } else {
                Text("No successful benchmarks to share yet. Run a benchmark first.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 40)
            }

            Button("Done") { dismiss() }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
        }
        .padding(24)
        .task { renderImage() }
    }

    @ViewBuilder private var targets: some View {
        #if canImport(UIKit)
        HStack(spacing: 12) {
            shareButton("Instagram", systemImage: "camera.circle") { shareToInstagram() }
            shareButton("X", systemImage: "at.circle") { shareToX() }
            if let image = renderedImage {
                ShareLink(
                    item: Image(uiImage: image),
                    message: Text(data?.shareMessage ?? shareCaption),
                    preview: SharePreview("RunAnywhere Benchmark", image: Image(uiImage: image))
                ) {
                    labelPill("More", systemImage: "square.and.arrow.up")
                }
            }
        }
        #elseif canImport(AppKit)
        if let image = renderedImage {
            ShareLink(
                item: Image(nsImage: image),
                message: Text(data?.shareMessage ?? shareCaption),
                preview: SharePreview("RunAnywhere Benchmark", image: Image(nsImage: image))
            ) {
                labelPill("Share…", systemImage: "square.and.arrow.up")
            }
        }
        #endif
    }

    private func shareButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { labelPill(title, systemImage: systemImage) }
            .buttonStyle(.plain)
    }

    private func labelPill(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
    }

    @MainActor private func renderImage() {
        guard let data else { return }
        let renderer = ImageRenderer(content: BenchmarkShareCardView(data: data))
        renderer.scale = 3
        #if canImport(UIKit)
        renderedImage = renderer.uiImage
        #elseif canImport(AppKit)
        renderedImage = renderer.nsImage
        #endif
    }

    #if canImport(UIKit)
    // Instagram Stories: pass the card as the story background image via the
    // documented pasteboard contract, then open the Stories composer.
    private func shareToInstagram() {
        guard let image = renderedImage, let png = image.pngData(),
              let url = URL(string: "instagram-stories://share?source_application=\(Bundle.main.bundleIdentifier ?? "")"),
              UIApplication.shared.canOpenURL(url) else { return }
        UIPasteboard.general.setItems(
            [["com.instagram.sharedSticker.backgroundImage": png]],
            options: [.expirationDate: Date().addingTimeInterval(300)]
        )
        UIApplication.shared.open(url)
    }

    // X: copy the card so it can be pasted into the composer, then open the X app
    // with the caption prefilled. Image attachment via URL scheme isn't supported
    // by X, so the pasteboard copy is the reliable bridge.
    private func shareToX() {
        guard let image = renderedImage else { return }
        UIPasteboard.general.image = image
        let caption = data?.shareMessage ?? shareCaption
        let encoded = caption.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        for scheme in ["twitter://post?message=\(encoded)", "x://post?message=\(encoded)"] {
            if let url = URL(string: scheme), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }
    }
    #endif
}

#if canImport(AppKit)
private extension NSImage {
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
#endif
