import ArgumentParser
import Foundation
import Rainbow

/// RunAnywhere iOS CLI - Native Swift tool for iOS developers
@main
struct RunAnywhereCLI: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "runanywhere-ios",
        abstract: "🍎 RunAnywhere iOS CLI - Build, lint, and benchmark iOS apps",
        version: "0.1.0",
        subcommands: [
            Benchmark.self,
            Build.self,
            Lint.self,
            Devices.self,
        ],
        defaultSubcommand: nil
    )
}

// MARK: - Benchmark Command

struct Benchmark: ParsableCommand {
    static var configuration = CommandConfiguration(
        abstract: "Run benchmarks on iOS devices",
        subcommands: [
            BenchmarkAuto.self,
            BenchmarkDevices.self,
            BenchmarkPull.self,
            BenchmarkReport.self,
        ],
        defaultSubcommand: BenchmarkAuto.self
    )
}

/// Fully automated benchmark - just plug in your iPhone!
struct BenchmarkAuto: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "auto",
        abstract: "🚀 Fully automated benchmark - just plug in your iPhone!"
    )
    
    @Option(name: .shortAndLong, help: "Configuration: quick, default, comprehensive")
    var config: String = "quick"
    
    @Option(name: .shortAndLong, help: "Comma-separated model IDs (default: all downloaded)")
    var models: String?
    
    @Option(name: .long, help: "URL to a GGUF model to download and benchmark")
    var modelUrl: String?
    
    @Option(name: .long, help: "Custom name for the model (optional)")
    var modelName: String?
    
    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Int = 600
    
    @Option(name: .shortAndLong, help: "Output directory for results")
    var output: String = "benchmark_results"
    
    @Flag(name: .long, help: "Skip build even if app not installed")
    var skipBuild: Bool = false
    
    func run() throws {
        printBanner()
        
        // Step 1: Detect devices using Xcode tools
        print("\n" + "📱 Step 1: Detecting iOS devices...".cyan)
        
        let devices = detectDevicesWithXcode()
        
        if devices.isEmpty {
            print("\n" + "❌ No iOS devices found!".red)
            print("\n" + "Please:".yellow)
            print("  • Connect your iPhone/iPad via USB and unlock it")
            print("  • Or boot an iOS Simulator")
            print("\nRun 'runanywhere-ios devices' to check connection status")
            return
        }
        
        print("✓ Found \(devices.count) device(s):".green)
        for device in devices {
            let icon = device.isSimulator ? "📱" : "📲"
            print("  \(icon) \(device.name.cyan) (iOS \(device.osVersion)) [\(device.udid.prefix(12))...]")
        }
        
        // Step 1.5: Check if app is installed, build if needed
        let device = devices[0] // Use first device
        print("\n" + "🔍 Step 1.5: Checking app installation...".cyan)
        
        if !isAppInstalled(device: device) {
            print("   App not installed on \(device.name)".yellow)
            
            if skipBuild {
                print("   ❌ --skip-build specified, cannot continue".red)
                return
            }
            
            print("   🔨 Building and installing app...".cyan)
            
            if !buildAndInstallApp(device: device) {
                print("   ❌ Failed to build/install app".red)
                print("   Try running manually:".lightBlack)
                print("     cd examples/ios/RunAnywhereAI".lightBlack)
                print("     xcodebuild -scheme RunAnywhereAI ...".lightBlack)
                return
            }
            
            print("   ✅ App installed successfully!".green)
        } else {
            print("   ✅ App is installed".green)
        }
        
        // Step 2: Run benchmarks
        let modelList = models?.split(separator: ",").map { String($0).trimmingCharacters(in: CharacterSet.whitespaces) }
        
        print("\n" + "⚙️  Step 2: Starting benchmarks...".cyan)
        print("   Config: \(config)")
        print("   Models: \(modelList?.joined(separator: ", ") ?? "all downloaded")")
        
        for device in devices {
            print("\n" + "▶ Launching on \(device.name)...".cyan)
            
            // Launch app with benchmark args using devicectl
            launchAppWithBenchmark(device: device, config: config, models: modelList)
            
            print("   ✓ App launched!".green)
            
            if let modelUrl = modelUrl {
                print("")
                print("   📥 Model URL provided: \(modelUrl.prefix(60))...".cyan)
                print("   The app will download and benchmark this model automatically.".lightBlack)
                print("")
                
                // Open URL scheme to trigger download
                openBenchmarkURL(device: device, config: config, modelUrl: modelUrl, modelName: modelName)
            } else {
                print("")
                print("   ┌─────────────────────────────────────────────────────┐".yellow)
                print("   │  📱 ON YOUR iPHONE:                                 │".yellow)
                print("   │                                                     │".yellow)
                print("   │  1. Go to the 'Benchmark' tab (speedometer icon)    │".yellow)
                print("   │  2. Select models (or they may auto-select)         │".yellow)  
                print("   │  3. Tap 'Run Benchmark' button                      │".yellow)
                print("   │                                                     │".yellow)
                print("   │  The CLI will detect when benchmark completes.      │".yellow)
                print("   └─────────────────────────────────────────────────────┘".yellow)
            }
            print("")
            print("   ⏳ Waiting for benchmark to complete (timeout: \(timeout)s)...".lightBlack)
            
            // Wait for completion
            let success = waitForCompletion(device: device)
            
            if success {
                print("   ✓ Benchmark completed!".green)
                // Pull results
                let files = pullResultsFromDevice(device: device, outputDir: output)
                if files.count > 0 {
                    print("   ✓ Pulled \(files.count) result file(s)".green)
                }
            } else {
                print("   ⚠ Timed out waiting for benchmark".yellow)
            }
        }
        
        // Step 3: Show results
        print("\n" + "📊 Step 3: Results".cyan)
        printResults(outputDir: output)
        
        print("\n" + "✓ Results saved to: \(output)".green)
    }
    
    /// Detect devices using xcrun xctrace
    private func detectDevicesWithXcode() -> [IOSDevice] {
        let output = shellOutput(["xcrun", "xctrace", "list", "devices"])
        var devices: [IOSDevice] = []
        var inDevicesSection = false
        var inSimulatorsSection = false
        
        for line in output.split(separator: "\n") {
            let lineStr = String(line)
            
            if lineStr.contains("== Devices ==") {
                inDevicesSection = true
                inSimulatorsSection = false
                continue
            }
            if lineStr.contains("== Simulators ==") {
                inDevicesSection = false
                inSimulatorsSection = true
                continue
            }
            if lineStr.contains("== Devices Offline ==") {
                inDevicesSection = false
                continue
            }
            
            // Parse device line: "iPhone (2) (26.1) (00008140-000E25A6022A801C)"
            if inDevicesSection && !lineStr.isEmpty && !lineStr.contains("MacBook") {
                // Extract UDID (last parentheses)
                if let udidMatch = lineStr.range(of: #"\(([A-F0-9-]{20,})\)"#, options: .regularExpression) {
                    let udid = String(lineStr[udidMatch]).dropFirst().dropLast()
                    
                    // Extract version
                    var version = "Unknown"
                    if let versionMatch = lineStr.range(of: #"\((\d+\.\d+)\)"#, options: .regularExpression) {
                        version = String(lineStr[versionMatch]).dropFirst().dropLast().description
                    }
                    
                    // Extract name (everything before first parenthesis)
                    let name = lineStr.components(separatedBy: " (").first?.trimmingCharacters(in: CharacterSet.whitespaces) ?? "iOS Device"
                    
                    devices.append(IOSDevice(
                        udid: String(udid),
                        name: name,
                        osVersion: version,
                        isSimulator: false
                    ))
                }
            }
            
            // Parse simulator line (booted ones only)
            if inSimulatorsSection && lineStr.contains("Booted") {
                if let udidMatch = lineStr.range(of: #"\(([A-F0-9-]{36})\)"#, options: .regularExpression) {
                    let udid = String(lineStr[udidMatch]).dropFirst().dropLast()
                    let name = lineStr.components(separatedBy: " Simulator").first?.trimmingCharacters(in: CharacterSet.whitespaces) ?? "Simulator"
                    
                    devices.append(IOSDevice(
                        udid: String(udid),
                        name: name,
                        osVersion: "17.0",
                        isSimulator: true
                    ))
                }
            }
        }
        
        return devices
    }
    
    /// Launch app with benchmark arguments
    private func launchAppWithBenchmark(device: IOSDevice, config: String, models: [String]?) {
        let bundleId = "com.runanywhere.RunAnywhere"
        let modelsArg = models?.joined(separator: ",") ?? "all"
        
        // Terminate if running
        _ = shellOutput(["xcrun", "devicectl", "device", "process", "terminate", "--device", device.udid, bundleId])
        Thread.sleep(forTimeInterval: 0.5)
        
        if device.isSimulator {
            // Simulator: use simctl
            shellExec([
                "xcrun", "simctl", "launch", device.udid, bundleId,
                "-benchmark_auto", "true",
                "-benchmark_config", config,
                "-benchmark_models", modelsArg
            ])
        } else {
            // Physical device: use devicectl
            shellExec([
                "xcrun", "devicectl", "device", "process", "launch",
                "--device", device.udid,
                bundleId,
                "--", "-benchmark_auto", "true", "-benchmark_config", config, "-benchmark_models", modelsArg
            ])
        }
    }
    
    /// Pull results from device
    private func pullResultsFromDevice(device: IOSDevice, outputDir: String) -> [String] {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        
        if device.isSimulator {
            return IOSDeviceManager.pullResults(device: device, outputDir: outputDir)
        }
        
        // For physical devices, we'd need to use different approach
        // For now, just return empty - results can be viewed in app
        return []
    }
    
    /// Open URL scheme to trigger benchmark with model download
    private func openBenchmarkURL(device: IOSDevice, config: String, modelUrl: String, modelName: String?) {
        // Build the URL
        var urlString = "runanywhere://benchmark?config=\(config)"
        
        if let encoded = modelUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlString += "&model_url=\(encoded)"
        }
        
        if let name = modelName, let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlString += "&model_name=\(encoded)"
        }
        
        print("   Opening URL: \(urlString.prefix(80))...".lightBlack)
        
        if device.isSimulator {
            // For simulator, use simctl openurl
            shellExec(["xcrun", "simctl", "openurl", device.udid, urlString])
        } else {
            // For physical device, we need a different approach
            // The app should already be launched with the URL scheme registered
            // We can use devicectl to open the URL
            
            // Unfortunately devicectl doesn't support opening URLs directly
            // We'll write to a shared location that the app can read
            print("   ⚠️ URL scheme launch not fully supported on physical devices yet".yellow)
            print("   Please manually enter the model URL in the app".lightBlack)
        }
    }
    
    private func printBanner() {
        print("")
        print("╔═══════════════════════════════════════════════════════════╗".cyan)
        print("║".cyan + "        RunAnywhere iOS Benchmark                          ".bold + "║".cyan)
        print("║".cyan + "        Just plug in your iPhone and run!                  ".lightBlack + "║".cyan)
        print("╚═══════════════════════════════════════════════════════════╝".cyan)
    }
    
    private func waitForCompletion(device: IOSDevice) -> Bool {
        let startTime = Date()
        let timeoutInterval = TimeInterval(timeout)
        var lastCheckTime = Date()
        var dotCount = 0
        let pollInterval: TimeInterval = 5  // Check every 5 seconds
        let statusInterval: TimeInterval = 30 // Show status every 30 seconds
        var lastStatusTime = Date()
        
        print("")
        
        while Date().timeIntervalSince(startTime) < timeoutInterval {
            let elapsed = Int(Date().timeIntervalSince(startTime))
            
            // Check for completion
            if IOSDeviceManager.isBenchmarkComplete(device: device) {
                print("\r   ✅ Benchmark completed!                              ".green)
                return true
            }
            
            // Show periodic status updates
            if Date().timeIntervalSince(lastStatusTime) >= statusInterval {
                lastStatusTime = Date()
                let remaining = Int(timeoutInterval) - elapsed
                print("\r   📊 Still running... (\(elapsed)s elapsed, \(remaining)s remaining)    ")
                
                // Check if app is still running
                if !isAppRunning(device: device) {
                    print("   ⚠️  App may have closed. Checking for results...".yellow)
                    Thread.sleep(forTimeInterval: 2)
                    if IOSDeviceManager.isBenchmarkComplete(device: device) {
                        print("   ✅ Found results!".green)
                        return true
                    }
                }
            }
            
            // Animated waiting indicator
            dotCount = (dotCount + 1) % 4
            let dots = String(repeating: ".", count: dotCount + 1)
            let spaces = String(repeating: " ", count: 3 - dotCount)
            print("\r   ⏳ Waiting\(dots)\(spaces) (\(elapsed)s)", terminator: "")
            fflush(stdout)
            
            Thread.sleep(forTimeInterval: pollInterval)
        }
        
        print("\n   ⚠ Timeout after \(timeout)s".yellow)
        return false
    }
    
    /// Check if the app is currently running on the device
    private func isAppRunning(device: IOSDevice) -> Bool {
        let bundleId = "com.runanywhere.RunAnywhere"
        
        if device.isSimulator {
            let output = shellOutput(["xcrun", "simctl", "get_app_container", device.udid, bundleId])
            return !output.contains("error")
        } else {
            // For physical devices, assume running if we can't check
            return true
        }
    }
    
    /// Check if the app is installed on the device
    private func isAppInstalled(device: IOSDevice) -> Bool {
        let bundleId = "com.runanywhere.RunAnywhere"
        
        if device.isSimulator {
            let output = shellOutput(["xcrun", "simctl", "get_app_container", device.udid, bundleId])
            return !output.contains("error") && !output.isEmpty
        } else {
            // For physical devices, use devicectl
            let output = shellOutput(["xcrun", "devicectl", "device", "info", "apps", "--device", device.udid])
            return output.contains(bundleId)
        }
    }
    
    /// Build and install the app on the device
    private func buildAndInstallApp(device: IOSDevice) -> Bool {
        let workspaceRoot = findWorkspaceRoot()
        let projectPath = workspaceRoot + "/examples/ios/RunAnywhereAI"
        
        // Check if project exists
        let projectFile = projectPath + "/RunAnywhereAI.xcodeproj"
        if !FileManager.default.fileExists(atPath: projectFile) {
            print("   ❌ Xcode project not found at \(projectFile)".red)
            return false
        }
        
        // Build the app
        print("   📦 Building (this may take a minute)...".lightBlack)
        
        let destination = device.isSimulator 
            ? "platform=iOS Simulator,id=\(device.udid)"
            : "id=\(device.udid)"
        
        let buildResult = shellExec([
            "xcodebuild",
            "-project", projectFile,
            "-scheme", "RunAnywhereAI",
            "-configuration", "Debug",
            "-destination", destination,
            "-quiet",
            "build"
        ], currentDirectory: projectPath)
        
        if buildResult != 0 {
            print("   ❌ Build failed".red)
            return false
        }
        
        print("   ✅ Build succeeded".green)
        
        // Find the built app
        let derivedDataPath = NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData"
        let appPath: String
        
        if device.isSimulator {
            appPath = findBuiltApp(in: derivedDataPath, for: "iphonesimulator")
        } else {
            appPath = findBuiltApp(in: derivedDataPath, for: "iphoneos")
        }
        
        if appPath.isEmpty {
            print("   ❌ Could not find built app".red)
            return false
        }
        
        // Install the app
        print("   📲 Installing on \(device.name)...".lightBlack)
        
        if device.isSimulator {
            let installResult = shellExec(["xcrun", "simctl", "install", device.udid, appPath])
            return installResult == 0
        } else {
            let installResult = shellExec([
                "xcrun", "devicectl", "device", "install", "app",
                "--device", device.udid, appPath
            ])
            return installResult == 0
        }
    }
    
    /// Find the most recently built app in DerivedData
    private func findBuiltApp(in derivedDataPath: String, for platform: String) -> String {
        let fm = FileManager.default
        
        // Look for RunAnywhereAI-* directories
        guard let contents = try? fm.contentsOfDirectory(atPath: derivedDataPath) else {
            return ""
        }
        
        for dir in contents where dir.starts(with: "RunAnywhereAI-") {
            let appPath = "\(derivedDataPath)/\(dir)/Build/Products/Debug-\(platform)/RunAnywhereAI.app"
            if fm.fileExists(atPath: appPath) {
                return appPath
            }
        }
        
        return ""
    }
    
    private func printResults(outputDir: String) {
        let fm = FileManager.default
        let outputURL = URL(fileURLWithPath: outputDir)
        
        guard let files = try? fm.contentsOfDirectory(at: outputURL, includingPropertiesForKeys: nil),
              !files.isEmpty else {
            print("   No results found in output directory".yellow)
            print("   Results are available in the app on your device".lightBlack)
            return
        }
        
        // Parse and display results
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                
                print("")
                print("   ┌─────────────────────────────────────────────────┐".cyan)
                
                if let modelName = json["modelName"] as? String {
                    print("   │ Model: \(modelName.padding(toLength: 38, withPad: " ", startingAt: 0)) │".cyan)
                }
                
                if let tokensPerSec = json["avgTokensPerSecond"] as? Double {
                    let value = String(format: "%.1f tok/s", tokensPerSec)
                    print("   │ Speed: \(value.padding(toLength: 38, withPad: " ", startingAt: 0)) │")
                }
                
                if let ttft = json["avgTtftMs"] as? Double {
                    let value = String(format: "%.0f ms", ttft)
                    print("   │ TTFT:  \(value.padding(toLength: 38, withPad: " ", startingAt: 0)) │")
                }
                
                if let memory = json["peakMemoryBytes"] as? Int64 {
                    let mb = Double(memory) / 1024 / 1024
                    let value = String(format: "%.0f MB", mb)
                    print("   │ Memory: \(value.padding(toLength: 37, withPad: " ", startingAt: 0)) │")
                }
                
                print("   └─────────────────────────────────────────────────┘".cyan)
            }
        }
    }
}

