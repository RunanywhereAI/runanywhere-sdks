import SwiftUI
import RunAnywhere
#if canImport(UIKit)
import UIKit
#endif

struct VoiceAssistantView: View {
    /// Which single-component picker the setup card asked for while it was still
    /// on screen. Consumed once the card's own sheet has finished dismissing.
    private enum PendingPicker {
        case stt, llm, tts
    }

    @StateObject private var viewModel = VoiceAgentViewModel()
    @State private var showModelInfo = false
    @State private var showModelSelection = false
    @State private var showSTTModelSelection = false
    @State private var showLLMModelSelection = false
    @State private var showTTSModelSelection = false
    @State private var pendingPicker: PendingPicker?

    // Particle animation states
    @State private var amplitude: Float = 0.0
    @State private var morphProgress: Float = 0.0
    @State private var scatterAmount: Float = 0.0
    @State private var touchPoint: SIMD2<Float> = .zero
    @Environment(\.colorScheme)
    var colorScheme

    private let animationTimer = Timer.publish(every: 0.016, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            #if os(macOS)
            macOSContent
            #else
            iOSContent
            #endif
        }
        .adaptiveSheet(isPresented: $showModelSelection, onDismiss: presentPendingPicker) {
            modelSelectionSheet
        }
        .adaptiveSheet(isPresented: $showSTTModelSelection) {
            ModelSelectionSheet(context: .stt) { model in
                await viewModel.setSTTModel(model)
            }
        }
        .adaptiveSheet(isPresented: $showLLMModelSelection) {
            ModelSelectionSheet(context: .llm) { model in
                await viewModel.setLLMModel(model)
            }
        }
        .adaptiveSheet(isPresented: $showTTSModelSelection) {
            ModelSelectionSheet(context: .tts) { model in
                await viewModel.setTTSModel(model)
            }
        }
        .onAppear {
            Task {
                if !viewModel.isInitialized {
                    await viewModel.initialize()
                } else {
                    viewModel.refreshComponentStatesFromSDK()
                }
            }
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }

    /// Remember which picker to open and close the card that asked for it.
    private func requestPicker(_ picker: PendingPicker) {
        pendingPicker = picker
        showModelSelection = false
    }

    /// Open it, now that the presenting sheet is actually gone.
    private func presentPendingPicker() {
        guard let picker = pendingPicker else { return }
        pendingPicker = nil
        switch picker {
        case .stt: showSTTModelSelection = true
        case .llm: showLLMModelSelection = true
        case .tts: showTTSModelSelection = true
        }
    }
}

#if os(macOS)
// MARK: - macOS Content
extension VoiceAssistantView {
    private var macOSContent: some View {
        VStack(spacing: 0) {
            macOSToolbar
            Divider()
            if !viewModel.allModelsLoaded {
                VoiceAISetupCard(
                    viewModel: viewModel,
                    onChangeSTT: { showSTTModelSelection = true },
                    onChangeLLM: { showLLMModelSelection = true },
                    onChangeTTS: { showTTSModelSelection = true }
                )
            } else {
                if showModelInfo {
                    modelInfoSection
                }
                macOSConversationArea
                Spacer()
                controlArea
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.backgroundPrimary)
    }

    private var macOSToolbar: some View {
        HStack {
            Button(action: {
                showModelSelection = true
            }, label: {
                Label("Models", systemImage: "cube")
            })
            .buttonStyle(.bordered)
            .tint(AppColors.primaryAccent)

            Spacer()

            HStack(spacing: Space.sm) {
                Circle()
                    .fill(viewModel.statusColor.swiftUIColor)
                    .frame(width: 8, height: 8)
                Text(viewModel.statusLabel)
                    .appType(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            // One element, one announcement: the dot is decoration and the word
            // beside it is the state, so the two are read together and the
            // colour is never the only carrier.
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Voice session: \(viewModel.statusLabel)")

            Spacer()

            Button(action: {
                withMotion(Motion.standardSpring) {
                    showModelInfo.toggle()
                }
            }, label: {
                Label(
                    showModelInfo ? "Hide Info" : "Show Info",
                    systemImage: "info.circle"
                )
            })
            .buttonStyle(.bordered)
            .tint(AppColors.primaryAccent)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(AppColors.backgroundPrimary)
    }

    /// The transcript and the reply, each always present once a session exists.
    ///
    /// Both panes used to disappear when empty and fall back to one fixed line,
    /// "Click the microphone to start" — which stayed on screen while the agent
    /// was listening, thinking, and talking. The panel is now two labelled
    /// regions whose empty text is derived from the session state, so it can
    /// never claim something the status indicator above it contradicts.
    private var macOSConversationArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    if viewModel.isActive
                        || !viewModel.currentTranscript.isEmpty
                        || !viewModel.assistantResponse.isEmpty {
                        transcriptPane
                        replyPane.id("assistant")
                    } else {
                        // One verb per platform, resolved centrally: this line
                        // and the instruction under the button used to say
                        // "Click" and "Tap" about the same control.
                        emptyStatePlaceholder(
                            text: "\(VoiceAgentViewModel.pressVerb) the microphone to start"
                        )
                    }
                }
                .padding(.horizontal, AdaptiveSizing.contentPadding)
                .padding(.vertical, Space.xl)
                .adaptiveConversationWidth()
            }
            .onChange(of: viewModel.assistantResponse) { _, _ in
                withMotion(Motion.standardSpring) {
                    proxy.scrollTo("assistant", anchor: .bottom)
                }
            }
        }
    }

