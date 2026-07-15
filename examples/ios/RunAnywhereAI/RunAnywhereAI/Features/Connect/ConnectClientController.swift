//
//  ConnectClientController.swift
//  RunAnywhereAI
//
//  iPhone and iPad discovery, pairing, and banner state for a Mac host.
//

#if os(iOS)
import Combine
import Foundation
import RunAnywhere

@MainActor
final class ConnectClientController: ObservableObject {
    static let shared = ConnectClientController()

    let session = ConnectSession()

    @Published private var dismissedBannerKey: String?
    @Published private var presentationRevision = 0

    private var sessionCancellable: AnyCancellable?
    private var autoDismissTask: Task<Void, Never>?

    private init() {
        // ConnectSession owns the transport state. Forward its changes so one
        // app-level controller can drive the banner and chat surface together.
        sessionCancellable = session.objectWillChange
            .sink { [weak self] _ in
                // `@Published` emits before ConnectSession applies its new
                // value. Publish on the next main-loop turn so SwiftUI reads
                // the updated status, host, and model together.
                DispatchQueue.main.async {
                    self?.presentationRevision &+= 1
                    self?.updateAutomaticDismissal()
                }
            }
    }

    deinit {
        autoDismissTask?.cancel()
    }

    var isConnected: Bool {
        session.status == .connected
    }

    var discoveredHost: ConnectHost? {
        session.availableHosts.first
    }

    var shouldPresentBanner: Bool {
        guard let bannerKey else { return false }
        return dismissedBannerKey != bannerKey
    }

    func startDiscovery() async {
        guard !isConnected else { return }
        if case .discovering = session.status { return }

        do {
            try await session.startBrowsing()
        } catch {
            // The session exposes this error through its status so the same
            // banner can communicate both discovery and connection failures.
        }
    }

    func connect(to host: ConnectHost) async {
        autoDismissTask?.cancel()
        dismissedBannerKey = nil
        do {
            try await session.connect(to: host)
        } catch {
            // Session status and lastError are updated by ConnectSession.
        }
    }

    func disconnect() {
        autoDismissTask?.cancel()
        // Disconnecting keeps Bonjour discovery running, but avoid immediately
        // reopening the exact same availability prompt the user just dismissed.
        let nextAvailableKey = discoveredHost.map { "available:\($0.id)" }
        session.disconnect()
        dismissedBannerKey = nextAvailableKey
    }

    func dismissBanner() {
        autoDismissTask?.cancel()
        dismissedBannerKey = bannerKey
    }

    private func updateAutomaticDismissal() {
        autoDismissTask?.cancel()

        guard case .connected = session.status,
              let key = bannerKey else {
            return
        }

        // A newly-connected state must always be visible once before it
        // fades away. Any later disconnect gets a different key and is shown
        // immediately, even if this success state was already dismissed.
        dismissedBannerKey = nil
        autoDismissTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(6))
            } catch {
                return
            }
            self?.dismissConnectedBanner(matching: key)
        }
    }

    private func dismissConnectedBanner(matching key: String) {
        guard case .connected = session.status,
              bannerKey == key else {
            return
        }
        dismissedBannerKey = key
    }

    private var bannerKey: String? {
        switch session.status {
        case .connecting:
            return "connecting:\(session.connectingHost?.id ?? "unknown")"
        case .connected:
            return "connected:\(session.activeHost?.id ?? "unknown")"
        case let .disconnected(reason):
            return "disconnected:\(session.lastDisconnectedHost?.id ?? "unknown"):\(reason)"
        case let .failed(message):
            return "failed:\(message)"
        case .discovering, .idle:
            return discoveredHost.map { "available:\($0.id)" }
        case .hosting:
            return nil
        }
    }
}
#endif