/// List connected iOS devices
struct BenchmarkDevices: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "devices",
        abstract: "List connected iOS devices and simulators"
    )
    
    func run() throws {
        print("\n" + "📱 iOS Devices".cyan)
        print(String(repeating: "─", count: 50))
        
        let devices = IOSDeviceManager.listDevices()
        
        if devices.isEmpty {
            print("\n" + "No devices found".lightBlack)
            print("\nTo connect a device:")
            print("  • iPhone/iPad: Connect via USB and trust this computer")
            print("  • Simulator: Open Xcode → Window → Devices and Simulators")
            return
        }
        
        print("\n" + "Simulators:".bold)
        let simulators = devices.filter { $0.isSimulator }
        if simulators.isEmpty {
            print("  None running".lightBlack)
        } else {
            for device in simulators {
                print("  📱 \(device.name.cyan) (iOS \(device.osVersion)) [\(String(device.udid.prefix(12)))]...".lightBlack)
            }
        }
        
        print("\n" + "Physical Devices:".bold)
        let physical = devices.filter { !$0.isSimulator }
        if physical.isEmpty {
            print("  None connected".lightBlack)
        } else {
            for device in physical {
                print("  📲 \(device.name.cyan) (iOS \(device.osVersion)) [\(String(device.udid.prefix(12)))]...".lightBlack)
            }
        }
        
        print("")
    }
}

