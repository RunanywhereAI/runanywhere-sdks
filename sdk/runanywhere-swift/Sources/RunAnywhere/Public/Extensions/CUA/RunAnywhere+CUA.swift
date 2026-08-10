import CRACommons
import Foundation

/// A computer-use-agent action parsed from a model's output, with coordinates
/// already scaled to the caller's viewport. Model-agnostic (see `RunAnywhere.CUA`).
public struct CuaAction: Sendable {
    /// The action the model wants to perform.
    public enum Kind: Int, Sendable {
        case unknown = 0
        case leftClick, rightClick, doubleClick, tripleClick
        case mouseMove, leftClickDrag
        case type, key, scroll, hscroll
        case visitURL, historyBack, webSearch
        case readPageAnswer, pauseMemorize, askUser
        case wait, terminate
    }

    public let kind: Kind
    /// Viewport-scaled pixel coordinate (for click / move / drag), else nil.
    public let coordinate: (x: Int, y: Int)?
    /// Primary string argument, interpreted by `kind`: type→text, visitURL→url,
    /// webSearch→query, terminate→answer, askUser/readPageAnswer→question,
    /// pauseMemorize→fact.
    public let text: String
    /// Chain-of-thought the model emitted before the tool call, if any.
    public let reasoning: String
    /// Horizontal scroll amount, for `hscroll`. Raw model output, sign
    /// unverified against any real device trace.
    public let scrollX: Int
    /// Vertical scroll amount, for `scroll`. Raw model output, sign
    /// unverified against any real device trace.
    public let scrollY: Int
    /// Seconds to wait for `wait`.
    public let waitSeconds: Double
    /// Whether a valid tool call was found.
    public let isValid: Bool
}

extension RunAnywhere {
    /// Computer-use-agent scaffold. Turns a VLM into a drivable agent using a
    /// model *profile* (data describing prompt / output format / coordinate
    /// convention). Fara1.5 ships built in; adding another CUA model is a new
    /// profile in commons, not new API. This is stateless — pair it with
    /// `processImage`/`processImageStream` for inference; the app owns
    /// screenshot capture, executing the action, and the agent loop.
    public enum CUA {
        /// Built-in profile for Microsoft Fara1.5 / Qwen3.5-VL `computer_use`.
        public static let faraProfile = RAC_CUA_PROFILE_FARA

        /// The system prompt (identity + `computer_use` tool schema) for a
        /// profile, rendered at the profile's coordinate space. Returns nil
        /// for an unknown profile, or if `display` is neither the profile's own
        /// space (1000×1000 for Fara) nor zero: the space is a property of the
        /// model, and declaring a different one would contradict how
        /// `parseAction` rescales the model's output.
        public static func systemPrompt(
            profile: String = faraProfile,
            display: (width: Int, height: Int) = (1000, 1000)
        ) -> String? {
            let needed = rac_cua_system_prompt(profile, UInt32(display.width), UInt32(display.height), nil, 0)
            guard needed > 0 else { return nil }
            var buffer = [CChar](repeating: 0, count: Int(needed) + 1)
            _ = rac_cua_system_prompt(profile, UInt32(display.width), UInt32(display.height), &buffer, buffer.count)
            return String(cString: buffer)
        }

        /// Parse a model's raw output into a `CuaAction`, rescaling coordinates
        /// from the profile's model space to `viewport`. Returns nil for an
        /// unknown profile; `CuaAction.isValid` is false when no tool call was
        /// found.
        ///
        /// Decodes the canonical `runanywhere.v1.CuaAction` proto that commons
        /// serializes — the same proto-byte bridging every other modality uses,
        /// so there is no hand-mirrored C struct to keep in sync.
        public static func parseAction(
            _ modelOutput: String,
            profile: String = faraProfile,
            viewport: (width: Int, height: Int)
        ) -> CuaAction? {
            var buffer = rac_proto_buffer_t()
            defer { rac_proto_buffer_free(&buffer) }
            let rc = modelOutput.withCString { output in
                rac_cua_parse_action_proto(
                    profile, output, UInt32(viewport.width), UInt32(viewport.height), &buffer)
            }
            // NOTE: a valid "no tool call found" result is an all-defaults
            // CuaAction, which proto3 serializes to ZERO bytes. Rejecting
            // size == 0 here would report it as nil — the value this function
            // reserves for an unknown profile — and would make Swift the lone
            // SDK that cannot tell those two cases apart.
            guard rc == RAC_SUCCESS, let data = buffer.data else { return nil }
            let bytes = buffer.size > 0 ? Data(bytes: data, count: buffer.size) : Data()
            guard let proto = try? RACuaAction(serializedBytes: bytes) else { return nil }

            // coordinateValid/scrollPixels/parseOk were deleted outright
            // (idl/cua.proto): x/y presence IS "has a coordinate" now
            // (hasX/hasY), scroll_pixels split into scroll_x/scroll_y, and
            // parseOk was renamed is_valid.
            let coordinate = (proto.hasX && proto.hasY) ? (x: Int(proto.x), y: Int(proto.y)) : nil
            return CuaAction(
                kind: CuaAction.Kind(rawValue: proto.type.rawValue) ?? .unknown,
                coordinate: coordinate,
                text: proto.text,
                reasoning: proto.reasoning,
                scrollX: Int(proto.scrollX),
                scrollY: Int(proto.scrollY),
                waitSeconds: proto.waitSeconds,
                isValid: proto.isValid
            )
        }
    }
}
