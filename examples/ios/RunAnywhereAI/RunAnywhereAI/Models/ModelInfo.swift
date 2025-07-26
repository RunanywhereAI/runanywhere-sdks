//
//  ModelInfo.swift
//  RunAnywhereAI
//
//  Created on 7/26/25.
//

import Foundation

struct ModelInfo: Identifiable {
    let id = UUID()
    let name: String
    let size: String
    let framework: String
    let quantization: String?
    let description: String
    let minimumMemory: Int64
    let recommendedMemory: Int64
    
    var displaySize: String {
        return size
    }
    
    var isCompatible: Bool {
        let availableMemory = ProcessInfo.processInfo.physicalMemory
        return availableMemory >= minimumMemory
    }
}