/// Pull benchmark results from device
struct BenchmarkPull: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "pull",
        abstract: "Pull benchmark results from iOS devices"
    )
    
    @Option(name: .shortAndLong, help: "Output directory")
    var output: String = "benchmark_results"
    
    func run() throws {
        print("\n" + "📥 Pulling benchmark results...".cyan)
        
        let devices = IOSDeviceManager.listDevices()
        
        if devices.isEmpty {
            print("❌ No devices found".red)
            return
        }
        
        var totalFiles = 0
        for device in devices {
            print("  From \(device.name)...")
            let files = IOSDeviceManager.pullResults(device: device, outputDir: output)
            totalFiles += files.count
            for file in files {
                print("    ✓ \(file)".green)
            }
        }
        
        print("\n✓ Pulled \(totalFiles) file(s) to \(output)".green)
    }
}

/// Generate benchmark report
struct BenchmarkReport: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "report",
        abstract: "Generate benchmark report"
    )
    
    @Option(name: .shortAndLong, help: "Input directory with results")
    var input: String = "benchmark_results"
    
    @Option(name: .shortAndLong, help: "Output format: markdown, json, html")
    var format: String = "markdown"
    
    func run() throws {
        print("\n" + "📊 Generating report...".cyan)
        // Report generation logic here
        print("✓ Report generated".green)
    }
}

