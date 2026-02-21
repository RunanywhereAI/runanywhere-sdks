//
//  ContentView.swift
//  YapRun
//
//  Redesigned home screen with branding, status cards, model management,
//  and dictation history.
//

#if os(iOS)
import SwiftUI
import RunAnywhere
import os

struct ContentView: View {
    @EnvironmentObject private var flowSession: FlowSessionManager
    @State private var viewModel = HomeViewModel()

    private static let sdkURL = URL(string: "https://github.com/RunanywhereAI/runanywhere-sdks")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    statusSection
                    sessionIndicator
                    modelSection
                    if !viewModel.dictationHistory.isEmpty {
                        historySection
                    }
                    poweredBySection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .background(AppColors.backgroundPrimaryDark.ignoresSafeArea())
            .navigationBarHidden(true)
            .task { await viewModel.refresh() }
            .refreshable { await viewModel.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task { await viewModel.refresh() }
            }
            .sheet(isPresented: $viewModel.showAddModelSheet) {
                AddModelURLSheet(isPresented: $viewModel.showAddModelSheet) { url, name in
                    viewModel.addModelFromURL(url, name: name)
                }
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image("yaprun_logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text("YapRun")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)

            Text("On-device voice dictation")
                .font(.subheadline)
                .foregroundStyle(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }

    // MARK: - Status

    private var statusSection: some View {
        VStack(spacing: 10) {
            // Microphone
            statusCard(
                icon: viewModel.micPermission.icon,
                title: "Microphone",
                subtitle: viewModel.micPermission.label,
                color: viewModel.micPermission.color,
                actionLabel: micActionLabel,
                action: micAction
            )

            // Keyboard
            statusCard(
                icon: viewModel.keyboardReady ? "checkmark.circle.fill" : "keyboard",
                title: "Keyboard",
                subtitle: viewModel.keyboardReady
                    ? "Installed with Full Access"
                    : "Settings → General → Keyboard → Add YapRun",
                color: viewModel.keyboardReady ? AppColors.primaryGreen : .orange,
                actionLabel: viewModel.keyboardReady ? nil : "Setup",
                action: viewModel.keyboardReady ? nil : { viewModel.openSettings() }
            )
        }
    }

    private var micActionLabel: String? {
        switch viewModel.micPermission {
        case .unknown: return "Allow"
        case .denied:  return "Settings"
        case .granted: return nil
        }
    }

    private var micAction: (() -> Void)? {
        switch viewModel.micPermission {
        case .unknown: return { Task { await viewModel.requestMicPermission() } }
        case .denied:  return { viewModel.openSettings() }
        case .granted: return nil
        }
    }

    private func statusCard(
        icon: String,
        title: String,
        subtitle: String,
        color: Color,
        actionLabel: String?,
        action: (() -> Void)?
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            if let label = actionLabel, let action {
                Button(label, action: action)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.12), in: Capsule())
            }
        }
        .padding(14)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppColors.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Session Indicator

    @ViewBuilder
    private var sessionIndicator: some View {
        if let label = sessionPhaseLabel {
            HStack(spacing: 10) {
                if flowSession.sessionPhase != .idle {
                    ProgressView()
                        .tint(AppColors.ctaOrange)
                        .scaleEffect(0.8)
                }
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(AppColors.ctaOrange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var sessionPhaseLabel: String? {
        switch flowSession.sessionPhase {
        case .idle:           return nil
        case .activating:     return "Starting microphone…"
        case .ready:          return "Mic ready — tap mic icon to dictate"
        case .listening:      return "Listening…"
        case .transcribing:   return "Transcribing…"
        case .done(let text): return "Done: \"\(text.prefix(40))\""
        }
    }

    // MARK: - Models

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Models")
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                Button {
                    viewModel.showAddModelSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Add URL")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08), in: Capsule())
                }
            }

            if viewModel.models.isEmpty {
                Text("No speech recognition models registered.")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ForEach(viewModel.models) { model in
                    ModelCardView(
                        model: model,
                        isActive: model.id == viewModel.currentSTTModelId,
                        downloadProgress: viewModel.downloadProgress[model.id],
                        onDownload: { Task { await viewModel.downloadModel(model.id) } },
                        onLoad: { Task { await viewModel.loadModel(model.id) } },
                        onDelete: { Task { await viewModel.deleteModel(model.id) } }
                    )
                }
            }

            Text("All transcription runs fully on-device — no data leaves your phone.")
                .font(.caption)
                .foregroundStyle(AppColors.textTertiary)
                .padding(.top, 4)
        }
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Dictations")
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                Button("Clear") { viewModel.clearHistory() }
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }

            VStack(spacing: 0) {
                ForEach(Array(viewModel.dictationHistory.prefix(10).enumerated()), id: \.element.id) { index, entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.text)
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(2)
                        Text(entry.date, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)

                    if index < min(viewModel.dictationHistory.count, 10) - 1 {
                        Divider()
                            .background(AppColors.cardBorder)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppColors.cardBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Footer

    private var poweredBySection: some View {
        Link(destination: Self.sdkURL) {
            HStack(spacing: 10) {
                Image("runanywhere_logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Powered by RunAnywhere SDKs")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                    Text("github.com/RunanywhereAI")
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                }

                Spacer()

                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(14)
            .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppColors.cardBorder, lineWidth: 1)
            )
        }
        .padding(.top, 8)
    }
}

#endif
