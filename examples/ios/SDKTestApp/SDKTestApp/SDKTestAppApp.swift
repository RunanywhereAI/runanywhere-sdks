import SwiftUI
import RunAnywhere
import LlamaCPPRuntime
import ONNXRuntime

@main
struct SDKTestAppApp: App {
    init() {
        // Ensure backends are registered early.
        _ = LlamaCPP.autoRegister
        _ = ONNX.autoRegister
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
