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
    /// Scroll amount for scroll/hscroll (+up / -down).
    public let scrollPixels: Int
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
        /// profile, rendered at a declared coordinate space (pass the profile's
        /// native space, e.g. 1000×1000 for Fara). Returns nil for an unknown
        /// profile.
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
        public static func parseAction(
            _ modelOutput: String,
            profile: String = faraProfile,
            viewport: (width: Int, height: Int)
        ) -> CuaAction? {
            var action = rac_cua_action_t()
            let rc = modelOutput.withCString { output in
                rac_cua_parse_action(profile, output, UInt32(viewport.width), UInt32(viewport.height), &action)
            }
            guard rc == 0 else { return nil }
            let coordinate = action.has_coordinate != 0 ? (x: Int(action.x), y: Int(action.y)) : nil
            return CuaAction(
                kind: CuaAction.Kind(rawValue: Int(action.type.rawValue)) ?? .unknown,
                coordinate: coordinate,
                text: fixedCString(action.text),
                reasoning: fixedCString(action.reasoning),
                scrollPixels: Int(action.scroll_pixels),
                waitSeconds: action.wait_seconds,
                isValid: action.parse_ok != 0
            )
        }
    }
}

/// Read a NUL-terminated C string out of a fixed-size C `char` array tuple.
private func fixedCString<T>(_ tuple: T) -> String {
    withUnsafeBytes(of: tuple) { raw in
        guard let base = raw.baseAddress else { return "" }
        return String(cString: base.assumingMemoryBound(to: CChar.self))
    }
}
