//
//  RunAnywhere+OCR.swift
//  RunAnywhere SDK
//
//  Readiness gate for `RunAnywhere.ocr`, kept separate from native dispatch so
//  focused tests can prove the no-model contract without mutating
//  process-global SDK initialization state.
//

public extension RunAnywhere {

    internal static func requireOCRModel(
        _ snapshot: RACurrentModelResult
    ) throws {
        guard snapshot.found else {
            throw SDKException(
                code: .modelNotLoaded,
                message: "OCR model not loaded",
                category: .component
            )
        }
    }
}
