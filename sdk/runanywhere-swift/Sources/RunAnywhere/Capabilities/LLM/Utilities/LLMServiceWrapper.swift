//
//  LLMServiceWrapper.swift
//  RunAnywhere SDK
//
//  Wrapper class to allow protocol-based LLM service to work with BaseComponent
//

import Foundation

/// Wrapper class to allow protocol-based LLM service to work with BaseComponent
public final class LLMServiceWrapper: ServiceWrapper {

    public typealias ServiceProtocol = any LLMService

    public var wrappedService: (any LLMService)?

    public init(_ service: (any LLMService)? = nil) {
        self.wrappedService = service
    }
}
