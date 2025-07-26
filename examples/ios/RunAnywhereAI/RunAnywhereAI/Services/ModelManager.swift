//
//  ModelManager.swift
//  RunAnywhereAI
//
//  Created on 7/26/25.
//

import Foundation

actor ModelManager {
    static let shared = ModelManager()
    
    private let documentsDirectory: URL
    private let modelsDirectory: URL
    
    private init() {
        documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        modelsDirectory = documentsDirectory.appendingPathComponent("Models")
        
        // Create models directory if it doesn't exist
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    }
    
    func modelPath(for modelName: String) -> URL {
        return modelsDirectory.appendingPathComponent(modelName)
    }
    
    func isModelDownloaded(_ modelName: String) -> Bool {
        let path = modelPath(for: modelName)
        return FileManager.default.fileExists(atPath: path.path)
    }
    
    func downloadModel(
        from url: URL,
        modelName: String,
        progress: @escaping (Double) -> Void
    ) async throws -> URL {
        let destination = modelPath(for: modelName)
        
        // If model already exists, return its path
        if isModelDownloaded(modelName) {
            return destination
        }
        
        // Download the model
        let (tempURL, _) = try await URLSession.shared.download(from: url)
        
        // Move to final destination
        try FileManager.default.moveItem(at: tempURL, to: destination)
        
        return destination
    }
    
    func deleteModel(_ modelName: String) throws {
        let path = modelPath(for: modelName)
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
    }
    
    func listDownloadedModels() -> [String] {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: modelsDirectory,
                includingPropertiesForKeys: nil
            )
            return contents.map { $0.lastPathComponent }
        } catch {
            return []
        }
    }
    
    func getModelSize(_ modelName: String) -> Int64? {
        let path = modelPath(for: modelName)
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
            return attributes[.size] as? Int64
        } catch {
            return nil
        }
    }
    
    func getAvailableSpace() -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(
                forPath: documentsDirectory.path
            )
            return attributes[.systemFreeSize] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
}