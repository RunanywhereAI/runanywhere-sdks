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

        // MARK: - Symbol bindings

        // Keep a typed reference to each canonical SDK-init entry point. The
        // Apple distribution links RACommons as a static archive; a dlsym-only
        // reference does not pull an otherwise-unreferenced archive member into
        // the final app, so the symbol can be dead-stripped even though it is
        // present in the XCFramework. The direct fallback is both a link-time
        // anchor and a valid invocation path when RTLD_DEFAULT cannot enumerate
        // main-executable symbols.

        private static let phase1Symbol: NativeProtoABI.ProtoRequest? = {
            let linked: NativeProtoABI.ProtoRequest = rac_sdk_init_phase1_proto
            return NativeProtoABI.load(
                "rac_sdk_init_phase1_proto",
                as: NativeProtoABI.ProtoRequest.self
            ) ?? linked
        }()

        private static let phase2Symbol: NativeProtoABI.ProtoRequest? = {
            let linked: NativeProtoABI.ProtoRequest = rac_sdk_init_phase2_proto
            return NativeProtoABI.load(
                "rac_sdk_init_phase2_proto",
                as: NativeProtoABI.ProtoRequest.self
            ) ?? linked
        }()

        private static let retryHTTPSymbol: (@convention(c) (
            UnsafeMutablePointer<rac_proto_buffer_t>?
        ) -> rac_result_t)? = {
            let linked: @convention(c) (
                UnsafeMutablePointer<rac_proto_buffer_t>?
            ) -> rac_result_t = rac_sdk_retry_http_proto
            return NativeProtoABI.load(
                "rac_sdk_retry_http_proto",
                as: (@convention(c) (
                    UnsafeMutablePointer<rac_proto_buffer_t>?
                ) -> rac_result_t).self
            ) ?? linked
        }()

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
        ///
        /// `forceRefreshAssignments`/`flushTelemetry`/`discoverDownloadedModels`/
        /// `rescanLocalModels` were deleted outright from
        /// `SdkInitPhase2Request` (idl/sdk_init.proto): the deterministic
        /// step list — fetch cached assignments, always flush telemetry,
        /// always reconcile the registry and rescan local files — now runs
        /// unconditionally in commons with no per-call opt-out. Surfaces
        /// `linked_models_count` and warning flags so the caller can decide
        /// which UI affordances to enable. Failures in individual sub-steps
        /// are non-fatal — the C ABI reports success with warnings appended.
        @discardableResult
        public static func phase2(buildToken: String? = nil) throws -> RASdkInitResult {
            var request = RASdkInitPhase2Request()
            request.buildToken = buildToken ?? ""

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

        // RASdkInitEnvironment was deleted outright (idl/sdk_init.proto):
        // SdkInitPhase1Request.environment is typed model_types.proto's
        // RASDKEnvironment directly (SDKEnvironment is already a typealias
        // for it), so this used to be a needless enum-to-enum bridge.
        private static func mapEnvironment(_ env: SDKEnvironment) -> RASDKEnvironment {
            switch env {
            case .development: return .development
            case .production:  return .production
            default:           return .development
            }
        }

        /// Throw the embedded RASDKError when the C ABI signals a hard failure
        /// (validation/parse/state init). Soft failures (offline mode) come
        /// back with no error submessage plus warnings — the caller decides how
        /// to react to those.
        private static func assertSuccess(_ result: RASdkInitResult) throws {
            if result.hasError {
                throw SDKException(proto: result.error)
            }
        }
    }
}