    private var transcriptPane: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Text("You said")
                    .appType(.overline)
                    .foregroundStyle(AppColors.textSecondary)
                if !viewModel.currentTranscript.isEmpty && !viewModel.isTranscriptFinal {
                    PartialSpeechBadge()
                }
            }

            ConversationBubble(
                speaker: "You",
                message: viewModel.currentTranscript.isEmpty
                    ? viewModel.transcriptPlaceholder
                    : viewModel.currentTranscript,
                isUser: true,
                isPlaceholder: viewModel.currentTranscript.isEmpty,
                isPartial: !viewModel.currentTranscript.isEmpty && !viewModel.isTranscriptFinal
            )
        }
    }

    private var replyPane: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Reply")
                .appType(.overline)
                .foregroundStyle(AppColors.textSecondary)

            ConversationBubble(
                speaker: "Assistant",
                message: viewModel.assistantResponse.isEmpty
                    ? viewModel.replyPlaceholder
                    : viewModel.assistantResponse,
                isUser: false,
                isPlaceholder: viewModel.assistantResponse.isEmpty
            )
        }
    }
}
#endif

#if os(iOS)
// MARK: - iOS Content
extension VoiceAssistantView {
    private var iOSContent: some View {
        ZStack {
            if !viewModel.allModelsLoaded {
                setupView
            } else {
                mainVoiceUI
            }
        }
    }

    private var setupView: some View {
        VoiceAISetupCard(
            viewModel: viewModel,
            onChangeSTT: { showSTTModelSelection = true },
            onChangeLLM: { showLLMModelSelection = true },
            onChangeTTS: { showTTSModelSelection = true }
        )
    }

