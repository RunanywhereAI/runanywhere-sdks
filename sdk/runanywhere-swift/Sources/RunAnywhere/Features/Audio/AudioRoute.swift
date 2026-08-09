//
//  AudioRoute.swift
//  RunAnywhere
//
//  Which speaker and which microphone the system is actually going to use.
//
//  WHY THIS EXISTS. Every voice failure looks identical from inside the app: the
//  transcript stays empty and the agent never takes a turn. The cause is very
//  often not the model or the pipeline but the route — the user is on a Bluetooth
//  headset whose mic is muted, or a meeting app has parked a virtual device as the
//  system default, or (the case that cost this project a full debugging cycle) a
//  loopback device like BlackHole is selected as the input, so the microphone
//  delivers digital silence: every sample exactly zero, forever, with no error
//  anywhere. The SDK's own diagnostic can say "I can't hear you", but it cannot
//  say *why*, and without the why the user has nothing to act on.
//
//  Naming the device turns an unactionable dead end into a one-glance fix.
//
//  WHY IT IS IN THE SDK AND NOT THE EXAMPLE APP. Reading the current route is
//  platform I/O — AVAudioSession on iOS, CoreAudio on macOS, with no shared
//  surface between them. Per the repo's layering rule that is exactly what the
//  platform SDK is for, and it means every consumer gets it rather than each app
//  reimplementing two different Apple APIs.

import Foundation

#if os(iOS) || os(tvOS) || os(visionOS)
import AVFoundation
#elseif os(macOS)
import CoreAudio
#endif

// MARK: - Public types

/// The broad kind of a route endpoint, independent of its product name.
///
/// The kind is what drives behaviour and iconography; the name is what the user
/// recognises. Both are surfaced because neither alone is enough — "AirPods Pro"
/// tells a user which earbuds, `.bluetooth` tells the app it may be dealing with
/// a lossy mic and a route that can vanish mid-session.
public enum AudioRouteKind: String, Sendable, CaseIterable {
    case builtInSpeaker
    case builtInMic
    case headphones
    case headsetMic
    case bluetooth
    case usb
    case hdmi
    case airPlay
    case carAudio
    case displayAudio
    /// Aggregate, multi-output, or loopback devices (BlackHole, Loopback,
    /// Multi-Output). Called out separately because these are the ones that
    /// silently break capture while looking perfectly healthy in Settings.
    case virtualOrAggregate
    case unknown

    /// A short human label, for when there is no product name to show.
    public var displayName: String {
        switch self {
        case .builtInSpeaker: return "Built-in Speaker"
        case .builtInMic: return "Built-in Microphone"
        case .headphones: return "Headphones"
        case .headsetMic: return "Headset Microphone"
        case .bluetooth: return "Bluetooth"
        case .usb: return "USB"
        case .hdmi: return "HDMI"
        case .airPlay: return "AirPlay"
        case .carAudio: return "Car Audio"
        case .displayAudio: return "Display Audio"
        case .virtualOrAggregate: return "Virtual Device"
        case .unknown: return "Unknown"
        }
    }

