import Darwin
import Foundation
import MLXRuntime
import ONNXRuntime
import RCLIHost

/// macOS CLI entry: registers MLX Swift callbacks, then hands off to the
/// shared C++ rcli host. RCLIHost is built with both `RCLI_HAS_LLAMACPP` and
/// `RCLI_HAS_MLX`, so GGUF (llama.cpp) and MLX catalog models are available.
@main
struct RunAnywhereMLXCLI {
    static func main() {
        guard registerAppleBackends() else {
            stderrWrite("error: failed to register RunAnywhere MLX runtime callbacks\n")
            Darwin.exit(1)
        }

        var argv = CommandLine.arguments.map { strdup($0) }
        defer {
            for pointer in argv {
                free(pointer)
            }
        }

        let exitCode = argv.withUnsafeMutableBufferPointer { buffer -> Int32 in
            rcli_run_main(Int32(buffer.count), buffer.baseAddress)
        }
        Darwin.exit(exitCode)
    }

    private static func registerAppleBackends() -> Bool {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                ONNX.register()
                return MLX.register()
            }
        }

        var registered = false
        DispatchQueue.main.sync {
            registered = MainActor.assumeIsolated {
                ONNX.register()
                return MLX.register()
            }
        }
        return registered
    }

    private static func stderrWrite(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
    }
}
