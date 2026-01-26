//
//  ToolCallViews.swift
//  RunAnywhereAI
//
//  Minimal UI components for tool calling visualization
//

import SwiftUI
import RunAnywhere

// MARK: - Tool Call Indicator

struct ToolCallIndicator: View {
    let toolCallInfo: ToolCallInfo
    let onTap: () -> Void

    @State private var isPulsing = false

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: toolCallInfo.success ? "wrench.and.screwdriver" : "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(toolCallInfo.success ? AppColors.primaryAccent : AppColors.primaryOrange)
                    .scaleEffect(isPulsing ? 1.1 : 1.0)

                Text(toolCallInfo.toolName)
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(toolCallInfo.success
                        ? AppColors.primaryAccent.opacity(0.1)
                        : AppColors.primaryOrange.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        toolCallInfo.success
                            ? AppColors.primaryAccent.opacity(0.3)
                            : AppColors.primaryOrange.opacity(0.3),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Tool Call Detail Sheet

struct ToolCallDetailSheet: View {
    let toolCallInfo: ToolCallInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Status
                    statusSection

                    // Tool Name
                    detailSection(title: "Tool", content: toolCallInfo.toolName)

                    // Arguments
                    codeSection(title: "Arguments", code: toolCallInfo.arguments)

                    // Result
                    if let result = toolCallInfo.result {
                        codeSection(title: "Result", code: result)
                    }

                    // Error
                    if let error = toolCallInfo.error {
                        detailSection(title: "Error", content: error, isError: true)
                    }

                    Spacer()
                }
                .padding()
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Tool Call")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 350)
        #endif
    }

    private var statusSection: some View {
        HStack(spacing: 10) {
            Image(systemName: toolCallInfo.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(toolCallInfo.success ? AppColors.statusGreen : AppColors.primaryRed)

            Text(toolCallInfo.success ? "Success" : "Failed")
                .font(AppTypography.headline)
                .foregroundColor(AppColors.textPrimary)

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(toolCallInfo.success
                    ? AppColors.statusGreen.opacity(0.1)
                    : AppColors.primaryRed.opacity(0.1))
        )
    }

    private func detailSection(title: String, content: String, isError: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)

            Text(content)
                .font(AppTypography.body)
                .foregroundColor(isError ? AppColors.primaryRed : AppColors.textPrimary)
        }
    }

    private func codeSection(title: String, code: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)

            Text(code)
                .font(AppTypography.monospaced)
                .foregroundColor(AppColors.textPrimary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppColors.backgroundSecondary)
                )
        }
    }
}

// MARK: - Tool Calling Active Indicator

struct ToolCallingActiveIndicator: View {
    @State private var rotation: Double = 0

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "gearshape.2")
                .font(.system(size: 12))
                .foregroundColor(AppColors.primaryAccent)
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }

            Text("Calling tool...")
                .font(AppTypography.caption2)
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColors.primaryAccent.opacity(0.1))
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        ToolCallIndicator(
            toolCallInfo: ToolCallInfo(
                toolName: "get_weather",
                arguments: ["location": "San Francisco"],
                result: ["temp": 72, "condition": "Sunny"],
                success: true
            )
        ) {}

        ToolCallIndicator(
            toolCallInfo: ToolCallInfo(
                toolName: "search_web",
                arguments: ["query": "Swift concurrency"],
                success: false,
                error: "Network timeout"
            )
        ) {}

        ToolCallingActiveIndicator()
    }
    .padding()
}
