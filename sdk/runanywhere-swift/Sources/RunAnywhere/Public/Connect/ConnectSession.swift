//
//  ConnectSession.swift
//  RunAnywhere SDK
//
//  Apple LAN discovery, host selection, and typed remote generation.
//

import Combine
import Foundation
import Network
import SwiftProtobuf

#if os(iOS)
import UIKit
#endif

/// A macOS runtime host discovered on the local network.
public struct ConnectHost: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let protocolVersion: UInt32

    public init(id: String, displayName: String, protocolVersion: UInt32) {
        self.id = id
        self.displayName = displayName
        self.protocolVersion = protocolVersion
    }
}

/// A language model selected by a Mac host and made available to a client.
///
/// Connect intentionally exposes the one model the host has loaded, rather
/// than a client-side catalog. A connected client can start text chat without
/// downloading, loading, or selecting a local language model.
public struct ConnectModel: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let framework: String
    public let contextWindow: UInt32
    public let supportsStreaming: Bool

    public init(
        id: String,
        displayName: String,
        framework: String,
        contextWindow: UInt32 = 0,
        supportsStreaming: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.framework = framework
        self.contextWindow = contextWindow
        self.supportsStreaming = supportsStreaming
    }

    fileprivate init(_ descriptor: RAConnectModelDescriptor) {
        self.init(
            id: descriptor.modelID,
            displayName: descriptor.displayName,
            framework: descriptor.framework,
            contextWindow: descriptor.contextWindow,
            supportsStreaming: descriptor.supportsStreaming
        )
    }

    fileprivate var proto: RAConnectModelDescriptor {
        var descriptor = RAConnectModelDescriptor()
        descriptor.modelID = id
        descriptor.displayName = displayName
        descriptor.framework = framework
        descriptor.contextWindow = contextWindow
        descriptor.supportsStreaming = supportsStreaming
        return descriptor
    }
}

/// The host-side operation that runs a validated text-generation request.
public typealias ConnectHostGenerationHandler = @Sendable (
    RALLMGenerateRequest
) async throws -> AsyncStream<RALLMStreamEvent>

/// The UI-safe lifecycle state for a local runtime connection.
public enum ConnectSessionStatus: Equatable, Sendable {
    case idle
    case discovering
    case connecting
    case hosting
    case connected
    case disconnected(String)
    case failed(String)
}

/// Owns the Apple transport for a local runtime session.
///
/// Commons remains the source of truth for protocol version, role validation,
/// model binding, and host-side session accounting. This type owns Bonjour and
/// the framed platform transport. It forwards the SDK's canonical streaming
/// events unchanged, so the model never needs to exist on the client device.
@MainActor
public final class ConnectSession: ObservableObject {
    @Published public private(set) var status: ConnectSessionStatus = .idle
    @Published public private(set) var availableHosts: [ConnectHost] = []
    @Published public private(set) var activeHost: ConnectHost?
    @Published public private(set) var activeModel: ConnectModel?
    @Published public private(set) var activeClientCount = 0
    @Published public private(set) var lastError: String?
    @Published public private(set) var connectingHost: ConnectHost?
    @Published public private(set) var lastDisconnectedHost: ConnectHost?
    @Published public private(set) var lastDisconnectedModel: ConnectModel?
    @Published public private(set) var lastDisconnectReason: String?

    private let transport = ConnectTransport()
    // Stable for this SDK session so a network reconnect replaces the old
    // host-side connection instead of being counted as another device.
    private let clientInstanceID = UUID().uuidString
    private var activeSessionID: String?

    public init() {
        transport.onHostsChanged = { [weak self] hosts in
            DispatchQueue.main.async {
                self?.availableHosts = hosts
            }
        }
        transport.onHostClientCountChanged = { [weak self] count in
            DispatchQueue.main.async {
                self?.activeClientCount = count
            }
        }
        transport.onClientDisconnected = { [weak self] error in
            DispatchQueue.main.async {
                self?.handleClientDisconnect(error)
            }
        }
        transport.onFailure = { [weak self] error in
            DispatchQueue.main.async {
                self?.handleTransportFailure(error)
            }
        }
    }

    deinit {
        transport.stop()
    }

    /// Start browsing for Mac hosts over the local network.
    public func startBrowsing() async throws {
        try requireInitialized()
        #if os(iOS)
        lastError = nil
        transport.startBrowsing()
        if status != .connected {
            status = .discovering
        }
        #else
        throw unsupported("Only iPhone and iPad may browse for a Connect host in this release.")
        #endif
    }

    /// Stop local-network discovery without affecting an established session.
    public func stopBrowsing() {
        transport.stopBrowsing()
        if status == .discovering {
            status = .idle
        }
    }

