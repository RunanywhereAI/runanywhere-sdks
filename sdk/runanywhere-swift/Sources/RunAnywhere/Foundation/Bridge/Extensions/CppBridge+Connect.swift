//
//  CppBridge+Connect.swift
//  RunAnywhere SDK
//
//  Native protocol bridge for local runtime session coordination.
//

import CRACommons
import Foundation
import SwiftProtobuf

private enum ConnectProtoABI {
    static let platformPolicy = NativeProtoABI.load(
        "rac_connect_get_platform_policy_proto",
        as: NativeProtoABI.ProtoRequest.self
    )
    static let hostStart = NativeProtoABI.load(
        "rac_connect_host_start_proto",
        as: NativeProtoABI.ProtoRequest.self
    )
    static let hostStop = NativeProtoABI.load(
        "rac_connect_host_stop_proto",
        as: NativeProtoABI.ProtoRequest.self
    )
    static let clientCreateHello = NativeProtoABI.load(
        "rac_connect_client_create_hello_proto",
        as: NativeProtoABI.ProtoRequest.self
    )
    static let hostAcceptClient = NativeProtoABI.load(
        "rac_connect_host_accept_client_proto",
        as: NativeProtoABI.ProtoRequest.self
    )
    static let clientValidateHost = NativeProtoABI.load(
        "rac_connect_client_validate_host_proto",
        as: NativeProtoABI.ProtoRequest.self
    )
    static let hostCloseSession = NativeProtoABI.load(
        "rac_connect_host_close_session_proto",
        as: NativeProtoABI.ProtoRequest.self
    )
    static let hostValidateInvocation = NativeProtoABI.load(
        "rac_connect_host_validate_invocation_proto",
        as: NativeProtoABI.ProtoRequest.self
    )
}

extension CppBridge {

    /// Typed C++ coordination for local runtime hosts and clients.
    /// Platform SDKs provide discovery and channel transport adapters.
    public enum Connect {

        static func platformPolicy(
            _ request: RAConnectPlatformPolicyRequest
        ) throws -> RAConnectPlatformPolicy {
            try NativeProtoABI.invoke(
                request,
                symbol: ConnectProtoABI.platformPolicy,
                symbolName: "rac_connect_get_platform_policy_proto",
                responseType: RAConnectPlatformPolicy.self
            )
        }

        static func startHost(_ request: RAConnectHostStartRequest) throws -> RAConnectHostState {
            try NativeProtoABI.invoke(
                request,
                symbol: ConnectProtoABI.hostStart,
                symbolName: "rac_connect_host_start_proto",
                responseType: RAConnectHostState.self
            )
        }

        static func stopHost(_ request: RAConnectHostStopRequest = .init()) throws -> RAConnectHostState {
            try NativeProtoABI.invoke(
                request,
                symbol: ConnectProtoABI.hostStop,
                symbolName: "rac_connect_host_stop_proto",
                responseType: RAConnectHostState.self
            )
        }

        static func createClientHello(
            _ request: RAConnectClientStartRequest
        ) throws -> RAConnectClientHello {
            try NativeProtoABI.invoke(
                request,
                symbol: ConnectProtoABI.clientCreateHello,
                symbolName: "rac_connect_client_create_hello_proto",
                responseType: RAConnectClientHello.self
            )
        }

        static func acceptClient(_ hello: RAConnectClientHello) throws -> RAConnectHandshakeResponse {
            try NativeProtoABI.invoke(
                hello,
                symbol: ConnectProtoABI.hostAcceptClient,
                symbolName: "rac_connect_host_accept_client_proto",
                responseType: RAConnectHandshakeResponse.self
            )
        }

        static func validateHost(
            _ response: RAConnectHandshakeResponse
        ) throws -> RAConnectClientSessionState {
            try NativeProtoABI.invoke(
                response,
                symbol: ConnectProtoABI.clientValidateHost,
                symbolName: "rac_connect_client_validate_host_proto",
                responseType: RAConnectClientSessionState.self
            )
        }

        static func closeSession(
            _ request: RAConnectSessionCloseRequest
        ) throws -> RAConnectHostState {
            try NativeProtoABI.invoke(
                request,
                symbol: ConnectProtoABI.hostCloseSession,
                symbolName: "rac_connect_host_close_session_proto",
                responseType: RAConnectHostState.self
            )
        }

        static func validateInvocation(
            _ request: RAConnectInvocationRequest
        ) throws -> RAConnectInvocationValidation {
            try NativeProtoABI.invoke(
                request,
                symbol: ConnectProtoABI.hostValidateInvocation,
                symbolName: "rac_connect_host_validate_invocation_proto",
                responseType: RAConnectInvocationValidation.self
            )
        }
    }
}
