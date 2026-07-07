import Darwin
import Foundation
import MLXRuntime
import RCLIHost

@main
struct RunAnywhereMLXCLI {
    static func main() {
        guard registerMLXRuntime() else {
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

    private static func registerMLXRuntime() -> Bool {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                MLX.register()
            }
        }

        var registered = false
        DispatchQueue.main.sync {
            registered = MainActor.assumeIsolated {
                MLX.register()
            }
        }
        return registered
    }

    private static func stderrWrite(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
    }
}
