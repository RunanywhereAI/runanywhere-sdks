import CRACommons
import Foundation

/// Bridges events from runanywhere-commons (C++) to Swift.
///
/// Subscribes to C++ events and re-publishes them to the Swift EventBus
/// so that app-level code can observe SDK events through a unified API.
final class EventBridge {
    private let logger = SDKLogger(category: "EventBridge")

    /// Shared instance
    static let shared = EventBridge()

    /// Active subscription IDs
    private var subscriptions: [UInt64] = []

    /// Whether the bridge is active
    private var isActive = false

    private init() {}

    // MARK: - Lifecycle

    /// Starts the event bridge.
    /// Subscribes to all C++ event categories.
    func start() {
        guard !isActive else { return }

        logger.info("Starting event bridge")

        // Subscribe to all events
        let subscriptionId = rac_event_subscribe_all(
            { event, _ in
                EventBridge.handleEvent(event)
            },
            nil
        )

        if subscriptionId != 0 {
            subscriptions.append(subscriptionId)
        }

        isActive = true
        logger.info("Event bridge started with \(subscriptions.count) subscriptions")
    }

    /// Stops the event bridge.
    /// Unsubscribes from all C++ events.
    func stop() {
        guard isActive else { return }

        logger.info("Stopping event bridge")

        for subscriptionId in subscriptions {
            rac_event_unsubscribe(subscriptionId)
        }
        subscriptions.removeAll()

        isActive = false
    }

    // MARK: - Event Handling

    private static func handleEvent(_ eventPtr: UnsafePointer<rac_event_t>?) {
        guard let eventPtr = eventPtr else { return }
        let event = eventPtr.pointee

        // Convert category
        let category = mapCategory(event.category)

        // Extract event type
        let eventType: String
        if let typePtr = event.type {
            eventType = String(cString: typePtr)
        } else {
            eventType = "unknown"
        }

        // Extract event ID
        let eventId: String
        if let idPtr = event.id {
            eventId = String(cString: idPtr)
        } else {
            eventId = UUID().uuidString
        }

        // Extract properties JSON
        var eventProperties: [String: String] = [:]
        if let propsPtr = event.properties_json {
            let propsJson = String(cString: propsPtr)
            eventProperties = parseEventProperties(propsJson)
        }

        // Determine destination
        let destination: EventDestination
        switch event.destination {
        case RAC_EVENT_DESTINATION_PUBLIC_ONLY:
            destination = .publicOnly
        case RAC_EVENT_DESTINATION_ANALYTICS_ONLY:
            destination = .analyticsOnly
        case RAC_EVENT_DESTINATION_ALL:
            destination = .all
        default:
            destination = .publicOnly
        }

        // Extract session ID
        let sessionId: String?
        if let sessionPtr = event.session_id {
            sessionId = String(cString: sessionPtr)
        } else {
            sessionId = nil
        }

        // Create Swift event
        let bridgedEvent = BridgedEvent(
            id: eventId,
            type: eventType,
            category: category,
            timestamp: Date(timeIntervalSince1970: Double(event.timestamp_ms) / 1000.0),
            sessionId: sessionId,
            destination: destination,
            properties: eventProperties
        )

        // Publish to Swift EventPublisher
        DispatchQueue.main.async {
            EventPublisher.shared.publish(bridgedEvent)
        }
    }

    private static func parseEventProperties(_ json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) else {
            return [:]
        }
        // swiftlint:disable:next avoid_any_type
        guard let dict = parsed as? [String: Any] else {
            return [:]
        }
        // Convert to [String: String] for SDKEvent compatibility
        var result: [String: String] = [:]
        for (key, value) in dict {
            result[key] = String(describing: value)
        }
        return result
    }

    private static func mapCategory(_ category: rac_event_category_t) -> EventCategory {
        switch category {
        case RAC_EVENT_CATEGORY_SDK:
            return .sdk
        case RAC_EVENT_CATEGORY_MODEL:
            return .model
        case RAC_EVENT_CATEGORY_LLM:
            return .llm
        case RAC_EVENT_CATEGORY_STT:
            return .stt
        case RAC_EVENT_CATEGORY_TTS:
            return .tts
        case RAC_EVENT_CATEGORY_VOICE:
            return .voice
        case RAC_EVENT_CATEGORY_STORAGE:
            return .storage
        case RAC_EVENT_CATEGORY_DEVICE:
            return .device
        case RAC_EVENT_CATEGORY_NETWORK:
            return .network
        case RAC_EVENT_CATEGORY_ERROR:
            return .error
        default:
            return .sdk
        }
    }
}

// MARK: - Bridged Event

/// Event type that wraps events from the C++ layer.
private struct BridgedEvent: SDKEvent {
    let id: String
    let type: String
    let category: EventCategory
    let timestamp: Date
    let sessionId: String?
    let destination: EventDestination
    let properties: [String: String]
}
