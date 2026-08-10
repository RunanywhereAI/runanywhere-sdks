//
//  SmartMarkdownRenderer.swift
//  RunAnywhereAI
//
//  The one renderer for model-produced text. Every assistant reply on both
//  platforms — Chat, the voice agent's transcript, and the Documents answer —
//  comes through here.
//
//  ## It used to be four renderers behind a guess
//
//  `AdaptiveMarkdownText` asked `MarkdownDetector` which of `.plain` / `.light` /
//  `.basic` / `.rich` to use and dispatched to a different view for each. Two of
//  the four resolved to the same view, so the real branch was "one `Text`" versus
//  "a stack of blocks" — and that branch was evaluated inside `body`, so during
//  streaming it was re-evaluated on every token. The first ``` to land turned the
//  bubble from a `Text` into a `VStack`, tearing down and re-laying-out the whole
//  reply mid-sentence.
//
//  There is now one shape: parse to blocks (`MarkdownBlockParser`), render the
//  blocks. A fence arriving appends a block instead of changing what kind of view
//  the reply is, so there is nothing left to flip between. `MarkdownBlockParser`
//  is proven stable on a growing prefix: only the block currently being written
//  ever changes, and the block count never decreases.
//
//  ## Division of labour
//
//  - `MarkdownBlockParser` — line structure. No SwiftUI.
//  - this file — one view per block kind, using design-system tokens.
//  - `MarkdownText` — inline runs (emphasis, code, links, strikethrough) inside
//    a single block, via `AttributedString`'s CommonMark parser.
//

import SwiftUI

/// Renders model output: paragraphs, headings, lists, quotes, rules, and fenced
/// code, with inline emphasis inside each.
struct AdaptiveMarkdownText: View {
    let content: String
    let baseFont: Font
    let textColor: Color

    init(_ content: String, font: Font = .body, color: Color = .primary) {
        self.content = content
        self.baseFont = font
        self.textColor = color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            ForEach(Array(MarkdownBlockParser.parse(content).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            MarkdownText(text, font: baseFont, color: textColor)
                .frame(maxWidth: .infinity, alignment: .leading)

        case let .heading(level, text):
            MarkdownText(text, font: Self.headingFont(level), color: textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

        case .list(let items):
            MarkdownListView(items: items, font: baseFont, color: textColor)

        case .quote(let text):
            MarkdownQuoteView(text: text, font: baseFont)

        case let .code(language, source):
            MarkdownCodeBlock(language: language, source: source)

        case .rule:
            Rectangle()
                .fill(AppColors.border)
                .frame(height: Hairline.width)
                .padding(.vertical, Space.xs)
                .accessibilityHidden(true)
        }
    }

    /// A model's heading level, clamped into this app's own type scale.
    ///
    /// Relative sizes survive — an `#` still outranks a `###` — but the absolute
    /// level does not: the reply sits *inside* a screen that already has a
    /// `.largeTitle`, and a model emitting `#` must not out-shout the title of
    /// the screen it is being read on. Three tiers, none above `.sectionTitle`,
    /// which is the same clamp the web renderer applies (`h1` → `h3`).
    private static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1, 2: AppType.font(.sectionTitle)
        case 3, 4: AppType.font(.cardTitle)
        default: AppType.font(.secondary).weight(.semibold)
        }
    }
}

// MARK: - List

/// A run of list rows sharing one gutter.
///
/// The gutter is sized once for the whole list from its widest label, so `9.`
/// and `10.` do not stagger the text beside them — the reason a list is parsed
/// as a group rather than row by row.
private struct MarkdownListView: View {
    let items: [MarkdownListItem]
    let font: Font
    let color: Color