    private var mainVoiceUI: some View {
        ZStack {
            // Background particles animation - centered
            GeometryReader { geometry in
                VoiceAssistantParticleView(
                    amplitude: amplitude,
                    morphProgress: morphProgress,
                    scatterAmount: scatterAmount,
                    touchPoint: touchPoint,
                    isDarkMode: colorScheme == .dark
                )
                .frame(width: min(geometry.size.width, geometry.size.height) * 0.9)
                .frame(width: min(geometry.size.width, geometry.size.height) * 0.9)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2 - 50)
                .allowsHitTesting(false)
            }

            // Main UI overlay
            VStack(spacing: 0) {
                iOSHeader
                if showModelInfo {
                    modelInfoSection
                }
                iOSConversationArea
                Spacer()
                iOSControlArea
            }
        }
        .background(Color(.systemBackground))
        .onReceive(animationTimer) { _ in
            updateAnimation()
        }
    }

    private var iOSHeader: some View {
        HStack {
            Button(action: {
                showModelSelection = true
            }, label: {
                Image(systemName: "cube")
                    .font(AppTypography.system18)
                    .foregroundColor(.secondary)
                    .padding(10)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(Circle())
            })
            .accessibilityLabel("Voice models")

            Spacer()

            // The same status readout macOS, Android and Web all carry. iPhone
            // had none: the only signal was the mic button's colour, so an idle
            // screen and a screen whose event stream had died were
            // indistinguishable — which is exactly what made the dead-panel
            // failure so hard to see. The dot is decoration; the word beside it
            // is the state, so colour is never the only carrier.
            HStack(spacing: Space.sm) {
                Circle()
                    .fill(viewModel.statusColor.swiftUIColor)
                    .frame(width: 8, height: 8)
                Text(viewModel.statusLabel)
                    .appType(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Voice session: \(viewModel.statusLabel)")

            Spacer()

            Button(action: {
                withMotion(Motion.standardSpring) {
                    showModelInfo.toggle()
                }
            }, label: {
                Image(systemName: showModelInfo ? "info.circle.fill" : "info.circle")
                    .font(AppTypography.system18)
                    .foregroundColor(.secondary)
                    .padding(10)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(Circle())
            })
            .accessibilityLabel(showModelInfo ? "Hide pipeline details" : "Show pipeline details")
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 10)
    }

    /// Deliberately empty: on iPhone the transcript and the reply are rendered
    /// just above the mic in `iOSControlArea`, so the particle field owns this
    /// space. The comment here used to say the messages appeared "as toast at
    /// bottom", which was never true of any build and sent readers looking for a
    /// toast that does not exist.
    private var iOSConversationArea: some View {
        Spacer()
    }

    private var iOSControlArea: some View {
        VStack(spacing: Space.xl) {
            if let error = viewModel.errorMessage {
                Text(error)
                    .appType(.caption)
                    .foregroundStyle(AppColors.statusRed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.xl)
            }

            // What the recogniser heard. Shown even while it is still a
            // hypothesis — that is the only feedback that the microphone is
            // actually working — but marked as one, because the words in a
            // partial visibly change and an unmarked one reads as a glitch.
            if !viewModel.currentTranscript.isEmpty {
                VStack(spacing: Space.sm) {
                    Text(viewModel.currentTranscript)
                        .appType(.secondary)
                        .italic(!viewModel.isTranscriptFinal)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, Space.xl)

                    if !viewModel.isTranscriptFinal {
                        PartialSpeechBadge()
                    }
                }
                .transition(.opacity)
            }

            // Scrollable markdown response - streaming real-time
            if !viewModel.assistantResponse.isEmpty {
                ScrollView {
                    ScrollViewReader { proxy in
                        VStack {
                            AdaptiveMarkdownText(
                                viewModel.assistantResponse,
                                font: AppType.font(.body),
                                color: AppColors.textPrimary
                            )
                            .multilineTextAlignment(.center)
                            .id("responseEnd")
                        }
                        .padding(.horizontal, Space.xl)
                        .onChange(of: viewModel.assistantResponse) { _, _ in
                            withMotion(Motion.standardSpring) {
                                proxy.scrollTo("responseEnd", anchor: .bottom)
                            }
                        }
                    }
                }
                .frame(maxHeight: 150)
                .animation(.none, value: viewModel.assistantResponse)
                // A long reply is taller than this box, and it used to be cut
                // straight through the middle of a glyph line — which reads as
                // broken rendering, not as content that continues. The fade
                // makes the bottom edge mean "more below", and lands on a soft
                // boundary instead of half a row of letters.
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.86),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            micButtonSection

            Text(viewModel.instructionText)
                .appType(.caption)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                // The line changes wording every turn; a crossfade keeps it from
                // snapping while the particle field behind it is still moving.
                .motionAware(Motion.standardFade, value: viewModel.instructionText)

            endButton
        }
        .motionAware(Motion.standardSpring, value: viewModel.currentTranscript.isEmpty)
        .padding(.bottom, Space.xl)
    }

    private var audioLevelIndicator: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(AppColors.statusRed)
                    .frame(width: 8, height: 8)
                Text("RECORDING")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(AppColors.statusRed)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppColors.statusRed.opacity(0.1))
            .cornerRadius(AppSpacing.cornerRadiusSmall)

            AdaptiveAudioLevelIndicator(level: viewModel.audioLevel)
        }
        .padding(.bottom, 8)
        // `AudioActivityBars` already animates the level on the micro tier; a
        // second animation on the same value from an ancestor just fights it.
        // Left here only for the surrounding row's own changes.
        .motionAware(Motion.microFade, value: viewModel.audioLevel)
    }
}
#endif

