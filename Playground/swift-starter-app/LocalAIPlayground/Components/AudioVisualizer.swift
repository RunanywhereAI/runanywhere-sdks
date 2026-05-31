//
//  AudioVisualizer.swift
//  LocalAIPlayground
//
//  =============================================================================
//  AUDIO VISUALIZER - REAL-TIME AUDIO VISUALIZATION
//  =============================================================================
//
//  A collection of audio visualization components for displaying:
//  - Real-time audio input levels during recording
//  - Audio output levels during playback
//  - Waveform animations
//  - Recording state indicators
//
//  These components provide visual feedback to users during STT recording
//  and TTS playback operations.
//
//  =============================================================================

import SwiftUI

// =============================================================================
// MARK: - Audio Level Bars
// =============================================================================
/// An animated bar visualization showing current audio level.
///
/// Used to provide visual feedback during recording or playback.
// =============================================================================
struct AudioLevelBars: View {
    /// Current audio level from 0.0 to 1.0
    let level: Float
    
    /// Number of bars to display
    let barCount: Int
    
    /// Color for active bars
    let activeColor: Color
    
    /// Color for inactive bars
    let inactiveColor: Color
    
    init(
        level: Float,
        barCount: Int = 5,
        activeColor: Color = .aiPrimary,
        inactiveColor: Color = .secondary.opacity(0.3)
    ) {
        self.level = level
        self.barCount = barCount
        self.activeColor = activeColor
        self.inactiveColor = inactiveColor
    }
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(isBarActive(index) ? activeColor : inactiveColor)
                    .frame(width: 4, height: barHeight(for: index))
                    .animation(.easeInOut(duration: 0.1), value: level)
            }
        }
    }
    
    private func isBarActive(_ index: Int) -> Bool {
        let threshold = Float(index + 1) / Float(barCount)
        return level >= threshold * 0.8
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        let minHeight: CGFloat = 8
        let maxHeight: CGFloat = 24
        let progress = CGFloat(index + 1) / CGFloat(barCount)
        return minHeight + (maxHeight - minHeight) * progress
    }
}

// =============================================================================
// MARK: - Waveform Visualizer
// =============================================================================
/// An animated waveform visualization with flowing waves.
///
/// Creates a dynamic, organic-looking audio visualization.
// =============================================================================
struct WaveformVisualizer: View {
    /// Current audio level from 0.0 to 1.0
    let level: Float
    
    /// Whether the visualization is active
    let isActive: Bool
    
    /// Number of wave segments
    let segments: Int
    
    /// Primary color for the waveform
    let color: Color
    
    @State private var phase: Double = 0
    
    init(
        level: Float,
        isActive: Bool = true,
        segments: Int = 50,
        color: Color = .aiPrimary
    ) {
        self.level = level
        self.isActive = isActive
        self.segments = segments
        self.color = color
    }
    
    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let width = size.width
            
            var path = Path()
            path.move(to: CGPoint(x: 0, y: midY))
            
            for i in 0..<segments {
                let x = width * CGFloat(i) / CGFloat(segments - 1)
                let normalizedX = Double(i) / Double(segments - 1)
                
                // Combine multiple sine waves for organic look
                let wave1 = sin((normalizedX * 4 * .pi) + phase)
                let wave2 = sin((normalizedX * 6 * .pi) + phase * 1.5) * 0.5
                let wave3 = sin((normalizedX * 8 * .pi) + phase * 0.7) * 0.25
                
                // Amplitude based on audio level
                let amplitude = Double(level) * (size.height / 3) * (isActive ? 1 : 0.1)
                let y = midY + CGFloat((wave1 + wave2 + wave3) * amplitude)
                
                path.addLine(to: CGPoint(x: x, y: y))
            }
            
            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [color.opacity(0.5), color, color.opacity(0.5)]),
                    startPoint: CGPoint(x: 0, y: midY),
                    endPoint: CGPoint(x: width, y: midY)
                ),
                lineWidth: 3
            )
        }
        .onAppear {
            if isActive {
                startAnimation()
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                startAnimation()
            }
        }
    }
    
    private func startAnimation() {
        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
            phase = .pi * 2
        }
    }
}

// =============================================================================
// MARK: - Circular Audio Visualizer
// =============================================================================
/// A circular pulsing visualization for audio levels.
///
/// Great for recording indicators and voice activity display.
// =============================================================================
struct CircularAudioVisualizer: View {
    /// Current audio level from 0.0 to 1.0
    let level: Float
    
    /// Whether actively recording/playing
    let isActive: Bool
    
    /// Size of the visualizer
    let size: CGFloat
    
    /// Primary color
    let color: Color
    
    @State private var pulseScale: CGFloat = 1
    
    init(
        level: Float,
        isActive: Bool,
        size: CGFloat = 120,
        color: Color = .aiPrimary
    ) {
        self.level = level
        self.isActive = isActive
        self.size = size
        self.color = color
    }
    
    var body: some View {
        ZStack {
            // Outer pulse ring
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 2)
                .frame(width: size * pulseScale, height: size * pulseScale)
            
            // Middle ring (responds to audio level)
            Circle()
                .stroke(color.opacity(0.4), lineWidth: 3)
                .frame(
                    width: size * 0.8 * (1 + CGFloat(level) * 0.3),
                    height: size * 0.8 * (1 + CGFloat(level) * 0.3)
                )
                .animation(.easeInOut(duration: 0.1), value: level)
            
            // Inner circle
            Circle()
                .fill(
                    RadialGradient(
                        colors: [color, color.opacity(0.7)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.3
                    )
                )
                .frame(width: size * 0.5, height: size * 0.5)
                .scaleEffect(1 + CGFloat(level) * 0.2)
                .animation(.easeInOut(duration: 0.1), value: level)
            
            // Microphone icon
            Image(systemName: isActive ? "mic.fill" : "mic")
                .font(.system(size: size * 0.15, weight: .semibold))
                .foregroundStyle(.white)
        }
        .onAppear {
            if isActive {
                startPulse()
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                startPulse()
            }
        }
    }
    