    /// Labels are set in monospaced digits and right-aligned, so the gutter only
    /// has to be wide enough for the longest one. Derived from the type size
    /// rather than a fixed point value so it holds at every Dynamic Type step.
    private var gutter: CGFloat {
        let widest = items.map(\.label.count).max() ?? 1
        return AppType.pointSize(.body) * (0.62 * CGFloat(widest) + 0.35)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Text(item.label)
                        .font(font.monospacedDigit())
                        .foregroundStyle(item.isOrdered ? color : AppColors.brand)
                        .frame(width: gutter, alignment: .trailing)
                        // The marker is decoration; VoiceOver reads the row's
                        // text and announces list position itself.
                        .accessibilityHidden(true)

                    MarkdownText(item.text, font: font, color: color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, CGFloat(item.depth) * Space.lg)
            }
        }
    }
}

// MARK: - Quote

/// A blockquote: a brand rule down the left edge, text stepped back.
///
/// The rule rather than an indent alone, because a quote nested in a reply that
/// already indents its lists is otherwise indistinguishable from a list item
/// whose bullet failed to render.
private struct MarkdownQuoteView: View {
    let text: String
    let font: Font

    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            Capsule()
                .fill(AppColors.brand.opacity(0.5))
                .frame(width: Stroke.emphasis)
                .accessibilityHidden(true)

            MarkdownText(text, font: font, color: AppColors.mutedForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Code

/// A fenced code block: language named, text copyable, never wrapped.
///
/// Horizontal scrolling rather than wrapping is deliberate — wrapped code loses
/// the indentation that carries its structure. The language label and the copy
/// button are cross-platform parity items: the web renderer emits both, and a
/// reader should not have to hand-select code out of a scrolling box on any of
/// the four apps.
private struct MarkdownCodeBlock: View {
    let language: String?
    let source: String

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            sourceText
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(AppColors.border, lineWidth: Hairline.width)
        )
        // On the Mac the copy affordance is expected in the context menu too —
        // a right-click on code is muscle memory there.
        .contextMenu {
            Button("Copy Code", systemImage: "doc.on.doc", action: copy)
        }
    }

    private var header: some View {
        HStack(spacing: Space.sm) {
            if let language {
                Text(language.uppercased())
                    .appType(.overline)
                    .foregroundStyle(AppColors.codeForeground.opacity(0.7))
            }

            Spacer(minLength: 0)

            Button(action: copy) {
                Label(
                    didCopy ? "Copied" : "Copy",
                    systemImage: didCopy ? "checkmark" : "doc.on.doc"
                )
                .appType(.overline)
                .labelStyle(.titleAndIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(didCopy ? AppColors.success : AppColors.codeForeground.opacity(0.7))
                // The glyph swaps in place instead of the label jumping as the
                // two words change width.
                .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(didCopy ? "Code copied" : "Copy code")
            // Arrival of a confirmed result — the one place §6.3 allows a
            // bouncy curve, and the only motion in this block.
            .motionAware(Motion.bouncy, value: didCopy)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .background(AppColors.codeSurface.opacity(0.65))
    }

    private var sourceText: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(source)
                .font(AppType.font(.mono))
                .foregroundStyle(AppColors.codeForeground)
                .textSelection(.enabled)
                .padding(Space.md)
        }
        .background(AppColors.codeSurface)
    }

    private func copy() {
        #if os(iOS)
        UIPasteboard.general.string = source
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(source, forType: .string)
        #endif

        didCopy = true
        Task {
            // Long enough to be read, short enough that the button is back to
            // "Copy" before the reader wants it again.
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }
}

// MARK: - Preview

#Preview("Every block") {
    ScrollView {
        AdaptiveMarkdownText(
            """
            Here is the plan, with a **bold** run and some `inline code`.

            ## Steps

            3. Third step, because the model started at three
            4. Fourth step
            10. Tenth step, testing gutter alignment

            - A bullet
              - Nested one level
            - Back out again

            ```swift
            func sum(_ a: Int, _ b: Int) -> Int {
                a + b
            }
            ```

            > A caveat, set back behind a brand rule.

            ---

            Arithmetic stays literal: 5 * 3 * 2, `rm *.txt`, and get_user_name.
            """,
            font: AppType.font(.body),
            color: AppColors.textPrimary
        )
        .padding(Space.xl)
    }
    .frame(width: 460)
    .background(AppColors.background)
}
