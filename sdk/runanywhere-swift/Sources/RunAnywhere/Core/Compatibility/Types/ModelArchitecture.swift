//
//  ModelArchitecture.swift
//  RunAnywhere SDK
//
//  Model architecture enumeration
//

import Foundation

/// Model architectures
public enum ModelArchitecture: String, CaseIterable {
    case llama
    case mistral
    case phi
    case qwen
    case gemma
    case gpt2
    case bert
    case t5
    case falcon
    case starcoder
    case codegen
    case custom

    public var displayName: String {
        switch self {
        case .llama: return "LLaMA"
        case .mistral: return "Mistral"
        case .phi: return "Phi"
        case .qwen: return "Qwen"
        case .gemma: return "Gemma"
        case .gpt2: return "GPT-2"
        case .bert: return "BERT"
        case .t5: return "T5"
        case .falcon: return "Falcon"
        case .starcoder: return "StarCoder"
        case .codegen: return "CodeGen"
        case .custom: return "Custom"
        }
    }
}