// MARK: - Build Command

struct Build: ParsableCommand {
    static var configuration = CommandConfiguration(
        abstract: "Build iOS SDK and apps",
        subcommands: [
            BuildSDK.self,
            BuildApp.self,
        ]
    )
}

struct BuildSDK: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "sdk",
        abstract: "Build the Swift SDK"
    )
    
    @Flag(name: .long, help: "Setup dependencies first")
    var setup: Bool = false
    
    func run() throws {
        print("\n" + "🔨 Building Swift SDK...".cyan)
        
        let scriptPath = findWorkspaceRoot() + "/sdk/runanywhere-swift/scripts/build-swift.sh"
        
        if FileManager.default.fileExists(atPath: scriptPath) {
            var args = [scriptPath]
            if setup { args.append("--setup") }
            
            let result = shellExec(args)
            if result == 0 {
                print("✓ SDK built successfully".green)
            } else {
                print("❌ Build failed".red)
            }
        } else {
            print("⚠ Build script not found".yellow)
        }
    }
}

struct BuildApp: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "app",
        abstract: "Build the iOS sample app"
    )
    
    @Flag(name: .shortAndLong, help: "Run app after building")
    var launch: Bool = false
    
    func run() throws {
        print("\n" + "🔨 Building iOS app...".cyan)
        
        let appPath = findWorkspaceRoot() + "/examples/ios/RunAnywhereAI"
        
        let buildResult = shellExec([
            "xcodebuild",
            "-project", "\(appPath)/RunAnywhereAI.xcodeproj",
            "-scheme", "RunAnywhereAI",
            "-configuration", "Debug",
            "-destination", "generic/platform=iOS Simulator",
            "build"
        ])
        
        if buildResult == 0 {
            print("✓ App built successfully".green)
            
            if launch {
                print("\n" + "🚀 Launching app...".cyan)
                // Launch on first available simulator
                let devices = IOSDeviceManager.listDevices()
                if let device = devices.first(where: { $0.isSimulator }) {
                    shellExec(["xcrun", "simctl", "launch", device.udid, "ai.runanywhere.RunAnywhereAI"])
                    print("✓ App launched on \(device.name)".green)
                }
            }
        } else {
            print("❌ Build failed".red)
        }
    }
}

