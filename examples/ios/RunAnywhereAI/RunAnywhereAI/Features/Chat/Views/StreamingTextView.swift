//
//  StreamingTextView.swift
//  RunAnywhereAI
//
//  How a reply arrives. This is the most-watched animation in the app — a reader
//  spends more seconds looking at this than at any other moving thing here — so
//  it gets a real treatment rather than "text appears".
//
//  ## The caret is a character, not a view
//
//  The previous build put a pulsing dot in a `VStack` *below* the whole reply.
//  That reads as a separate status light, not as a cursor: it sits on its own
//  line, left-aligned, however far the last word happened to end. A cursor has
//  to be at the end of the text.
//
//  SwiftUI has exactly one way to flow something inline after wrapped text:
//  make it part of the `Text`. So the caret is a `▌` glyph appended to the last
//  line with its own brand color, which means it lands hard against the final
//  token and travels with every one that follows — for free, with no geometry
//  measurement and nothing to get wrong at a different Dynamic Type size.
//
//  ## Only the last line re-renders
//
//  Splitting the reply at the final newline is what makes the caret affordable.
//  The settled paragraphs above go through the markdown renderer once and hold
//  still; the final line is a plain `Text` that can be rebuilt on a timer to
//  breathe the caret without re-laying-out a 900-word reply five times a second.
//  Rendering the in-progress line as plain text is also more correct than it
//  looks: markdown structure (fences, headings, list markers) is declared at the
//  *start* of a line, so a line that is still being written has no complete
//  syntax to honour yet — and a half-arrived ``` fence rendered eagerly makes the
//  reply flicker between a code block and prose as tokens land.
//
//  ## Motion
//
//  The caret breathes on the canonical 1.6s ambient period (§6.4), sampled at
//  ~8fps because opacity is a slow-moving quantity and a caret does not need
//  120Hz. `TimelineView(.periodic)` rather than `.animation`: an implicit
//  animation on a value that changes every token restarts its own curve on every
//  token, which is what made the old dot stutter during a fast reply.
//
//  Under Reduce Motion the caret is solid and still — visible, because the
//  reader still needs to know the reply is unfinished, but not moving.
//

import SwiftUI

struct StreamingTextView: View {
    /// The reply so far.
    let content: String
    /// True while tokens are still arriving. When false this is just markdown.
    let isStreaming: Bool
    var font: Font = AppType.font(.body)
    var color: Color = AppColors.textPrimary

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    /// U+258C LEFT HALF BLOCK. A block caret rather than `|` because at body
    /// size a pipe is one hairline and disappears against prose, and rather than
    /// `█` because a full block covers more than a cursor should.
    private static let caret = "\u{258C}"

    /// The caret never fully disappears. A caret that blinks to zero is missing
    /// half the time, and on a reply that pauses mid-thought that reads as "it
    /// stopped" rather than "it is thinking".
    private static let caretOpacityFloor: Double = 0.35

    var body: some View {
        if isStreaming {
            streamingBody
        } else {
            // Settled: one markdown pass over the whole reply, no caret, nothing
            // sampling a clock.
            AdaptiveMarkdownText(content, font: font, color: color)
        }
    }

    // MARK: - Streaming

    private var streamingBody: some View {
        let split = Self.split(content)

        return VStack(alignment: .leading, spacing: 0) {
            if !split.settled.isEmpty {
                AdaptiveMarkdownText(split.settled, font: font, color: color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            finalLine(split.tail)
        }
        // The whole reply is one accessibility element and reads as the text
        // alone: the caret is a rendering detail and "left half block" is not
        // something anyone needs to hear at the end of every sentence.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.isEmpty ? "Generating a reply" : content)
    }

    /// The in-progress line plus the caret, as one `Text`.
    @ViewBuilder
    private func finalLine(_ tail: String) -> some View {
        if reduceMotion {
            styledLine(tail, caretOpacity: 1)
        } else {
            // `.periodic` and not `.animation`: `.animation` asks for a redraw
            // every frame, which for a text layout is a great deal of work to
            // move one glyph's alpha. 8fps is invisible on a 1.6s cycle.
            TimelineView(.periodic(from: .now, by: 1.0 / 8.0)) { context in
                styledLine(tail, caretOpacity: Self.caretOpacity(at: context.date))
            }
        }
    }

    private func styledLine(_ tail: String, caretOpacity: Double) -> some View {
        (Text(tail) + caretText(opacity: caretOpacity))
            .font(font)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private func caretText(opacity: Double) -> Text {
        Text(Self.caret)
            .font(font)
            .foregroundStyle(AppColors.brand.opacity(opacity))
    }

    // MARK: - Timing

    /// A sine over the 1.6s ambient period, mapped onto `[floor, 1]`. Sine and
    /// not a triangle wave because a breathe should ease at the turnaround and a
    /// linear ramp visibly kinks there — the "linear" rule in §6.4 is about the
    /// *loop* not stuttering at the seam, which a sine satisfies exactly.
    private static func caretOpacity(at date: Date) -> Double {
        let period = 1.6
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        let wave = (sin(phase * 2 * .pi) + 1) / 2
        return caretOpacityFloor + (1 - caretOpacityFloor) * wave
    }

    // MARK: - Splitting

    /// Everything through the last newline, and the unfinished line after it.
    ///
    /// Splits on the last newline rather than on the last N characters: a
    /// character window cuts mid-word and mid-markdown, and the point of the
    /// split is to isolate the line whose syntax is not decided yet.
    static func split(_ content: String) -> (settled: String, tail: String) {
        guard let lastNewline = content.lastIndex(of: "\n") else {
            return ("", content)
        }
        let settled = String(content[content.startIndex..<lastNewline])
        let tail = String(content[content.index(after: lastNewline)...])
        return (settled, tail)
    }
}

#Preview("Streaming mid-paragraph") {
    StreamingTextView(
        content: "Here is the first settled paragraph of the reply.\n\n"
            + "And this second one is still being written as tokens",
        isStreaming: true
    )
    .padding(Space.xl)
    .frame(width: 420)
    .background(AppColors.background)
}

#Preview("Settled") {
    StreamingTextView(
        content: "Here is the **finished** reply, rendered through the markdown path with no caret.",
        isStreaming: false
    )
    .padding(Space.xl)
    .frame(width: 420)
    .background(AppColors.background)
}
