//
//  TTSServiceWrapper.swift
//  RunAnywhere SDK
//
//  Wrapper class for protocol-based TTS services
//

import Foundation

/// Wrapper class to allow protocol-based TTS service to work with BaseComponent
///
/// This wrapper enables the TTSComponent to work with the generic BaseComponent
/// infrastructure while using the protocol-based TTSService.
public final class TTSServiceWrapper: ServiceWrapper {

    // MARK: - ServiceWrapper

    public typealias ServiceProtocol = any TTSService

    /// The wrapped TTS service
    public var wrappedService: (any TTSService)?

    // MARK: - Initialization

    public init(_ service: (any TTSService)? = nil) {
        self.wrappedService = service
    }

    // MARK: - Convenience Methods

    /// Check if the wrapper contains a valid service
    public var hasService: Bool {
        wrappedService != nil
    }

    /// Synthesize text using the wrapped service
    public func synthesize(text: String, options: TTSOptions) async throws -> Data {
        guard let service = wrappedService else {
            throw TTSError.notInitialized
        }
        return try await service.synthesize(text: text, options: options)
    }

    /// Stop synthesis on the wrapped service
    public func stop() {
        wrappedService?.stop()
    }

    /// Cleanup the wrapped service
    public func cleanup() async {
        await wrappedService?.cleanup()
        wrappedService = nil
    }
}