    /// Publish this Mac together with the language model it has selected.
    ///
    /// A host cannot be started without a model. This avoids a connected
    /// client reaching a local-model picker after it has already joined a host.
    public func startHosting(
        displayName: String? = nil,
        model: ConnectModel,
        generationHandler: @escaping ConnectHostGenerationHandler
    ) async throws {
        try requireInitialized()
        #if os(macOS)
        lastError = nil
        var request = RAConnectHostStartRequest()
        request.displayName = sanitizedDisplayName(displayName ?? ProcessInfo.processInfo.hostName)
        request.platform = .macos
        request.protocolVersion = ConnectTransport.protocolVersion
        request.model = model.proto

        do {
            let hostState = try CppBridge.Connect.startHost(request)
            guard hostState.isHosting, hostState.hasDiscoveryMetadata, hostState.hasModel else {
                throw SDKException(
                    code: .processingFailed,
                    message: hostState.errorMessage.isEmpty
                        ? "Connect host could not be started"
                        : hostState.errorMessage,
                    category: .network
                )
            }
            try transport.startHosting(
                metadata: hostState.discoveryMetadata,
                generationHandler: generationHandler
            )
            activeModel = ConnectModel(hostState.model)
            activeClientCount = Int(hostState.activeClientCount)
            status = .hosting
        } catch {
            _ = try? CppBridge.Connect.stopHost()
            activeModel = nil
            lastError = error.localizedDescription
            status = .failed(error.localizedDescription)
            throw error
        }
        #else
        throw unsupported("Only macOS may host in this release.")
        #endif
    }

    /// Stop publishing this Mac and disconnect all attached clients.
    public func stopHosting() {
        transport.stopHosting()
        _ = try? CppBridge.Connect.stopHost()
        activeModel = nil
        activeClientCount = 0
        if status == .hosting {
            status = .idle
        }
    }

    /// Pair the current iPhone or iPad with a discovered Mac host.
    public func connect(to host: ConnectHost) async throws {
        try requireInitialized()
        #if os(iOS)
        lastError = nil
        connectingHost = host
        status = .connecting

        var request = RAConnectClientStartRequest()
        request.displayName = sanitizedDisplayName(UIDevice.current.name)
        request.platform = UIDevice.current.userInterfaceIdiom == .pad ? .ipados : .ios
        request.protocolVersion = ConnectTransport.protocolVersion

        do {
            var hello = try CppBridge.Connect.createClientHello(request)
            hello.instanceID = clientInstanceID
            let response = try await transport.connect(to: host, hello: hello)
            let sessionState = try CppBridge.Connect.validateHost(response)
            guard sessionState.state == .connected,
                  !sessionState.sessionID.isEmpty,
                  sessionState.hasModel,
                  !sessionState.model.modelID.isEmpty else {
                transport.disconnectClient()
                throw SDKException(
                    code: .networkUnavailable,
                    message: sessionState.errorMessage.isEmpty
                        ? "The selected Mac could not provide a language model"
                        : sessionState.errorMessage,
                    category: .network
                )
            }

            activeHost = ConnectHost(
                id: host.id,
                displayName: sessionState.host.displayName,
                protocolVersion: sessionState.host.protocolVersion
            )
            activeModel = ConnectModel(sessionState.model)
            activeSessionID = sessionState.sessionID
            connectingHost = nil
            lastDisconnectedHost = nil
            lastDisconnectedModel = nil
            lastDisconnectReason = nil
            status = .connected
            transport.startClientHeartbeat(sessionID: sessionState.sessionID)
        } catch {
            clearClientState()
            connectingHost = nil
            status = .failed(error.localizedDescription)
            lastError = error.localizedDescription
            throw error
        }
        #else
        throw unsupported("Only iPhone and iPad may connect to a Connect host in this release.")
        #endif
    }

    /// Run a text-generation request on the active Mac host.
    ///
    /// The session binds every invocation to the model selected by the host;
    /// callers cannot substitute a local or arbitrary remote model identifier.
    public func generateStream(
        _ request: RALLMGenerateRequest
    ) async throws -> AsyncStream<RALLMStreamEvent> {
        #if os(iOS)
        guard status == .connected,
              let activeModel,
              let activeSessionID,
              !activeSessionID.isEmpty else {
            throw SDKException(
                code: .networkUnavailable,
                message: "Connect to a Mac with a selected model before generating text.",
                category: .network
            )
        }

        var invocation = RAConnectInvocationRequest()
        invocation.sessionID = activeSessionID
        invocation.requestID = request.requestID.isEmpty ? UUID().uuidString : request.requestID
        var generation = request
        generation.requestID = invocation.requestID
        generation.modelID = activeModel.id
        invocation.generation = generation
        return try await transport.invoke(invocation)
        #else
        throw unsupported("Only iPhone and iPad may generate through a Connect host in this release.")
        #endif
    }