// MARK: - Shared Components

extension VoiceAssistantView {
    private var modelInfoSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 15) {
                ModelBadge(
                    icon: "brain",
                    label: "LLM",
                    value: viewModel.currentLLMModel,
                    color: AppColors.primaryAccent
                )
                ModelBadge(
                    icon: "waveform",
                    label: "STT",
                    value: viewModel.currentSTTModel,
                    color: AppColors.statusGreen
                )
                ModelBadge(
                    icon: "speaker.wave.2",
                    label: "TTS",
                    value: viewModel.currentTTSModel,
                    color: AppColors.primaryPurple
                )
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 15)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func emptyStatePlaceholder(text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.circle")
                .font(AppTypography.system48)
                .foregroundColor(.secondary.opacity(0.3))
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }

    private var controlArea: some View {
        VStack(spacing: Space.xl) {
            if let error = viewModel.errorMessage {
                Text(error)
                    .appType(.caption)
                    .foregroundStyle(AppColors.statusRed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.xl)
            }

            micButtonSection

            Text(viewModel.instructionText)
                .appType(.caption)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .motionAware(Motion.standardFade, value: viewModel.instructionText)

            endButton
        }
        .padding(.bottom, Space.xl)
    }

    /// Ends the session, visibly.
    ///
    /// Ending used to be reachable only by long-pressing the mic — a gesture
    /// with no affordance anywhere on screen, and one that did not fire:
    /// measured 1.2 s and 1.5 s holds at verified coordinates produced no state
    /// change at all, while taps at the same point worked every time (the
    /// `LongPressGesture` is attached with `.simultaneousGesture` to a Button
    /// under `.glassEffect(.interactive())`, the same layer that already had to
    /// be worked around for taps). Hanging up is not an advanced action and does
    /// not belong behind a hidden gesture, so it is a button. The long press
    /// stays wired as a shortcut for anyone who learned it.
    @ViewBuilder private var endButton: some View {
        if viewModel.isActive || viewModel.sessionState == .connected {
            Button {
                Task { await viewModel.stopConversation() }
            } label: {
                HStack(spacing: Space.sm) {
                    Image(systemName: "phone.down.fill")
                    Text("End")
                }
                .appType(.caption)
                .padding(.horizontal, Space.lg)
                .frame(minHeight: 44)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColors.textSecondary)
            .background(
                Capsule().fill(AppColors.backgroundSecondary)
            )
            .accessibilityLabel("End conversation")
        }
    }

    private var micButtonSection: some View {
        let isLoading = viewModel.sessionState == .connecting
            || (viewModel.isProcessing && !viewModel.isListening)

        return HStack {
            Spacer()

            AdaptiveMicButton(
                isActive: viewModel.isListening,
                isPulsing: viewModel.isSpeechDetected,
                isLoading: isLoading,
                activeColor: viewModel.micButtonColor.swiftUIColor,
                inactiveColor: viewModel.micButtonColor.swiftUIColor,
                icon: viewModel.micButtonIcon,
                action: {
                    // Snapshot state synchronously so the decision can't race with
                    // state updates that happen between the tap and the Task firing.
                    //
                    // Two live meanings, and only two: start when idle, and cut
                    // the agent off while it is talking. Barge-in is the control
                    // a voice conversation needs most — a person who has heard
                    // enough talks over the assistant rather than hanging up —
                    // and it was the one thing this button could not do, even
                    // though `VoiceSession.interrupt()` has always existed.
                    // A tap while listening or thinking stays inert: there is
                    // nothing to cut off, and the VAD decides when a turn ends.
                    if viewModel.canInterrupt {
                        Task { await viewModel.interruptAgent() }
                        return
                    }
                    let isActive = viewModel.isActive
                    let isConnected = viewModel.sessionState == .connected
                    guard !isActive && !isConnected else { return }
                    Task { await viewModel.startConversation() }
                },
                onLongPress: {
                    // Snapshot state synchronously before spawning the Task.
                    let shouldStop = viewModel.isActive || viewModel.sessionState == .connected
                    guard shouldStop else { return }
                    Task { await viewModel.stopConversation() }
                }
            )
            // The Mac's accessibility tree reported this 88x88 control as a bare
            // `AXButton` with no title, description or value — one of five
            // unnamed buttons on the screen. The label names the action for the
            // current state; the value carries the state itself, so neither is
            // inferred from the button's colour.
            .accessibilityLabel(viewModel.micButtonAccessibilityLabel)
            .accessibilityValue(viewModel.statusLabel)

            Spacer()
        }
    }
}