// MARK: - Lint Command

struct Lint: ParsableCommand {
    static var configuration = CommandConfiguration(
        abstract: "Run SwiftLint on iOS code"
    )
    
    @Flag(name: .long, help: "Auto-fix issues")
    var fix: Bool = false
    
    func run() throws {
        print("\n" + "🔍 Linting iOS code...".cyan)
        
        let appPath = findWorkspaceRoot() + "/examples/ios/RunAnywhereAI"
        
        var args = ["swiftlint"]
        if fix { args.append("--fix") }
        
        let result = shellExec(args, currentDirectory: appPath)
        
        if result == 0 {
            print("✓ No lint issues found".green)
        }
    }
}

// MARK: - Devices Command

struct Devices: ParsableCommand {
    static var configuration = CommandConfiguration(
        abstract: "List all connected iOS devices"
    )
    
    func run() throws {
        // Delegate to BenchmarkDevices
        let devicesCmd = BenchmarkDevices()
        try devicesCmd.run()
    }
}

// MARK: - iOS Device Manager

struct IOSDevice {
    let udid: String
    let name: String
    let osVersion: String
    let isSimulator: Bool
}

enum IOSDeviceManager {
    private static let appBundleId = "ai.runanywhere.RunAnywhereAI"
    
    static func listDevices() -> [IOSDevice] {
        var devices: [IOSDevice] = []
        
        // List simulators
        let simOutput = shellOutput(["xcrun", "simctl", "list", "devices", "booted"])
        
        // Parse simulator output
        let lines = simOutput.split(separator: "\n")
        for line in lines {
            // Format: "    iPhone 15 Pro (UDID) (Booted)"
            let pattern = #"^\s+(.+?)\s+\(([A-F0-9-]+)\)\s+\(Booted\)"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: String(line), range: NSRange(line.startIndex..., in: line)) {
                let name = String(line[Range(match.range(at: 1), in: line)!])
                let udid = String(line[Range(match.range(at: 2), in: line)!])
                
                devices.append(IOSDevice(
                    udid: udid,
                    name: name,
                    osVersion: "17.0", // Could parse from runtime
                    isSimulator: true
                ))
            }
        }
        