    /// End the active client connection, if any.
    public func disconnect() {
        transport.disconnectClient()
        clearClientState()
        clearDisconnectContext()
        switch status {
        case .connected, .connecting, .disconnected, .failed:
            status = .idle
        default:
            break
        }
    }

    /// Release all local-network resources owned by this session.
    public func stop() {
        transport.stop()
        _ = try? CppBridge.Connect.stopHost()
        availableHosts = []
        clearClientState()
        clearDisconnectContext()
        activeModel = nil
        activeClientCount = 0
        status = .idle
    }

    private func clearClientState() {
        activeHost = nil
        activeModel = status == .hosting ? activeModel : nil
        activeSessionID = nil
    }

    private func clearDisconnectContext() {
        connectingHost = nil
        lastDisconnectedHost = nil
        lastDisconnectedModel = nil
        lastDisconnectReason = nil
    }

    private func handleClientDisconnect(_ error: Error) {
        guard status == .connected else { return }

        let host = activeHost
        let model = activeModel
        let reason = disconnectMessage(for: error, host: host)

        clearClientState()
        connectingHost = nil
        lastDisconnectedHost = host
        lastDisconnectedModel = model
        lastDisconnectReason = reason
        lastError = reason
        status = .disconnected(reason)
    }

    private func disconnectMessage(for error: Error, host: ConnectHost?) -> String {
        let hostName = host?.displayName ?? "the Mac"
        let detail = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let genericReasons = [
            "The connection to the Mac ended.",
            "The connection to the Mac was closed.",
            "The Connect request was cancelled."
        ]

        if detail.isEmpty || genericReasons.contains(detail) {
            return "Connection to \(hostName) ended. The Mac may have stopped hosting or left the network."
        }
        return "Connection to \(hostName) ended: \(detail)"
    }

    private func handleTransportFailure(_ error: Error) {
        if status == .connected {
            transport.disconnectClient()
            handleClientDisconnect(error)
            return
        }
        if case .disconnected = status {
            return
        }

        let message = error.localizedDescription
        lastError = message
        if status == .hosting {
            _ = try? CppBridge.Connect.stopHost()
            activeModel = nil
            activeClientCount = 0
        } else {
            clearClientState()
            connectingHost = nil
        }
        status = .failed(message)
    }

    private func requireInitialized() throws {
        guard RunAnywhere.isInitialized else {
            throw SDKException(
                code: .notInitialized,
                message: "Initialize the SDK before starting a Connect session",
                category: .internal
            )
        }
    }

    private func unsupported(_ message: String) -> SDKException {
        SDKException(code: .notSupported, message: message, category: .network)
    }

    private func sanitizedDisplayName(_ candidate: String) -> String {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(128)).isEmpty ? "RunAnywhere device" : String(trimmed.prefix(128))
    }
}

private enum ConnectTransportError: LocalizedError {
    case hostUnavailable
    case malformedFrame
    case frameTooLarge
    case invocationInProgress
    case network(String)

    var errorDescription: String? {
        switch self {
        case .hostUnavailable:
            return "The selected Mac is no longer available on the local network."
        case .malformedFrame:
            return "The Connect session returned an invalid response."
        case .frameTooLarge:
            return "The Connect session exceeded the allowed message size."
        case .invocationInProgress:
            return "Wait for the current response to finish before sending another message."
        case let .network(message):
            return message
        }
    }
}

/// Serial-queue-confined Network.framework adapter.
private final class ConnectTransport: @unchecked Sendable {
    static let serviceType = "_runanywhere-connect._tcp"
    static let protocolVersion: UInt32 = 1
    private static let maximumFrameLength = 4 * 1024 * 1024
    private static let heartbeatInterval: DispatchTimeInterval = .seconds(3)
    private static let heartbeatTimeout: DispatchTimeInterval = .seconds(2)

    var onHostsChanged: (([ConnectHost]) -> Void)?
    var onHostClientCountChanged: ((Int) -> Void)?
    var onClientDisconnected: ((Error) -> Void)?
    var onFailure: ((Error) -> Void)?

    private let queue = DispatchQueue(label: "ai.runanywhere.connect.transport")
    private var browser: NWBrowser?
    private var listener: NWListener?
    private var discoveredEndpoints: [String: NWEndpoint] = [:]
    private var hostedConnections: [ObjectIdentifier: HostedConnection] = [:]
    private var hostGenerationHandler: ConnectHostGenerationHandler?
    private var clientConnection: NWConnection?
    private var activeClientRequestID: String?
    private var clientEventContinuation: AsyncStream<RALLMStreamEvent>.Continuation?
    private var clientHeartbeatTimer: DispatchSourceTimer?
    private var clientHeartbeatTimeout: DispatchWorkItem?
    private var activeClientSessionID: String?
    private var clientHeartbeatSequence: UInt64 = 0
    private var clientHeartbeatInFlight = false
    private var pendingClientInvocation: PendingClientInvocation?

