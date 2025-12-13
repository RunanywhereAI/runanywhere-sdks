import Foundation

// MARK: - Empty Component Parameters

/// Empty parameters for components that don't need configuration
/// Used as a fallback when configuration doesn't conform to ComponentInitParameters
internal struct EmptyComponentParameters: ComponentInitParameters {
    var componentType: SDKComponent { .vad } // Default, not used
    var modelId: String? { nil }
    func validate() throws {}
}
