//
//  ServiceLifecycleObserverImpl.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/26/25.
//

import Foundation

/// Service lifecycle event
enum ServiceLifecycleEvent {
    case created
    case removed
}

/// Simple implementation of ServiceLifecycleObserver
class ServiceLifecycleObserverImpl: ServiceLifecycleObserver {
    private let handler: (LLMService, ServiceLifecycleEvent) -> Void

    init(handler: @escaping (LLMService, ServiceLifecycleEvent) -> Void) {
        self.handler = handler
    }

    func serviceCreated(_ service: LLMService) {
        handler(service, .created)
    }

    func serviceRemoved(_ service: LLMService) {
        handler(service, .removed)
    }
}
