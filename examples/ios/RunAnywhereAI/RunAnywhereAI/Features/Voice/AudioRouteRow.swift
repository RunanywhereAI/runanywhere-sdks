//
//  AudioRouteRow.swift
//  RunAnywhereAI
//
//  Shows which speaker and which microphone the system is actually going to use.
//
//  Every voice failure looks the same from the user's side: nothing is
//  transcribed and the agent never answers. The cause is very often the route
//  rather than the model — a Bluetooth headset whose mic is muted, a meeting app
//  that parked a virtual device as the default, or a loopback device selected as
//  the input, which delivers digital silence with no error anywhere. The SDK can
//  detect "I can't hear you", but only the device name tells the user what to go
//  and change.
//
//  The view is deliberately thin: `RunAnywhere.AudioRouteMonitor` owns the two
//  very different Apple APIs behind this (AVAudioSession on iOS, CoreAudio on
//  macOS), so this file only renders what it reports.

import RunAnywhere
import SwiftUI

/// A compact "Speaker · Microphone" readout that follows live route changes.
struct AudioRouteRow: View {
    /// Starts `nil` so the row can render nothing at all until the first reading
    /// arrives — an empty row is better than one that momentarily claims the
    /// wrong device.
    @State private var route: AudioRoute?

    var body: some View {
        Group {
            if let route {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    HStack(spacing: AppSpacing.large) {
                        endpoint(route.output, fallbackSymbol: "speaker.wave.2.fill", label: "Speaker")
                        endpoint(route.input, fallbackSymbol: "mic.fill", label: "Microphone")
                    }

                    // Only shown when the route itself is the problem. Absence is
                    // not a promise that audio works — just that the route is not
                    // the reason it does not.
                    if let warning = route.inputWarning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.warningText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .task {
            // The stream yields the current route immediately and again on every
            // system change — AirPods connecting, a cable pulled, another app
            // taking the default. Reading once would leave the row describing a
            // device the user has already stopped using.
            for await update in AudioRouteMonitor.routes() {
                route = update
            }
        }
    }

    @ViewBuilder
    private func endpoint(
        _ endpoint: AudioRouteEndpoint?,
        fallbackSymbol: String,
        label: String
    ) -> some View {
        HStack(spacing: AppSpacing.xSmall) {
            Image(systemName: endpoint?.kind.symbolName ?? fallbackSymbol)
                .font(AppTypography.caption)
                .foregroundColor(
                    // Amber, not red: a virtual input is a misconfiguration the
                    // user can fix in seconds, not an app failure.
                    endpoint?.kind.isLikelySilentAsInput == true
                        ? AppColors.warningText
                        : AppColors.textSecondary
                )
            Text(endpoint?.displayName ?? "None")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(endpoint?.displayName ?? "none selected")")
    }
}
