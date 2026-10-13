//
//  CppBridge+OCR.swift
//  RunAnywhere SDK
//
//  Full-page OCR bridge over the canonical lifecycle proto ABI.
//

import CRACommons
import Foundation

private enum OCRLifecycleProtoABI {
    static let readPageName = "rac_ocr_read_page_lifecycle_proto"
    static let readPage: NativeProtoABI.ProtoRequest? = {
        // RACommons ships as a static archive on Apple platforms. Keep a typed
        // reference so the linker retains the OCR archive member even when
        // RTLD_DEFAULT cannot enumerate executable symbols.
        let linked: NativeProtoABI.ProtoRequest = rac_ocr_read_page_lifecycle_proto
        return NativeProtoABI.load(
            readPageName,
            as: NativeProtoABI.ProtoRequest.self
        ) ?? linked
    }()
}

extension CppBridge {
    /// Stateless OCR namespace.
    ///
    /// Commons owns the loaded model through the canonical model lifecycle;
    /// Swift does not create or retain a second service handle. This keeps
    /// unload/reset behavior identical across every SDK consumer.
    public enum OCR {
        /// Read one packed RGB8, RGBA8, or BGRA8 page with the
        /// lifecycle-loaded OCR model.
        public static func readPage(
            _ request: RAOCRRequest
        ) async throws -> RAOCRResult {
            try await Task.detached(priority: .userInitiated) {
                try NativeProtoABI.invoke(
                    request,
                    symbol: OCRLifecycleProtoABI.readPage,
                    symbolName: OCRLifecycleProtoABI.readPageName,
                    responseType: RAOCRResult.self
                )
            }.value
        }
    }
}
