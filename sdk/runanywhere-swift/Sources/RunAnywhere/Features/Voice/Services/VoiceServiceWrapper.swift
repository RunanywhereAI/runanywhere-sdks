//
//  VoiceServiceWrapper.swift
//  RunAnywhere SDK
//
//  Wrapper class to allow protocol-based Voice service to work with BaseComponent
//

import Foundation

// MARK: - Voice Service Wrapper

/// Wrapper class to allow protocol-based Voice service to work with BaseComponent
public final class VoiceServiceWrapper: ServiceWrapper {
    public typealias ServiceProtocol = any VoiceService
    public var wrappedService: (any VoiceService)?

    public init(_ service: (any VoiceService)? = nil) {
        self.wrappedService = service
    }
}
