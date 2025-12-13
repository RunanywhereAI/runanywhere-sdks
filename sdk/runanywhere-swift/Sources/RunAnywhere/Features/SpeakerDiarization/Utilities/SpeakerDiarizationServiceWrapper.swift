//
//  SpeakerDiarizationServiceWrapper.swift
//  RunAnywhere SDK
//
//  Wrapper class to allow protocol-based SpeakerDiarization service to work with BaseComponent
//

import Foundation

// MARK: - SpeakerDiarization Service Wrapper

/// Wrapper class to allow protocol-based SpeakerDiarization service to work with BaseComponent
public final class SpeakerDiarizationServiceWrapper: ServiceWrapper {
    public typealias ServiceProtocol = any SpeakerDiarizationService
    public var wrappedService: (any SpeakerDiarizationService)?

    public init(_ service: (any SpeakerDiarizationService)? = nil) {
        self.wrappedService = service
    }
}