    func startBrowsing() {
        queue.async { [weak self] in
            guard let self, self.browser == nil else { return }

            let browser = NWBrowser(
                for: .bonjour(type: Self.serviceType, domain: nil),
                using: .tcp
            )
            browser.stateUpdateHandler = { [weak self] state in
                guard let self, case let .failed(error) = state else { return }
                self.onFailure?(ConnectTransportError.network(error.localizedDescription))
            }
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                self?.updateDiscoveredHosts(results)
            }
            self.browser = browser
            browser.start(queue: self.queue)
        }
    }

    func stopBrowsing() {
        queue.async { [weak self] in
            guard let self else { return }
            self.browser?.cancel()
            self.browser = nil
            self.discoveredEndpoints = [:]
            self.onHostsChanged?([])
        }
    }

    func startHosting(
        metadata: RAConnectDiscoveryMetadata,
        generationHandler: @escaping ConnectHostGenerationHandler
    ) throws {
        try queue.sync { [weak self] in
            guard let self, self.listener == nil else { return }

            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(
                name: metadata.displayName,
                type: Self.serviceType
            )
            listener.stateUpdateHandler = { [weak self] state in
                guard let self, case let .failed(error) = state else { return }
                self.listener?.cancel()
                self.listener = nil
                self.onFailure?(ConnectTransportError.network(error.localizedDescription))
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            self.hostGenerationHandler = generationHandler
            self.listener = listener
            listener.start(queue: self.queue)
        }
    }

    func stopHosting() {
        queue.async { [weak self] in
            guard let self else { return }
            self.listener?.cancel()
            self.listener = nil
            self.hostGenerationHandler = nil
            let connections = self.hostedConnections.values
            self.hostedConnections = [:]
            connections.forEach { $0.connection.cancel() }
            self.onHostClientCountChanged?(0)
        }
    }

    func connect(
        to host: ConnectHost,
        hello: RAConnectClientHello
    ) async throws -> RAConnectHandshakeResponse {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self,
                      let endpoint = self.discoveredEndpoints[host.id] else {
                    continuation.resume(throwing: ConnectTransportError.hostUnavailable)
                    return
                }

                self.clearClientConnection(notify: false)
                let connection = NWConnection(to: endpoint, using: .tcp)
                let attempt = ClientAttempt(continuation: continuation)
                connection.stateUpdateHandler = { [weak self, weak connection] state in
                    guard let self, let connection else { return }
                    self.handleClientState(state, connection: connection, hello: hello, attempt: attempt)
                }
                self.clientConnection = connection
                connection.start(queue: self.queue)
            }
        }
    }

    func invoke(_ invocation: RAConnectInvocationRequest) async throws -> AsyncStream<RALLMStreamEvent> {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: ConnectTransportError.hostUnavailable)
                    return
                }
                self.beginClientInvocation(invocation, continuation: continuation)
            }
        }
    }

    /// Keeps an idle client connection observable. NWConnection alone only
    /// reports a remote close when it has pending I/O, so a lightweight typed
    /// request/response makes a stopped Mac visible without waiting for the
    /// user to send another prompt.
    func startClientHeartbeat(sessionID: String) {
        queue.async { [weak self] in
            guard let self, self.clientConnection != nil else { return }
            self.stopClientHeartbeat()
            self.activeClientSessionID = sessionID

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(
                deadline: .now() + Self.heartbeatInterval,
                repeating: Self.heartbeatInterval,
                leeway: .milliseconds(250)
            )
            timer.setEventHandler { [weak self] in
                self?.sendClientHeartbeatIfIdle()
            }
            self.clientHeartbeatTimer = timer
            timer.resume()
        }
    }

    private func beginClientInvocation(
        _ invocation: RAConnectInvocationRequest,
        continuation: CheckedContinuation<AsyncStream<RALLMStreamEvent>, Error>
    ) {
        guard let connection = clientConnection else {
            continuation.resume(throwing: ConnectTransportError.hostUnavailable)
            return
        }
        guard activeClientRequestID == nil else {
            continuation.resume(throwing: ConnectTransportError.invocationInProgress)
            return
        }
        guard !clientHeartbeatInFlight else {
            // A heartbeat owns the one outstanding receive on this TCP
            // connection. Queue the user's turn for the few milliseconds
            // until it completes instead of surfacing a spurious failure.
            guard pendingClientInvocation == nil else {
                continuation.resume(throwing: ConnectTransportError.invocationInProgress)
                return
            }
            pendingClientInvocation = PendingClientInvocation(
                invocation: invocation,
                continuation: continuation
            )
            return
        }

        let requestID = invocation.requestID
        var streamContinuation: AsyncStream<RALLMStreamEvent>.Continuation?
        let stream = AsyncStream<RALLMStreamEvent> { streamContinuation = $0 }
        guard let streamContinuation else {
            continuation.resume(throwing: ConnectTransportError.malformedFrame)
            return
        }

        activeClientRequestID = requestID
        clientEventContinuation = streamContinuation
        streamContinuation.onTermination = { [weak self] _ in
            self?.queue.async {
                guard self?.activeClientRequestID == requestID else { return }
                self?.finishClientInvocation()
            }
        }

        do {
            var frame = RAConnectClientFrame()
            frame.invocation = invocation
            try sendFrame(try frame.serializedData(), on: connection) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    self.receiveClientInvocationEvent(on: connection, requestID: requestID)
                case let .failure(error):
                    self.finishClientInvocation(with: error)
                    self.clearClientConnection(connection, notify: true, reason: error)
                }
            }
            continuation.resume(returning: stream)
        } catch {
            finishClientInvocation(with: error)
            clearClientConnection(connection, notify: true, reason: error)
            continuation.resume(throwing: error)
        }
    }

    private func sendClientHeartbeatIfIdle() {
        guard let connection = clientConnection,
              let sessionID = activeClientSessionID,
              activeClientRequestID == nil,
              !clientHeartbeatInFlight else {
            return
        }

        clientHeartbeatSequence &+= 1
        let sequence = clientHeartbeatSequence
        clientHeartbeatInFlight = true

        var heartbeat = RAConnectHeartbeatRequest()
        heartbeat.sessionID = sessionID
        heartbeat.sequence = sequence
        var frame = RAConnectClientFrame()
        frame.heartbeat = heartbeat

        let timeout = DispatchWorkItem { [weak self, weak connection] in
            guard let self,
                  let connection,
                  self.clientConnection === connection,
                  self.clientHeartbeatInFlight,
                  self.clientHeartbeatSequence == sequence else {
                return
            }
            self.clearClientConnection(
                connection,
                notify: true,
                reason: ConnectTransportError.network(
                    "The Mac stopped responding. It may have stopped hosting or left the network."
                )
            )
        }
        clientHeartbeatTimeout = timeout
        queue.asyncAfter(deadline: .now() + Self.heartbeatTimeout, execute: timeout)

        do {
            try sendFrame(try frame.serializedData(), on: connection) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    self.receiveClientHeartbeat(
                        on: connection,
                        sessionID: sessionID,
                        sequence: sequence
                    )
                case let .failure(error):
                    self.clearClientConnection(connection, notify: true, reason: error)
                }
            }
        } catch {
            clearClientConnection(connection, notify: true, reason: error)
        }
    }

    private func receiveClientHeartbeat(
        on connection: NWConnection,
        sessionID: String,
        sequence: UInt64
    ) {
        receiveFrame(on: connection) { [weak self] result in
            guard let self,
                  self.clientConnection === connection,
                  self.clientHeartbeatInFlight else {
                return
            }

            switch result {
            case let .success(data):
                do {
                    let frame = try RAConnectHostFrame(serializedBytes: data)
                    guard case let .heartbeat(response)? = frame.payload,
                          response.sessionID == sessionID,
                          response.sequence == sequence else {
                        throw ConnectTransportError.malformedFrame
                    }
                    self.finishClientHeartbeat()
                } catch {
                    self.clearClientConnection(connection, notify: true, reason: error)
                }
            case let .failure(error):
                self.clearClientConnection(connection, notify: true, reason: error)
            }
        }
    }

    private func finishClientHeartbeat() {
        clientHeartbeatTimeout?.cancel()
        clientHeartbeatTimeout = nil
        clientHeartbeatInFlight = false

        guard let pending = pendingClientInvocation else { return }
        pendingClientInvocation = nil
        beginClientInvocation(pending.invocation, continuation: pending.continuation)
    }

    private func stopClientHeartbeat() {
        clientHeartbeatTimer?.cancel()
        clientHeartbeatTimer = nil
        clientHeartbeatTimeout?.cancel()
        clientHeartbeatTimeout = nil
        activeClientSessionID = nil
        clientHeartbeatInFlight = false
    }

    func disconnectClient() {
        queue.async { [weak self] in
            self?.clearClientConnection(notify: false)
        }
    }

    func stop() {
        stopBrowsing()
        stopHosting()
        disconnectClient()
    }

    private func updateDiscoveredHosts(_ results: Set<NWBrowser.Result>) {
        var endpoints: [String: NWEndpoint] = [:]
        let hosts = results.compactMap { result -> ConnectHost? in
            guard case let .service(name, _, domain, _) = result.endpoint else { return nil }
            let id = "\(name)@\(domain)"
            endpoints[id] = result.endpoint
            return ConnectHost(
                id: id,
                displayName: name,
                protocolVersion: Self.protocolVersion
            )
        }
        discoveredEndpoints = endpoints
        onHostsChanged?(hosts.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        })
    }

    private func accept(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .failed, .cancelled:
                self.removeHostedConnection(for: connection)
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveFrame(on: connection) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(data):
                do {
                    let hello = try RAConnectClientHello(serializedBytes: data)

                    // The commons layer invalidates the previous session for
                    // this client identity. Mirror that replacement in the
                    // platform transport so the live UI count stays accurate.
                    let staleConnections = self.hostedConnections.values.filter {
                        $0.clientInstanceID == hello.instanceID
                    }
                    staleConnections.forEach {
                        self.removeHostedConnection(for: $0.connection)
                        $0.connection.cancel()
                    }

                    let response = try CppBridge.Connect.acceptClient(hello)

                    guard response.status == .accepted, !response.sessionID.isEmpty else {
                        try self.sendFrame(try response.serializedData(), on: connection) { _ in
                            connection.cancel()
                        }
                        return
                    }

                    let hosted = HostedConnection(
                        connection: connection,
                        sessionID: response.sessionID,
                        clientInstanceID: hello.instanceID
                    )
                    self.hostedConnections[key] = hosted
                    try self.sendFrame(try response.serializedData(), on: connection) { [weak self] sendResult in
                        guard let self else { return }
                        guard case .success = sendResult else {
                            self.removeHostedConnection(for: connection)
                            connection.cancel()
                            return
                        }
                        self.onHostClientCountChanged?(self.hostedConnections.count)
                        self.receiveHostFrame(on: hosted)
                    }
                } catch {
                    self.onFailure?(error)
                    connection.cancel()
                }
            case .failure:
                connection.cancel()
            }
        }
    }

    private func receiveHostFrame(on hosted: HostedConnection) {
        receiveFrame(on: hosted.connection) { [weak self, weak hosted] result in
            guard let self, let hosted else { return }
            switch result {
            case let .success(data):
                do {
                    let frame = try RAConnectClientFrame(serializedBytes: data)
                    guard let payload = frame.payload else {
                        throw ConnectTransportError.malformedFrame
                    }
                    switch payload {
                    case let .invocation(invocation):
                        self.handleHostInvocation(invocation, on: hosted)
                    case let .heartbeat(heartbeat):
                        self.respondToHeartbeat(heartbeat, on: hosted)
                    }
                } catch {
                    hosted.connection.cancel()
                }
            case .failure:
                hosted.connection.cancel()
            }
        }
    }

    private func handleHostInvocation(_ invocation: RAConnectInvocationRequest, on hosted: HostedConnection) {
        do {
            let validation = try CppBridge.Connect.validateInvocation(invocation)
            guard validation.accepted, invocation.sessionID == hosted.sessionID else {
                sendHostTerminalError(
                    validation.rejectionReason.isEmpty
                        ? "The Mac rejected this generation request."
                        : validation.rejectionReason,
                    requestID: invocation.requestID,
                    on: hosted
                )
                return
            }
            guard let handler = hostGenerationHandler else {
                sendHostTerminalError(
                    "This Mac is not ready to run the selected model.",
                    requestID: invocation.requestID,
                    on: hosted
                )
                return
            }
            forwardHostGeneration(
                invocation.generation,
                requestID: invocation.requestID,
                handler: handler,
                on: hosted
            )
        } catch {
            sendHostTerminalError(
                error.localizedDescription,
                requestID: invocation.requestID,
                on: hosted
            )
        }
    }

    private func respondToHeartbeat(_ heartbeat: RAConnectHeartbeatRequest, on hosted: HostedConnection) {
        guard heartbeat.sessionID == hosted.sessionID else {
            hosted.connection.cancel()
            return
        }

        var response = RAConnectHeartbeatResponse()
        response.sessionID = hosted.sessionID
        response.sequence = heartbeat.sequence
        var frame = RAConnectHostFrame()
        frame.heartbeat = response

        do {
            try sendFrame(try frame.serializedData(), on: hosted.connection) { [weak self, weak hosted] result in
                guard let self, let hosted else { return }
                switch result {
                case .success:
                    self.receiveHostFrame(on: hosted)
                case .failure:
                    hosted.connection.cancel()
                }
            }
        } catch {
            hosted.connection.cancel()
        }
    }

    private func forwardHostGeneration(
        _ request: RALLMGenerateRequest,
        requestID: String,
        handler: @escaping ConnectHostGenerationHandler,
        on hosted: HostedConnection
    ) {
        Task { [weak self, weak hosted] in
            guard let self, let hosted else { return }
            do {
                let events = try await handler(request)
                var receivedTerminalEvent = false
                for await event in events {
                    var envelope = RAConnectInvocationEvent()
                    envelope.requestID = requestID
                    envelope.event = event
                    var frame = RAConnectHostFrame()
                    frame.invocationEvent = envelope
                    try await self.sendFrameAsync(try frame.serializedData(), on: hosted.connection)
                    if event.isFinal {
                        receivedTerminalEvent = true
                        break
                    }
                }
                if !receivedTerminalEvent {
                    try await self.sendTerminalErrorFrame(
                        "The Mac ended generation without a final result.",
                        requestID: requestID,
                        on: hosted.connection
                    )
                }
            } catch {
                try? await self.sendTerminalErrorFrame(
                    error.localizedDescription,
                    requestID: requestID,
                    on: hosted.connection
                )
            }
            self.queue.async { [weak self, weak hosted] in
                guard let self, let hosted else { return }
                self.receiveHostFrame(on: hosted)
            }
        }
    }

    private func sendHostTerminalError(
        _ message: String,
        requestID: String,
        on hosted: HostedConnection
    ) {
        Task { [weak self, weak hosted] in
            guard let self, let hosted else { return }
            try? await self.sendTerminalErrorFrame(message, requestID: requestID, on: hosted.connection)
            self.queue.async { [weak self, weak hosted] in
                guard let self, let hosted else { return }
                self.receiveHostFrame(on: hosted)
            }
        }
    }

    private func sendTerminalErrorFrame(
        _ message: String,
        requestID: String,
        on connection: NWConnection
    ) async throws {
        var event = RALLMStreamEvent()
        event.requestID = requestID
        event.isFinal = true
        event.finishReason = "error"
        event.errorMessage = message
        event.eventKind = .error

        var envelope = RAConnectInvocationEvent()
        envelope.requestID = requestID
        envelope.event = event
        var frame = RAConnectHostFrame()
        frame.invocationEvent = envelope
        try await sendFrameAsync(try frame.serializedData(), on: connection)
    }

    private func receiveClientInvocationEvent(on connection: NWConnection, requestID: String) {
        receiveFrame(on: connection) { [weak self] result in
            guard let self, self.clientConnection === connection,
                  self.activeClientRequestID == requestID else { return }
            switch result {
            case let .success(data):
                do {
                    let frame = try RAConnectHostFrame(serializedBytes: data)
                    guard case let .invocationEvent(envelope)? = frame.payload,
                          envelope.requestID == requestID,
                          envelope.hasEvent else {
                        throw ConnectTransportError.malformedFrame
                    }
                    self.clientEventContinuation?.yield(envelope.event)
                    if envelope.event.isFinal {
                        self.finishClientInvocation()
                    } else {
                        self.receiveClientInvocationEvent(on: connection, requestID: requestID)
                    }
                } catch {
                    self.finishClientInvocation(with: error)
                    self.clearClientConnection(connection, notify: true, reason: error)
                }
            case let .failure(error):
                self.finishClientInvocation(with: error)
                self.clearClientConnection(connection, notify: true, reason: error)
            }
        }
    }

    private func removeHostedConnection(for connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        guard let hosted = hostedConnections.removeValue(forKey: key) else { return }
        var request = RAConnectSessionCloseRequest()
        request.sessionID = hosted.sessionID
        _ = try? CppBridge.Connect.closeSession(request)
        onHostClientCountChanged?(hostedConnections.count)
    }

    private func handleClientState(
        _ state: NWConnection.State,
        connection: NWConnection,
        hello: RAConnectClientHello,
        attempt: ClientAttempt
    ) {
        switch state {
        case .ready:
            guard !attempt.didStartHandshake else { return }
            attempt.didStartHandshake = true
            do {
                try sendFrame(try hello.serializedData(), on: connection) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success:
                        self.receiveFrame(on: connection) { result in
                            switch result {
                            case let .success(data):
                                do {
                                    attempt.finish(.success(try RAConnectHandshakeResponse(serializedBytes: data)))
                                } catch {
                                    attempt.finish(.failure(error))
                                    connection.cancel()
                                }
                            case let .failure(error):
                                attempt.finish(.failure(error))
                                connection.cancel()
                            }
                        }
                    case let .failure(error):
                        attempt.finish(.failure(error))
                        connection.cancel()
                    }
                }
            } catch {
                attempt.finish(.failure(error))
                connection.cancel()
            }
        case let .failed(error):
            let reason = ConnectTransportError.network(error.localizedDescription)
            attempt.finish(.failure(reason))
            clearClientConnection(connection, notify: true, reason: reason)
        case .cancelled:
            let reason = ConnectTransportError.network("The connection to the Mac was closed.")
            if !attempt.didFinish {
                attempt.finish(.failure(reason))
            }
            clearClientConnection(connection, notify: true, reason: reason)
        default:
            break
        }
    }

    private func clearClientConnection(
        _ expected: NWConnection? = nil,
        notify: Bool,
        reason: Error = ConnectTransportError.network("The connection to the Mac ended.")
    ) {
        guard expected == nil || expected === clientConnection else { return }
        let connection = clientConnection
        clientConnection = nil
        connection?.cancel()
        stopClientHeartbeat()
        finishPendingClientInvocation(with: reason)
        finishClientInvocation(
            with: reason,
            emitError: false
        )
        if notify, connection != nil {
            onClientDisconnected?(reason)
        }
    }

    private func finishPendingClientInvocation(with error: Error) {
        guard let pending = pendingClientInvocation else { return }
        pendingClientInvocation = nil
        pending.continuation.resume(throwing: error)
    }

    private func finishClientInvocation(
        with error: Error? = nil,
        emitError: Bool = true
    ) {
        guard let continuation = clientEventContinuation else { return }
        if let error, emitError {
            var event = RALLMStreamEvent()
            event.requestID = activeClientRequestID ?? ""
            event.isFinal = true
            event.finishReason = "error"
            event.errorMessage = error.localizedDescription
            event.eventKind = .error
            continuation.yield(event)
        }
        continuation.finish()
        activeClientRequestID = nil
        clientEventContinuation = nil
    }

    private func sendFrameAsync(_ payload: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: ConnectTransportError.hostUnavailable)
                    return
                }
                do {
                    try self.sendFrame(payload, on: connection) { result in
                        continuation.resume(with: result)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func sendFrame(
        _ payload: Data,
        on connection: NWConnection,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) throws {
        guard payload.count <= Self.maximumFrameLength else {
            throw ConnectTransportError.frameTooLarge
        }
        var length = UInt32(payload.count).bigEndian
        var frame = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        frame.append(payload)
        connection.send(content: frame, completion: .contentProcessed { error in
            if let error {
                completion(.failure(ConnectTransportError.network(error.localizedDescription)))
            } else {
                completion(.success(()))
            }
        })
    }

    private func receiveFrame(
        on connection: NWConnection,
        completion: @escaping @Sendable (Result<Data, Error>) -> Void
    ) {
        receiveExactly(4, on: connection) { [weak self] headerResult in
            guard let self else { return }
            switch headerResult {
            case let .success(header):
                let length = header.reduce(UInt32(0)) { partial, byte in
                    (partial << 8) | UInt32(byte)
                }
                guard length > 0, length <= Self.maximumFrameLength else {
                    completion(.failure(ConnectTransportError.frameTooLarge))
                    return
                }
                self.receiveExactly(Int(length), on: connection, completion: completion)
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    private func receiveExactly(
        _ length: Int,
        on connection: NWConnection,
        completion: @escaping @Sendable (Result<Data, Error>) -> Void
    ) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { data, _, _, error in
            if let error {
                completion(.failure(ConnectTransportError.network(error.localizedDescription)))
                return
            }
            guard let data, data.count == length else {
                completion(.failure(ConnectTransportError.malformedFrame))
                return
            }
            completion(.success(data))
        }
    }
}

/// Holds a Network.framework connection that is serialized by `ConnectTransport.queue`.
/// Generation tasks never mutate it directly; they only schedule framed sends back onto
/// that queue through `sendFrameAsync`.
private final class HostedConnection: @unchecked Sendable {
    let connection: NWConnection
    let sessionID: String
    let clientInstanceID: String

    init(connection: NWConnection, sessionID: String, clientInstanceID: String) {
        self.connection = connection
        self.sessionID = sessionID
        self.clientInstanceID = clientInstanceID
    }
}

/// A user turn that arrived while the control-plane heartbeat owned the
/// connection's receive callback. Connect permits one generation at a time,
/// so a single queued turn preserves that invariant without dropping input.
private final class PendingClientInvocation {
    let invocation: RAConnectInvocationRequest
    let continuation: CheckedContinuation<AsyncStream<RALLMStreamEvent>, Error>

    init(
        invocation: RAConnectInvocationRequest,
        continuation: CheckedContinuation<AsyncStream<RALLMStreamEvent>, Error>
    ) {
        self.invocation = invocation
        self.continuation = continuation
    }
}

private final class ClientAttempt: @unchecked Sendable {
    let continuation: CheckedContinuation<RAConnectHandshakeResponse, Error>
    var didStartHandshake = false
    var didFinish = false

    init(continuation: CheckedContinuation<RAConnectHandshakeResponse, Error>) {
        self.continuation = continuation
    }

    func finish(_ result: Result<RAConnectHandshakeResponse, Error>) {
        guard !didFinish else { return }
        didFinish = true
        continuation.resume(with: result)
    }
}
