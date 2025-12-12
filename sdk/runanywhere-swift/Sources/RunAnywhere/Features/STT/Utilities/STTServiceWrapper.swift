//
//  STTServiceWrapper.swift
//  RunAnywhere SDK
//
//  Wrapper class to allow protocol-based STT service to work with BaseComponent
//

import Foundation

// MARK: - STT Service Wrapper

/// Wrapper class to allow protocol-based STT service to work with BaseComponent
public final class STTServiceWrapper: ServiceWrapper {
    public typealias ServiceProtocol = any STTService
    public var wrappedService: (any STTService)?

    public init(_ service: (any STTService)? = nil) {
        self.wrappedService = service
    }
}
