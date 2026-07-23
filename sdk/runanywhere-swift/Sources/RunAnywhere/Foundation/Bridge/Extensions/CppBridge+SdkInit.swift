//
//  CppBridge+SdkInit.swift
//  RunAnywhere SDK
//
//  Two-phase SDK init bridge — wraps the canonical C ABI surface in
//  rac_sdk_init.h. All step-list orchestration that used to live in
//  RunAnywhere.swift is owned by commons; this file is the data envelope.
//
//  Maps Swift parameters into RASdkInitPhase{1,2}Request, invokes
//  rac_sdk_init_phase{1,2}_proto / rac_sdk_retry_http_proto, and returns the
//  serialized RASdkInitResult so the public façade can react to outcome flags.
//

import CRACommons

extension CppBridge {

    /// Two-phase SDK init bridge.
    public enum SdkInit {

        // MARK: - Symbol bindings (lazy-loaded from RACommons)

        private static let phase1Symbol = NativeProtoABI.load(
            "rac_sdk_init_phase1_proto",
            as: NativeProtoABI.ProtoRequest.self
        )

        private static let phase2Symbol = NativeProtoABI.load(
            "rac_sdk_init_phase2_proto",
            as: NativeProtoABI.ProtoRequest.self
        )

        private static let retryHTTPSymbol = NativeProtoABI.load(
            "rac_sdk_retry_http_proto",
            as: (@convention(c) (UnsafeMutablePointer<rac_proto_buffer_t>?) -> rac_result_t).self
        )

        // MARK: - Phase 1 (synchronous core init)

        /// Drive Phase 1 (synchronous core init) through the canonical C ABI.
        /// Validates inputs and runs `rac_state_initialize` inside commons.
        @discardableResult
        public static func phase1(
            environment: SDKEnvironment,
            apiKey: String,
            baseURL: String,
            deviceId: String
        ) throws -> RASdkInitResult {
            var request = RASdkInitPhase1Request()
            request.environment = mapEnvironment(environment)
            request.apiKey = apiKey
            request.baseURL = baseURL
            request.deviceID = deviceId
            request.platform = SDKConstants.platform
            request.sdkVersion = SDKConstants.version

            let result = try NativeProtoABI.invoke(
                request,
                symbol: phase1Symbol,
                symbolName: "rac_sdk_init_phase1_proto",
                responseType: RASdkInitResult.self
            )
            try assertSuccess(result)
            return result
        }

        // MARK: - Phase 2 (async services init step list owned by C++)

        /// Drive Phase 2 (services init step list) through the canonical C ABI.
        /// Surfaces `http_configured`, `device_registered`, `linked_models_count`
        /// and warning flags so the caller can decide which UI affordances to
        /// enable. Failures in individual sub-steps are non-fatal — the C ABI
        /// reports `success=true` with flags off.
        @discardableResult
        public static func phase2(
            buildToken: String? = nil,
            forceRefreshAssignments: Bool = false,
            flushTelemetry: Bool = true,
            discoverDownloadedModels: Bool = true,
            rescanLocalModels: Bool = true
        ) throws -> RASdkInitResult {
            var request = RASdkInitPhase2Request()
            request.buildToken = buildToken ?? ""
            request.forceRefreshAssignments = forceRefreshAssignments
            request.flushTelemetry = flushTelemetry
            request.discoverDownloadedModels = discoverDownloadedModels
            request.rescanLocalModels = rescanLocalModels

            let result = try NativeProtoABI.invoke(
                request,
                symbol: phase2Symbol,
                symbolName: "rac_sdk_init_phase2_proto",
                responseType: RASdkInitResult.self
            )
            try assertSuccess(result)
            return result
        }

        // MARK: - HTTP retry

        /// Re-attempt HTTP/auth setup after an offline initialization. Mirrors
        /// `rac_sdk_retry_http_proto` semantics: idempotent fast path when
        /// already authenticated, surfaces a warning when no usable external
        /// config is available.
        @discardableResult
        public static func retryHTTP() throws -> RASdkInitResult {
            let symbol = try NativeProtoABI.require(retryHTTPSymbol, named: "rac_sdk_retry_http_proto")
            var outBuffer = rac_proto_buffer_t()
            defer { NativeProtoABI.free(&outBuffer) }
            let status = symbol(&outBuffer)
            guard status == RAC_SUCCESS else {
                let message = outBuffer.error_message.map { String(cString: $0) }
                    ?? "rac_sdk_retry_http_proto failed: rc=\(status)"
                throw SDKException(code: .processingFailed, message: message, category: .internal)
            }
            let result = try NativeProtoABI.decode(RASdkInitResult.self, from: outBuffer)
            try assertSuccess(result)
            return result
        }

        // MARK: - Helpers

        private static func mapEnvironment(_ env: SDKEnvironment) -> RASdkInitEnvironment {
            switch env {
            case .development: return .development
            case .production:  return .production
            default:           return .development
            }
        }

        /// Throw the embedded RASDKError when the C ABI signals a hard failure
        /// (validation/parse/state init). Soft failures (offline mode) come
        /// back with `success=true` plus warnings — the caller decides how to
        /// react to those.
        private static func assertSuccess(_ result: RASdkInitResult) throws {
            guard !result.success else { return }
            if result.hasError {
                throw SDKException(proto: result.error)
            }
            throw SDKException(
                code: .processingFailed,
                message: "SDK init phase \(result.phase) failed without error detail",
                category: .internal
            )
        }
    }
}