    private func startPulse() {
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            pulseScale = 1.15
        }
    }
}

// =============================================================================
// MARK: - Recording Indicator
// =============================================================================
/// A compact recording indicator with duration display.
// =============================================================================
struct RecordingIndicator: View {
    /// Whether currently recording
    let isRecording: Bool
    
    /// Recording duration in seconds
    let duration: TimeInterval
    
    @State private var dotOpacity: Double = 1
    
    var body: some View {
        HStack(spacing: AISpacing.sm) {
            // Recording dot
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
                .opacity(isRecording ? dotOpacity : 0.3)
            
            // Duration
            Text(formattedDuration)
                .font(.aiMono)
                .foregroundStyle(isRecording ? .primary : .secondary)
            
            // Status text
            Text(isRecording ? "Recording" : "Ready")
                .font(.aiCaption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, AISpacing.md)
        .padding(.vertical, AISpacing.sm)
        .background(
            Capsule()
                .fill(isRecording ? Color.red.opacity(0.15) : Color.secondary.opacity(0.1))
        )
        .onAppear {
            if isRecording {
                startBlinking()
            }
        }
        .onChange(of: isRecording) { _, recording in
            if recording {
                startBlinking()
            }
        }
    }
    
    private var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private func startBlinking() {
        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
            dotOpacity = 0.3
        }
    }
}

// =============================================================================
// MARK: - Voice Activity Indicator
// =============================================================================
/// Shows when voice activity is detected (VAD).
// =============================================================================
struct VoiceActivityIndicator: View {
    /// Whether voice is currently detected
    let isActive: Bool
    
    /// Confidence level of detection (0.0 to 1.0)
    let confidence: Float
    
    @State private var ringScale: CGFloat = 1
    
    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.aiSecondary.opacity(0.3), lineWidth: 4)
                .frame(width: 60, height: 60)
            
            // Active ring
            Circle()
                .trim(from: 0, to: isActive ? CGFloat(confidence) : 0)
                .stroke(
                    Color.aiSecondary,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: 60, height: 60)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.2), value: confidence)
            
            // Pulse effect when active
            if isActive {
                Circle()
                    .stroke(Color.aiSecondary.opacity(0.4), lineWidth: 2)
                    .frame(width: 60, height: 60)
                    .scaleEffect(ringScale)
            }
            
            // Icon
            Image(systemName: isActive ? "waveform" : "waveform.slash")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(isActive ? Color.aiSecondary : .secondary)
        }
        .onChange(of: isActive) { _, active in
            if active {
                withAnimation(.easeOut(duration: 0.8).repeatForever(autoreverses: false)) {
                    ringScale = 1.5
                }
            } else {
                ringScale = 1
            }
        }
    }
}

// =============================================================================
// MARK: - Playback Progress Bar
// =============================================================================
/// A progress bar for audio playback with time display.
// =============================================================================
struct PlaybackProgressBar: View {
    /// Current progress from 0.0 to 1.0
    let progress: Double
    
    /// Total duration in seconds
    let duration: TimeInterval
    
    /// Whether audio is currently playing
    let isPlaying: Bool
    
    var body: some View {
        VStack(spacing: AISpacing.sm) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 4)
                    
                    // Progress fill
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.aiPrimary)
                        .frame(width: geometry.size.width * progress, height: 4)
                        .animation(.linear(duration: 0.1), value: progress)
                    
                    // Playhead
                    Circle()
                        .fill(Color.aiPrimary)
                        .frame(width: 12, height: 12)
                        .offset(x: geometry.size.width * progress - 6)
                        .animation(.linear(duration: 0.1), value: progress)
                }
            }
            .frame(height: 12)
            
            // Time labels
            HStack {
                Text(formatTime(duration * progress))
                    .font(.aiCaption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text(formatTime(duration))
                    .font(.aiCaption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// =============================================================================
// MARK: - Previews
// =============================================================================
#Preview("Audio Level Bars") {
    VStack(spacing: 24) {
        AudioLevelBars(level: 0.2)
        AudioLevelBars(level: 0.5)
        AudioLevelBars(level: 0.8)
        AudioLevelBars(level: 1.0)
    }
    .padding()
}

#Preview("Waveform Visualizer") {
    VStack(spacing: 24) {
        WaveformVisualizer(level: 0.3, isActive: true)
            .frame(height: 60)
        
        WaveformVisualizer(level: 0.7, isActive: true, color: .aiSecondary)
            .frame(height: 60)
    }
    .padding()
}

#Preview("Circular Visualizer") {
    HStack(spacing: 24) {
        CircularAudioVisualizer(level: 0.3, isActive: true)
        CircularAudioVisualizer(level: 0.7, isActive: true, color: .aiSecondary)
    }
    .padding()
}

#Preview("Recording Indicator") {
    VStack(spacing: 24) {
        RecordingIndicator(isRecording: false, duration: 0)
        RecordingIndicator(isRecording: true, duration: 45.5)
    }
    .padding()
}

#Preview("Voice Activity") {
    HStack(spacing: 24) {
        VoiceActivityIndicator(isActive: false, confidence: 0)
        VoiceActivityIndicator(isActive: true, confidence: 0.8)
    }
    .padding()
}

#Preview("Playback Progress") {
    PlaybackProgressBar(progress: 0.35, duration: 125, isPlaying: true)
        .padding()
}
