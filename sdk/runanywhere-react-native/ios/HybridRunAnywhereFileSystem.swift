import Foundation
import NitroModules

/// Swift implementation of RunAnywhereFileSystem HybridObject
class HybridRunAnywhereFileSystem: HybridRunAnywhereFileSystemSpec {
    
    private let fileManager = FileManager.default
    
    private func getDocumentsDirectory() -> URL {
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    func getDataDirectory() throws -> Promise<String> {
        return Promise.async {
            let path = self.getDocumentsDirectory().appendingPathComponent("runanywhere-data").path
            if !self.fileManager.fileExists(atPath: path) {
                try? self.fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
            }
            return path
        }
    }
    
    func getModelsDirectory() throws -> Promise<String> {
        return Promise.async {
            let path = self.getDocumentsDirectory().appendingPathComponent("runanywhere-models").path
            if !self.fileManager.fileExists(atPath: path) {
                try? self.fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
            }
            return path
        }
    }
    
    func fileExists(path: String) throws -> Promise<Bool> {
        return Promise.async {
            return self.fileManager.fileExists(atPath: path)
        }
    }
    
    func modelExists(modelId: String) throws -> Promise<Bool> {
        return Promise.async {
            let modelsDir = self.getDocumentsDirectory().appendingPathComponent("runanywhere-models")
            let modelPath = modelsDir.appendingPathComponent(modelId).path
            return self.fileManager.fileExists(atPath: modelPath)
        }
    }
    
    func getModelPath(modelId: String) throws -> Promise<String> {
        return Promise.async {
            let modelsDir = self.getDocumentsDirectory().appendingPathComponent("runanywhere-models")
            return modelsDir.appendingPathComponent(modelId).path
        }
    }
    
    func downloadModel(modelId: String, url: String, callback: ((_ progress: Double) -> Void)?) throws -> Promise<Void> {
        return Promise.async {
            guard let downloadURL = URL(string: url) else {
                throw NSError(domain: "RunAnywhere", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }
            
            let modelsDir = self.getDocumentsDirectory().appendingPathComponent("runanywhere-models")
            if !self.fileManager.fileExists(atPath: modelsDir.path) {
                try? self.fileManager.createDirectory(at: modelsDir, withIntermediateDirectories: true)
            }
            
            let destPath = modelsDir.appendingPathComponent(modelId)
            
            // Download the file
            let (tempURL, _) = try await URLSession.shared.download(from: downloadURL)
            
            if self.fileManager.fileExists(atPath: destPath.path) {
                try self.fileManager.removeItem(at: destPath)
            }
            try self.fileManager.moveItem(at: tempURL, to: destPath)
            callback?(1.0)
        }
    }
    
    func deleteModel(modelId: String) throws -> Promise<Void> {
        return Promise.async {
            let modelsDir = self.getDocumentsDirectory().appendingPathComponent("runanywhere-models")
            let modelPath = modelsDir.appendingPathComponent(modelId)
            
            if self.fileManager.fileExists(atPath: modelPath.path) {
                try self.fileManager.removeItem(at: modelPath)
            }
        }
    }
    
    func readFile(path: String) throws -> Promise<String> {
        return Promise.async {
            return try String(contentsOfFile: path, encoding: .utf8)
        }
    }
    
    func writeFile(path: String, content: String) throws -> Promise<Void> {
        return Promise.async {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
    
    func deleteFile(path: String) throws -> Promise<Void> {
        return Promise.async {
            if self.fileManager.fileExists(atPath: path) {
                try self.fileManager.removeItem(atPath: path)
            }
        }
    }
    
    func getAvailableDiskSpace() throws -> Promise<Double> {
        return Promise.async {
            do {
                let attributes = try self.fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
                if let freeSize = attributes[.systemFreeSize] as? NSNumber {
                    return freeSize.doubleValue
                }
            } catch {}
            return 0
        }
    }
    
    func getTotalDiskSpace() throws -> Promise<Double> {
        return Promise.async {
            do {
                let attributes = try self.fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
                if let totalSize = attributes[.systemSize] as? NSNumber {
                    return totalSize.doubleValue
                }
            } catch {}
            return 0
        }
    }
}
