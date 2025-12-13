import Foundation

// MARK: - Pipeline Delegate

/// Protocol for pipeline delegates
public protocol ModularPipelineDelegate: AnyObject { // swiftlint:disable:this avoid_any_object
    func pipelineDidGenerateEvent(_ event: ModularPipelineEvent)
}
