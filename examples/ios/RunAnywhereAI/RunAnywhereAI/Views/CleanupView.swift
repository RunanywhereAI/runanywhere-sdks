import SwiftUI

struct CleanupView: View {
    @State private var statusMessage = "Ready to clean"
    @State private var filesFound: [URL] = []
    @State private var isScanning = false
    @State private var isCleaning = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Cleanup Misplaced Files")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(statusMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if !filesFound.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(filesFound, id: \.self) { file in
                            HStack {
                                Image(systemName: "doc")
                                Text(file.lastPathComponent)
                                    .font(.caption)
                                Spacer()
                                Text(file.deletingLastPathComponent().lastPathComponent)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .frame(maxHeight: 300)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            
            HStack(spacing: 20) {
                Button("Scan for Misplaced Files") {
                    scanForMisplacedFiles()
                }
                .buttonStyle(.bordered)
                .disabled(isScanning || isCleaning)
                
                Button("Clean All") {
                    cleanMisplacedFiles()
                }
                .buttonStyle(.borderedProminent)
                .disabled(filesFound.isEmpty || isCleaning)
            }
            
            Spacer()
        }
        .padding()
        .onAppear {
            scanForMisplacedFiles()
        }
    }
    
    private func scanForMisplacedFiles() {
        isScanning = true
        filesFound = []
        statusMessage = "Scanning..."
        
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelsURL = documentsURL.appendingPathComponent("Models")
        
        // Look for files that shouldn't be in certain locations
        var misplacedFiles: [URL] = []
        
        // Check test-mlx-tiny folder for Core ML files
        let testMLXPath = modelsURL.appendingPathComponent("test-mlx-tiny")
        if fileManager.fileExists(atPath: testMLXPath.path) {
            do {
                let contents = try fileManager.contentsOfDirectory(at: testMLXPath, includingPropertiesForKeys: nil)
                for file in contents {
                    if file.pathExtension == "mlmodel" || file.lastPathComponent == "weights.npz" {
                        misplacedFiles.append(file)
                    }
                }
            } catch {
                print("Error scanning test-mlx-tiny: \(error)")
            }
        }
        
        // Check for loose files in Core ML directory
        let coreMLPath = modelsURL.appendingPathComponent("Core ML")
        if fileManager.fileExists(atPath: coreMLPath.path) {
            do {
                let contents = try fileManager.contentsOfDirectory(at: coreMLPath, includingPropertiesForKeys: nil)
                for file in contents {
                    // Individual files (not directories) in Core ML folder are likely misplaced
                    var isDirectory: ObjCBool = false
                    if fileManager.fileExists(atPath: file.path, isDirectory: &isDirectory) && !isDirectory.boolValue {
                        if file.lastPathComponent == "Manifest.json" || 
                           file.pathExtension == "mlmodel" ||
                           file.lastPathComponent.contains("weight") {
                            misplacedFiles.append(file)
                        }
                    }
                }
            } catch {
                print("Error scanning Core ML: \(error)")
            }
        }
        
        // Check for test-coreml-tiny.mlpackage files
        let testCoreMLPath = modelsURL.appendingPathComponent("test-coreml-tiny.mlpackage")
        if fileManager.fileExists(atPath: testCoreMLPath.path) {
            do {
                let contents = try fileManager.contentsOfDirectory(at: testCoreMLPath, includingPropertiesForKeys: nil)
                misplacedFiles.append(contentsOf: contents)
            } catch {
                print("Error scanning test-coreml-tiny.mlpackage: \(error)")
            }
        }
        
        filesFound = misplacedFiles
        isScanning = false
        statusMessage = filesFound.isEmpty ? "No misplaced files found" : "Found \(filesFound.count) misplaced files"
    }
    
    private func cleanMisplacedFiles() {
        isCleaning = true
        statusMessage = "Cleaning..."
        
        let fileManager = FileManager.default
        var cleaned = 0
        
        for file in filesFound {
            do {
                try fileManager.removeItem(at: file)
                cleaned += 1
            } catch {
                print("Failed to remove \(file.lastPathComponent): \(error)")
            }
        }
        
        // Also remove empty test directories
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelsURL = documentsURL.appendingPathComponent("Models")
        
        // Remove test-mlx-tiny if empty
        let testMLXPath = modelsURL.appendingPathComponent("test-mlx-tiny")
        if let contents = try? fileManager.contentsOfDirectory(at: testMLXPath, includingPropertiesForKeys: nil),
           contents.isEmpty {
            try? fileManager.removeItem(at: testMLXPath)
        }
        
        // Remove test-coreml-tiny.mlpackage
        let testCoreMLPath = modelsURL.appendingPathComponent("test-coreml-tiny.mlpackage")
        try? fileManager.removeItem(at: testCoreMLPath)
        
        filesFound = []
        isCleaning = false
        statusMessage = "Cleaned \(cleaned) files"
        
        // Refresh models
        Task {
            await ModelManager.shared.refreshModelList()
        }
    }
}