// MARK: - Model Selection Sheet

extension VoiceAssistantView {
    private var modelSelectionSheet: some View {
        NavigationStack {
            VoiceAISetupCard(
                viewModel: viewModel,
                // Chained off this sheet's dismissal (see `onDismiss` on the
                // presenter), not raced behind a fixed 0.3s delay: a sheet that
                // is still animating out swallows the next presentation, and a
                // machine slower than the guess showed nothing at all.
                onChangeSTT: { requestPicker(.stt) },
                onChangeLLM: { requestPicker(.llm) },
                onChangeTTS: { requestPicker(.tts) }
            )
            .navigationTitle("Voice Models")
            #if os(iOS)
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showModelSelection = false
                    }
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showModelSelection = false
                    }
                }
            }
            #endif
        }
    }

    // MARK: - Animation Helpers
    private func updateAnimation() {
        // Target morph: 0 = sphere (idle/thinking), 1 = ring (listening/speaking)
        let isListening = viewModel.sessionState == .listening
        let isSpeaking = viewModel.sessionState == .speaking
        let isActive = isListening || isSpeaking
        let targetMorph: Float = isActive ? 1.0 : 0.0

        // Smooth morph transition
        let morphDiff = targetMorph - morphProgress
        morphProgress += morphDiff * 0.04
        morphProgress = max(0, min(1, morphProgress))

        // Scatter decay
        if scatterAmount > 0.001 {
            scatterAmount *= 0.92
        } else {
            scatterAmount = 0
        }

        // Amplitude while the session is active. Neither branch claims to be a
        // level meter: `VoiceEvent` carries no audio-level arm, so nothing ever
        // raises `viewModel.audioLevel` above zero. Reading it here made the
        // ring decay to nothing the moment listening began and then sit still
        // through an entire utterance — an indicator that looked live and was
        // dead, which is worse than an honestly indeterminate one.
        if isListening {
            // Indeterminate breathe on the continuous tier (1.6s period), the
            // same treatment the other apps give a live-but-unmeasured mic.
            let time = Float(Date().timeIntervalSinceReferenceDate)
            let breathe = 0.28 + abs(sin(time * .pi / 0.8)) * 0.16
            amplitude = amplitude * 0.85 + breathe * 0.15
            amplitude = max(0.0, min(1.0, amplitude))
        } else if isSpeaking {
            // TTS output - realistic speech-like pulse simulation
            let time = Float(Date().timeIntervalSinceReferenceDate)

            // Multiple frequency components for natural speech rhythm
            let basePulse: Float = 0.35
            let primaryWave = sin(time * 3.5) * 0.2         // Main speech rhythm
            let secondaryWave = sin(time * 7.0) * 0.1       // Phoneme-like variation
            let randomNoise = Float.random(in: -0.05...0.15) // Natural variation

            let targetAmplitude = basePulse + abs(primaryWave) + abs(secondaryWave) * 0.5 + randomNoise

            // Smooth interpolation to avoid jarring changes
            amplitude = amplitude * 0.75 + targetAmplitude * 0.25
            amplitude = max(0.0, min(1.0, amplitude))
        } else {
            // Gentle decay when not active
            amplitude *= 0.95
        }
    }
}

// MARK: - Preview
struct VoiceAssistantView_Previews: PreviewProvider {
    static var previews: some View {
        VoiceAssistantView()
    }
}
