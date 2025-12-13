//
//  VADServiceWrapper.swift
//  RunAnywhere SDK
//
//  Wrapper class to allow protocol-based VAD service to work with BaseComponent
//

import Foundation

// MARK: - VAD Service Wrapper

/// Wrapper class to allow protocol-based VAD service to work with BaseComponent
public final class VADServiceWrapper: ServiceWrapper {
    public typealias ServiceProtocol = any VADService
    public var wrappedService: (any VADService)?

    public init(_ service: (any VADService)? = nil) {
        self.wrappedService = service
    }
}