    /// SF Symbol name, so all consumers draw the same route the same way.
    public var symbolName: String {
        switch self {
        case .builtInSpeaker, .displayAudio: return "speaker.wave.2.fill"
        case .builtInMic, .headsetMic: return "mic.fill"
        case .headphones: return "headphones"
        case .bluetooth: return "wave.3.right"
        case .usb: return "cable.connector"
        case .hdmi: return "tv"
        case .airPlay: return "airplayaudio"
        case .carAudio: return "car.fill"
        case .virtualOrAggregate: return "square.stack.3d.up.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    /// Whether this kind cannot be trusted to carry real microphone signal.
    ///
    /// A loopback returns whatever is being *played* into it, which is silence
    /// when nothing is playing — indistinguishable from a working-but-quiet mic
    /// unless something says so.
    public var isLikelySilentAsInput: Bool { self == .virtualOrAggregate }
}

/// One end of the current route.
public struct AudioRouteEndpoint: Sendable, Equatable {
    /// The product name the user would recognise, e.g. "AirPods Pro", "BlackHole 2ch".
    public let name: String
    public let kind: AudioRouteKind

    public init(name: String, kind: AudioRouteKind) {
        self.name = name
        self.kind = kind
    }

    /// `name`, falling back to the kind's label when the platform gives no name.
    public var displayName: String { name.isEmpty ? kind.displayName : name }
}

/// The system's current output and input selection.
public struct AudioRoute: Sendable, Equatable {
    public let output: AudioRouteEndpoint?
    public let input: AudioRouteEndpoint?

    public init(output: AudioRouteEndpoint?, input: AudioRouteEndpoint?) {
        self.output = output
        self.input = input
    }

    /// Set when the route is one that will not produce usable capture, with a
    /// sentence the app can show verbatim. `nil` means nothing looks wrong —
    /// which is not a promise that audio *works*, only that the route itself is
    /// not the reason it does not.
    public var inputWarning: String? {
        guard let input else {
            return "No microphone is selected. Choose an input device in system settings."
        }
        if input.kind.isLikelySilentAsInput {
            return "\"\(input.displayName)\" is a virtual audio device, not a microphone. "
                 + "It only carries audio other apps play into it, so recordings will be silent. "
                 + "Select a real microphone in system settings."
        }
        return nil
    }
}

// MARK: - Reading the route

public enum AudioRouteMonitor {
    /// The route as the system reports it right now.
    ///
    /// Cheap enough to call on appear and on every route-change notification;
    /// it reads system state and allocates nothing that needs tearing down.
    public static func current() -> AudioRoute {
        #if os(iOS) || os(tvOS) || os(visionOS)
        let route = AVAudioSession.sharedInstance().currentRoute
        return AudioRoute(
            output: route.outputs.first.map {
                AudioRouteEndpoint(name: $0.portName, kind: kind(for: $0.portType))
            },
            input: route.inputs.first.map {
                AudioRouteEndpoint(name: $0.portName, kind: kind(for: $0.portType))
            }
        )
        #elseif os(macOS)
        return AudioRoute(
            output: endpoint(forDefault: kAudioHardwarePropertyDefaultOutputDevice, isInput: false),
            input: endpoint(forDefault: kAudioHardwarePropertyDefaultInputDevice, isInput: true)
        )
        #else
        return AudioRoute(output: nil, input: nil)
        #endif
    }

    /// Emits the route now, and again whenever the system changes it.
    ///
    /// A route can change mid-session without any app involvement — AirPods
    /// connect, a meeting app steals the default, a cable is pulled. A view that
    /// reads the route only once will keep showing a device the user is no longer
    /// using, which is worse than showing nothing.
    public static func routes() -> AsyncStream<AudioRoute> {
        AsyncStream { continuation in
            continuation.yield(current())

            #if os(iOS) || os(tvOS) || os(visionOS)
            // Same shape as the CoreAudio branch below: the observer token has to
            // survive until termination so it can be removed, but
            // `any NSObjectProtocol` is not `Sendable` and `onTermination` is a
            // `@Sendable` closure. The box carries it across; the unchecked
            // conformance is sound because the token is written once here and
            // only ever read by the removal call.
            final class TokenBox: @unchecked Sendable {
                let token: any NSObjectProtocol
                init(_ token: any NSObjectProtocol) { self.token = token }
            }
            let box = TokenBox(
                NotificationCenter.default.addObserver(
                    forName: AVAudioSession.routeChangeNotification,
                    object: nil,
                    queue: nil
                ) { _ in
                    continuation.yield(current())
                }
            )
            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(box.token)
            }
            #elseif os(macOS)
            // CoreAudio has no notification centre: register a listener block per
            // property and hand back a termination handler that removes both,
            // otherwise the blocks outlive the stream and fire into a dead
            // continuation.
            let queue = DispatchQueue(label: "com.runanywhere.audioroute")
            let system = AudioObjectID(kAudioObjectSystemObject)

            // CoreAudio removes a listener by block *identity*, so the exact same
            // block object has to survive until termination. An
            // `AudioObjectPropertyListenerBlock` is a C block type and therefore
            // not `Sendable`, which Swift 6 rejects when `onTermination` (a
            // `@Sendable` closure) captures it. The box carries it across that
            // boundary; the unchecked conformance is sound here because the block
            // is only ever invoked on `queue`, and the box is written once before
            // either listener is registered and never mutated afterwards.
            final class ListenerBox: @unchecked Sendable {
                let block: AudioObjectPropertyListenerBlock
                init(_ block: @escaping AudioObjectPropertyListenerBlock) { self.block = block }
            }
            let box = ListenerBox { _, _ in continuation.yield(current()) }

            var outputAddress = address(for: kAudioHardwarePropertyDefaultOutputDevice)
            var inputAddress = address(for: kAudioHardwarePropertyDefaultInputDevice)
            AudioObjectAddPropertyListenerBlock(system, &outputAddress, queue, box.block)
            AudioObjectAddPropertyListenerBlock(system, &inputAddress, queue, box.block)
            continuation.onTermination = { _ in
                var out = address(for: kAudioHardwarePropertyDefaultOutputDevice)
                var inp = address(for: kAudioHardwarePropertyDefaultInputDevice)
                AudioObjectRemovePropertyListenerBlock(system, &out, queue, box.block)
                AudioObjectRemovePropertyListenerBlock(system, &inp, queue, box.block)
            }
            #endif
        }
    }
}

// MARK: - iOS mapping

#if os(iOS) || os(tvOS) || os(visionOS)
private extension AudioRouteMonitor {
    static func kind(for port: AVAudioSession.Port) -> AudioRouteKind {
        switch port {
        case .builtInSpeaker: return .builtInSpeaker
        case .builtInMic: return .builtInMic
        case .headphones: return .headphones
        case .headsetMic: return .headsetMic
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE: return .bluetooth
        case .usbAudio: return .usb
        case .HDMI: return .hdmi
        case .airPlay: return .airPlay
        case .carAudio: return .carAudio
        case .displayPort: return .displayAudio
        // `.virtual` covers audio-unit taps that behave like a loopback.
        case .virtual: return .virtualOrAggregate
        default: return .unknown
        }
    }
}
#endif

// MARK: - macOS mapping

#if os(macOS)
private extension AudioRouteMonitor {
    static func address(for selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static func endpoint(
        forDefault selector: AudioObjectPropertySelector,
        isInput: Bool
    ) -> AudioRouteEndpoint? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = address(for: selector)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return AudioRouteEndpoint(
            name: name(of: deviceID) ?? "",
            kind: kind(of: deviceID, isInput: isInput)
        )
    }

    static func name(of deviceID: AudioDeviceID) -> String? {
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        return name as String
    }

    /// Classify from the transport type, which is what actually distinguishes a
    /// real device from an aggregate or a virtual one.
    static func kind(of deviceID: AudioDeviceID, isInput: Bool) -> AudioRouteKind {
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &transport) == noErr else {
            return .unknown
        }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            return isInput ? .builtInMic : .builtInSpeaker
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return .bluetooth
        case kAudioDeviceTransportTypeUSB:
            return .usb
        case kAudioDeviceTransportTypeHDMI:
            return .hdmi
        case kAudioDeviceTransportTypeAirPlay:
            return .airPlay
        case kAudioDeviceTransportTypeDisplayPort:
            return .displayAudio
        // Virtual, aggregate and auto-aggregate all mean "not a physical
        // endpoint" — the class that silently yields silent capture.
        case kAudioDeviceTransportTypeVirtual,
             kAudioDeviceTransportTypeAggregate,
             kAudioDeviceTransportTypeAutoAggregate:
            return .virtualOrAggregate
        default:
            return .unknown
        }
    }
}
#endif