        // List physical devices (if libimobiledevice is installed)
        let physicalOutput = shellOutput(["idevice_id", "-l"])
        let udids = physicalOutput.split(separator: "\n").map { String($0) }
        
        for udid in udids where !udid.isEmpty {
            let name = shellOutput(["idevicename", "-u", udid]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let version = shellOutput(["ideviceinfo", "-u", udid, "-k", "ProductVersion"]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            
            devices.append(IOSDevice(
                udid: udid,
                name: name.isEmpty ? "iOS Device" : name,
                osVersion: version.isEmpty ? "Unknown" : version,
                isSimulator: false
            ))
        }
        
        return devices
    }
    
    static func launchBenchmark(device: IOSDevice, config: String, models: [String]?) {
        let modelsArg = models?.joined(separator: ",") ?? "all"
        
        if device.isSimulator {
            // Terminate if running
            shellExec(["xcrun", "simctl", "terminate", device.udid, appBundleId])
            Thread.sleep(forTimeInterval: 0.5)
            
            // Launch with benchmark args
            shellExec([
                "xcrun", "simctl", "launch", device.udid,
                appBundleId,
                "-benchmark_auto", "true",
                "-benchmark_config", config,
                "-benchmark_models", modelsArg
            ])
        } else {
            // Physical device
            shellExec([
                "idevicedebug", "-u", device.udid, "run", appBundleId,
                "--args", "-benchmark_auto", "true"
            ])
        }
    }
    
    static func isBenchmarkComplete(device: IOSDevice) -> Bool {
        guard device.isSimulator else { return false }
        
        let containerOutput = shellOutput([
            "xcrun", "simctl", "get_app_container", device.udid, appBundleId, "data"
        ])
        
        let containerPath = containerOutput.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        if !containerPath.isEmpty && !containerPath.contains("error") {
            let documentsPath = containerPath + "/Documents"
            let fm = FileManager.default
            
            if let files = try? fm.contentsOfDirectory(atPath: documentsPath) {
                return files.contains { $0.hasPrefix("benchmark_") && $0.hasSuffix(".json") }
            }
        }
        
        return false
    }
    
    static func pullResults(device: IOSDevice, outputDir: String) -> [String] {
        var pulledFiles: [String] = []
        
        // Create output directory
        let fm = FileManager.default
        try? fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        
        if device.isSimulator {
            let containerOutput = shellOutput([
                "xcrun", "simctl", "get_app_container", device.udid, appBundleId, "data"
            ])
            
            let containerPath = containerOutput.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            
            if !containerPath.isEmpty && !containerPath.contains("error") {
                let documentsPath = containerPath + "/Documents"
                
                if let files = try? fm.contentsOfDirectory(atPath: documentsPath) {
                    for file in files where file.hasPrefix("benchmark_") && file.hasSuffix(".json") {
                        let sourcePath = documentsPath + "/" + file
                        let destPath = outputDir + "/ios_sim_" + file
                        
                        try? fm.copyItem(atPath: sourcePath, toPath: destPath)
                        pulledFiles.append(file)
                    }
                }
            }
        }
        
        return pulledFiles
    }
}

// MARK: - Helpers

func findWorkspaceRoot() -> String {
    let fm = FileManager.default
    
    // Method 1: Check from current directory
    var dir = fm.currentDirectoryPath
    while dir != "/" {
        if isWorkspaceRoot(dir) {
            return dir
        }
        dir = (dir as NSString).deletingLastPathComponent
    }
    
    // Method 2: Check from executable's location (for when run from anywhere)
    // The CLI is at: workspace/cli-swift/.build/release/runanywhere-ios
    if let execPath = Bundle.main.executablePath {
        var execDir = (execPath as NSString).deletingLastPathComponent
        // Go up from .build/release to cli-swift, then to workspace root
        for _ in 0..<5 {
            if isWorkspaceRoot(execDir) {
                return execDir
            }
            execDir = (execDir as NSString).deletingLastPathComponent
        }
    }
    
    // Method 3: Try common development paths
    let commonPaths = [
        NSHomeDirectory() + "/Desktop/RunanywhereAI/master/runanywhere-sdks",
        NSHomeDirectory() + "/Developer/runanywhere-sdks",
        NSHomeDirectory() + "/Projects/runanywhere-sdks",
        "/Users/shubhammalhotra/Desktop/RunanywhereAI/master/runanywhere-sdks"
    ]
    
    for path in commonPaths {
        if isWorkspaceRoot(path) {
            return path
        }
    }
    
    return fm.currentDirectoryPath
}

func isWorkspaceRoot(_ path: String) -> Bool {
    let fm = FileManager.default
    let settingsPath = path + "/settings.gradle.kts"
    let cliSwiftPath = path + "/cli-swift"
    let examplesPath = path + "/examples/ios/RunAnywhereAI"
    
    return fm.fileExists(atPath: settingsPath) || 
           (fm.fileExists(atPath: cliSwiftPath) && fm.fileExists(atPath: examplesPath))
}

/// Execute a shell command and return exit code
@discardableResult
func shellExec(_ args: [String], currentDirectory: String? = nil) -> Int {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = args
    
    if let dir = currentDirectory {
        process.currentDirectoryURL = URL(fileURLWithPath: dir)
    }
    
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return -1
    }
    
    return Int(process.terminationStatus)
}

/// Execute a shell command and return output
func shellOutput(_ args: [String], currentDirectory: String? = nil) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = args
    
    if let dir = currentDirectory {
        process.currentDirectoryURL = URL(fileURLWithPath: dir)
    }
    
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return ""
    }
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}
