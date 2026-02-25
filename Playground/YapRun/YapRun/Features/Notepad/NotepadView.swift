//
//  NotepadView.swift
//  YapRun
//
//  Simple text editor for testing the YapRun keyboard within the app.
//

#if os(iOS)
import SwiftUI

struct NotepadView: View {
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            AppColors.backgroundPrimaryDark.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                header
                    .padding(.top, 16)
                    .padding(.horizontal, 16)

                Divider()
                    .background(AppColors.cardBorder)
                    .padding(.top, 12)

                // Editor
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .focused($isFocused)
                        .font(.body)
                        .foregroundStyle(AppColors.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(14)

                    if text.isEmpty {
                        Text("Switch to the YapRun keyboard and start dictating…")
                            .font(.body)
                            .foregroundStyle(AppColors.textTertiary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 22)
                            .allowsHitTesting(false)
                    }
                }
                .background(AppColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppColors.cardBorder, lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                // Footer hint
                Text("Tap the globe icon to switch keyboards")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.bottom, 16)
            }
        }
        .onTapGesture {
            isFocused = true
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Notepad")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            // Word count
            Text("\(wordCount) word\(wordCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(AppColors.textTertiary)

            Button {
                UIPasteboard.general.string = text
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(AppColors.overlayLight, in: Circle())
            }
            .disabled(text.isEmpty)
            .opacity(text.isEmpty ? 0.4 : 1)

            Button {
                text = ""
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(AppColors.overlayLight, in: Circle())
            }
            .disabled(text.isEmpty)
            .opacity(text.isEmpty ? 0.4 : 1)
        }
    }

    // MARK: - Helpers

    private var wordCount: Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}

#endif
