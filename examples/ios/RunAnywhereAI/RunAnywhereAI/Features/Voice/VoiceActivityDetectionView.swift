import SwiftUI
import RunAnywhere
#if os(macOS)
import AppKit
#endif

/// Dedicated Voice Activity Detection view with real-time speech detection visualization
struct VoiceActivityDetectionView: View {
    @StateObject private var viewModel = VADViewModel()
    @State private var showModelPicker = false

    private var hasModelSelected: Bool {
        viewModel.selectedModelName != nil
    }

    var body: some View {
        Group {
            // A `NavigationView` wrapping a single child renders that child as
            // the *sidebar* column of a Mac split view, which is why this screen
            // drew itself in a ~200pt strip against the left edge of a 1450pt
            // detail pane. This screen is pushed from a NavigationLink, so the
            // window already owns a navigation container; on the Mac it is plain
            // content in a centred column and `.toolbar` attaches to the
            // window's own bar.
            navigationHost {
                ZStack {
                    VStack(spacing: 0) {
                        if hasModelSelected {
                            mainContentView
                            controlsView
                        } else {
                            Spacer()
                        }
                    }

                    // Overlay when no model is selected
                    if !hasModelSelected && !viewModel.isProcessing {
                        ModelRequiredOverlay(
                            modality: .vad
                        ) { showModelPicker = true }
                    }
                }
                .navigationTitle(hasModelSelected ? "Voice Activity Detection" : "")
                #if os(iOS)
                .navigationBarTitleDisplayModeCompat(.inline)
                .navigationBarHidden(!hasModelSelected)
                #endif
                .toolbar {
                    if hasModelSelected {
                        #if os(iOS)
                        ToolbarItem(placement: .navigationBarTrailing) {
                            modelButton
                        }
                        #else
                        ToolbarItem(placement: .automatic) {
                            modelButton
                        }
                        #endif
                    }
                }
            }
        }
        .adaptiveSheet(isPresented: $showModelPicker) {
            ModelSelectionSheet(context: .vad) { model in
                Task {
                    await viewModel.loadModelFromSelection(model)
                }
            }
        }
        .onAppear {
            Task {
                await viewModel.initialize()
            }
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }

    /// The navigation container this platform actually needs — see `body`.
    @ViewBuilder
    private func navigationHost<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        #if os(macOS)
        content()
            .frame(maxWidth: AdaptiveSizing.conversationMaxWidth)
            .frame(maxWidth: .infinity)
        #else
        NavigationView { content() }
            .navigationViewStyle(.stack)
        #endif
    }

    // MARK: - Main Content

    private var mainContentView: some View {
        VStack(spacing: 0) {
            if !viewModel.isListening && viewModel.activityLog.isEmpty {
                // Ready state
                readyStateView
            } else {
                // Detection display
                ScrollView {
                    VStack(spacing: 20) {
                        // Speech indicator
                        speechIndicatorView
                            .padding(.top, 24)

                        // Activity log
                        if !viewModel.activityLog.isEmpty {
                            activityLogView
                        }
                    }
                    .padding()
                }
            }
        }
    }

    // MARK: - Ready State

