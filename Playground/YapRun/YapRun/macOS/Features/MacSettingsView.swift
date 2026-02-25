#if os(macOS)
//
//  MacSettingsView.swift
//  YapRun
//
//  macOS settings: launch at login, sound effects, Flow Bar toggle, permissions.
//

import SwiftUI
import ServiceManagement

struct MacSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("soundEffects") private var soundEffectsEnabled = true
    @AppStorage("showFlowBar") private var showFlowBar = true

    @State private var micState: MicPermissionState = MacPermissionService.microphoneState
    @State private var accessibilityGranted = MacPermissionService.isAccessibilityGranted

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                generalSection
                permissionsSection
                aboutSection
            }
            .padding(24)
        }
        .background(AppColors.backgroundPrimaryDark)
        .onAppear { refreshPermissions() }
    }

    // MARK: - General

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("General")
                .font(.headline)
                .foregroundStyle(AppColors.textPrimary)

            toggleRow(
                icon: "power",
                title: "Launch at Login",
                subtitle: "Start YapRun when you log in",
                isOn: $launchAtLogin
            )
            .onChange(of: launchAtLogin) { _, newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    launchAtLogin = !newValue
                }
            }

            toggleRow(
                icon: "speaker.wave.2",
                title: "Sound Effects",
                subtitle: "Audio feedback on dictation start/stop",
                isOn: $soundEffectsEnabled
            )

            toggleRow(
                icon: "capsule",
                title: "Show Flow Bar",
                subtitle: "Floating dictation indicator at bottom of screen",
                isOn: $showFlowBar
            )
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Permissions")
                .font(.headline)
                .foregroundStyle(AppColors.textPrimary)

            permissionRow(
                icon: "mic.fill",
                title: "Microphone",
                state: micState == .granted ? "Granted" : "Not Granted",
                isGranted: micState == .granted,
                action: {
                    MacPermissionService.openMicrophoneSettings()
                }
            )

            permissionRow(
                icon: "lock.shield",
                title: "Accessibility",
                state: accessibilityGranted ? "Granted" : "Not Granted",
                isGranted: accessibilityGranted,
                action: {
                    MacPermissionService.openAccessibilitySettings()
                }
            )
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .font(.headline)
                .foregroundStyle(AppColors.textPrimary)

            HStack(spacing: 12) {
                Image("yaprun_logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("YapRun")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text("On-device voice dictation powered by RunAnywhere SDK")
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }

                Spacer()
            }
            .padding(14)
            .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppColors.cardBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Components

    private func toggleRow(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 32, height: 32)
                .background(AppColors.overlayThin, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppColors.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(14)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppColors.cardBorder, lineWidth: 1)
        )
    }

    private func permissionRow(icon: String, title: String, state: String, isGranted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(isGranted ? AppColors.primaryGreen : .orange)
                .frame(width: 32, height: 32)
                .background((isGranted ? AppColors.primaryGreen : Color.orange).opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppColors.textPrimary)
                Text(state)
                    .font(.caption)
                    .foregroundStyle(isGranted ? AppColors.primaryGreen : AppColors.textTertiary)
            }

            Spacer()

            if !isGranted {
                Button("Open Settings", action: action)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppColors.overlayMedium, in: Capsule())
                    .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppColors.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func refreshPermissions() {
        micState = MacPermissionService.microphoneState
        accessibilityGranted = MacPermissionService.isAccessibilityGranted
    }
}

#endif
