//
//  ConnectStatusBanner.swift
//  RunAnywhereAI
//
//  Reuses the app's compact top-banner treatment for Connect lifecycle state.
//

#if os(iOS)
import SwiftUI

struct ConnectStatusBanner: View {
    @ObservedObject private var controller = ConnectClientController.shared

    var body: some View {
        if controller.shouldPresentBanner {
            HStack(alignment: .center, spacing: AppSpacing.medium) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTypography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                actionButton

                Button(action: controller.dismissBanner) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(AppColors.backgroundSecondary.opacity(0.8), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss Connect status")
            }
            .padding(.horizontal, AppSpacing.mediumLarge)
            .padding(.vertical, AppSpacing.medium)
            .background(bannerBackground)
            .padding(.horizontal, AppSpacing.medium)
            .padding(.bottom, AppSpacing.small)
        }
    }

    @ViewBuilder private var actionButton: some View {
        switch controller.session.status {
        case .discovering, .idle:
            if let host = controller.discoveredHost {
                Button {
                    Task { await controller.connect(to: host) }
                } label: {
                    Image(systemName: "link")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(AppColors.primaryAccent, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Connect to \(host.displayName)")
            }
        case .connecting:
            ProgressView()
                .controlSize(.small)
                .frame(width: 34, height: 34)
        case .connected:
            // A successful connection is a short-lived confirmation, not a
            // persistent control surface. Keeping an orange disconnect
            // control here made the success state look unresolved.
            EmptyView()
        case .disconnected, .failed:
            Button {
                Task { await controller.startDiscovery() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColors.primaryAccent)
                    .frame(width: 34, height: 34)
                    .background(AppColors.primaryAccent.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Find available Macs")
        case .hosting:
            EmptyView()
        }
    }

    private var icon: String {
        switch controller.session.status {
        case .connected: return "checkmark.circle.fill"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .disconnected, .failed: return "exclamationmark.triangle.fill"
        default: return "desktopcomputer"
        }
    }

    private var tint: Color {
        switch controller.session.status {
        case .connected: return AppColors.statusGreen
        case .disconnected, .failed: return AppColors.statusOrange
        default: return AppColors.primaryAccent
        }
    }

    private var title: String {
        switch controller.session.status {
        case .connected:
            return shortText(controller.session.activeHost?.displayName ?? "Connected Mac", limit: 42)
        case .connecting:
            return "Connecting to \(shortText(controller.session.connectingHost?.displayName ?? "Mac", limit: 28))"
        case .disconnected:
            return "Connection lost"
        case .failed:
            return "Couldn’t connect"
        default:
            return shortText(controller.discoveredHost?.displayName ?? "Mac", limit: 42)
        }
    }

    private var subtitle: String {
        switch controller.session.status {
        case .connected:
            return shortText(controller.session.activeModel?.displayName ?? "Using a model on this Mac", limit: 54)
        case .connecting:
            return "Checking the selected model"
        case let .disconnected(reason):
            return shortText(reason, limit: 72)
        case let .failed(message):
            return shortText(message, limit: 72)
        default:
            return "Local model ready"
        }
    }

    private func shortText(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(limit - 1)) + "…"
    }

    @ViewBuilder private var bannerBackground: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular.interactive())
                .shadow(color: .black.opacity(0.16), radius: 14, y: 5)
        } else {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.16), radius: 14, y: 5)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.3), lineWidth: 0.5)
                }
        }
    }
}
#endif