    private var readyStateView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 48) {
                // VAD icon
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 56))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .cyan.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(spacing: 12) {
                    Text("Ready to detect")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("\(VoiceAgentViewModel.pressVerb) the mic to start detecting speech activity")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()
        }
    }

    // MARK: - Speech Indicator

    /// The speech / silence state, as one figure.
    ///
    /// Rebuilt from two independently-animating rings (1.0s and 1.5s
    /// `repeatForever`, plus 0.3s and 0.2s off-tier eases on siblings) into a
    /// single value change with a single signature. The old version had four
    /// animations racing on one composite, which is what made the transition
    /// between speech and silence look soft and uncertain — the exact opposite
    /// of what a detector should convey.
    ///
    /// The expanding rings are kept only while speech is actually detected,
    /// where they carry information (energy is arriving now), and they are phase
    /// locked to one clock so the two rings cannot drift apart.
    private var speechIndicatorView: some View {
        VStack(spacing: Space.lg) {
            ZStack {
                if viewModel.isSpeechDetected {
                    SpeechDetectedRings(diameter: Self.indicatorDiameter)
                }

                Circle()
                    .fill(
                        viewModel.isSpeechDetected
                            ? AppColors.statusGreen.opacity(0.20)
                            : AppColors.statusGray.opacity(0.10)
                    )
                    .frame(width: Self.indicatorDiameter, height: Self.indicatorDiameter)

                Circle()
                    .fill(
                        viewModel.isSpeechDetected
                            ? AppColors.statusGreen
                            : AppColors.statusGray.opacity(0.30)
                    )
                    .frame(width: Self.coreDiameter, height: Self.coreDiameter)

                Image(systemName: viewModel.isSpeechDetected ? "mic.fill" : "mic.slash")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
                    // The glyph swaps in place rather than cross-fading two
                    // images, so the mic stays one object through the change.
                    .contentTransition(.symbolEffect(.replace))
            }
            // ONE animation for the whole figure, on the one value that changed.
            .motionAware(Motion.standardFade, value: viewModel.isSpeechDetected)

            Text(viewModel.isSpeechDetected ? "Speech detected" : "Silence")
                .appType(.cardTitle)
                .foregroundStyle(
                    viewModel.isSpeechDetected ? AppColors.statusGreen : AppColors.textSecondary
                )
                .motionAware(Motion.standardFade, value: viewModel.isSpeechDetected)

            if viewModel.isListening {
                AdaptiveAudioLevelIndicator(level: viewModel.audioLevel)
            }
        }
    }

    private static let indicatorDiameter: CGFloat = 100
    private static let coreDiameter: CGFloat = 60

    // MARK: - Activity Log

    private var activityLogView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Activity Log")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Button("Clear") {
                    viewModel.clearLog()
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            ForEach(viewModel.activityLog) { entry in
                HStack(spacing: 12) {
                    Image(systemName: entry.type.icon)
                        .font(AppTypography.system14)
                        .foregroundColor(entry.type == .speechStarted ? AppColors.statusGreen : .secondary)
                        .frame(width: 24)

                    Text(entry.type.label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(entry.type == .speechStarted ? .primary : .secondary)

                    Spacer()

                    Text(entry.timestamp, style: .time)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                #if os(iOS)
                .background(Color(.secondarySystemBackground))
                #else
                .background(Color(NSColor.controlBackgroundColor))
                #endif
                .cornerRadius(AppSpacing.cornerRadiusRegular)
            }
        }
    }

    // MARK: - Controls

    private var controlsView: some View {
        VStack(spacing: 16) {
            // Error message
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(AppColors.statusRed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Listen button
            AdaptiveMicButton(
                isActive: viewModel.isListening,
                isPulsing: viewModel.isSpeechDetected,
                isLoading: viewModel.isProcessing,
                activeColor: AppColors.statusGreen,
                inactiveColor: .cyan,
                icon: viewModel.isListening ? "stop.fill" : "mic.fill"
            ) {
                Task {
                    await viewModel.toggleListening()
                }
            }
            .disabled(
                viewModel.selectedModelName == nil || viewModel.isProcessing
            )
            .opacity(
                viewModel.selectedModelName == nil || viewModel.isProcessing ? 0.6 : 1.0
            )
            // The Mac's accessibility tree reported this as a bare `AXButton`
            // with no title, description or value.
            .accessibilityLabel(viewModel.isListening ? "Stop detection" : "Start detection")
            .accessibilityValue(viewModel.isSpeechDetected ? "Speech detected" : "Silence")

            Text(viewModel.isListening
                 ? "Listening for speech..."
                 : "\(VoiceAgentViewModel.pressVerb) to start detection")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        #if os(iOS)
        .background(Color(.systemBackground))
        #else
        .background(Color(NSColor.windowBackgroundColor))
        #endif
    }

    // MARK: - Model Button

    private var modelButton: some View {
        VoiceModelChip(
            modelName: viewModel.selectedModelName,
            framework: viewModel.selectedFramework
        ) {
            showModelPicker = true
        }
    }
}

// MARK: - Speech Detected Rings

/// Two rings expanding outward from the detector core while speech is arriving.
///
/// One clock, two phase offsets. The previous build gave each ring its own
/// `repeatForever` at a different duration (1.0s and 1.5s), so they drifted in
/// and out of alignment on a cycle of their own — visible as an irregular
/// stutter that had nothing to do with the audio. Deriving both from a single
/// `TimelineView` date means the spacing between them is fixed by construction.
///
/// This motion earns its place: it only exists while `isSpeechDetected` is true,
/// so it is a live readout of the detector, not decoration. Under Reduce Motion
/// it collapses to a single static ring — the state is still marked, nothing
/// travels.
private struct SpeechDetectedRings: View {
    let diameter: CGFloat

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    /// The canonical 1.6s ambient period, shared by both rings.
    private static let period: Double = 1.6
    /// Half a cycle apart: evenly spaced is the only spacing that reads as
    /// deliberate rather than as two things that happened to overlap.
    private static let offsets: [Double] = [0, 0.5]

    var body: some View {
        if reduceMotion {
            ring(scale: 1.20, opacity: 0.45)
        } else {
            TimelineView(.animation) { context in
                let base = Self.basePhase(at: context.date)
                ZStack {
                    ForEach(Self.offsets, id: \.self) { offset in
                        let phase = (base + offset).truncatingRemainder(dividingBy: 1)
                        ring(scale: 1.0 + 0.55 * phase, opacity: 0.55 * (1 - phase))
                    }
                }
            }
        }
    }

    private func ring(scale: CGFloat, opacity: Double) -> some View {
        Circle()
            .stroke(AppColors.statusGreen.opacity(opacity), lineWidth: Stroke.regular)
            .frame(width: diameter, height: diameter)
            .scaleEffect(scale)
            .allowsHitTesting(false)
    }

    private static func basePhase(at date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
    }
}

// MARK: - Preview

struct VoiceActivityDetectionView_Previews: PreviewProvider {
    static var previews: some View {
        VoiceActivityDetectionView()
    }
}
