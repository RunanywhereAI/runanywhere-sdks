//
//  SolutionsView.swift
//  RunAnywhereAI
//
//  Wave 3 Step 3.3 (G-E6): Demo screen for `RunAnywhere.solutions.run(yaml:)`.
//
//  Two buttons run the canonical voice_agent.yaml and rag.yaml solutions
//  via the SDK's solutions capability namespace. The YAML payloads are
//  embedded inline as string constants — no asset-bundling churn — and
//  match `sdk/runanywhere-commons/examples/solutions/*.yaml` byte-for-byte.
//
//  The screen renders the solution lifecycle as a simple log: every state
//  transition (creating, started, error) is appended to a scrollable text
//  view so the demo stays readable without wiring up streaming output.
//

import RunAnywhere
import SwiftUI

private let voiceAgentYAML = """
voice_agent:
  llm_model_id: "qwen3-4b-q4_k_m"
  stt_model_id: "whisper-base"
  tts_model_id: "kokoro"
  vad_model_id: "silero-v5"

  sample_rate_hz: 16000
  chunk_ms: 20
  audio_source: "microphone"

  enable_barge_in: true
  barge_in_threshold_ms: 200

  system_prompt: "You are a helpful voice assistant. Keep answers concise."
  max_context_tokens: 4096
  temperature: 0.7

  emit_partials: true
  emit_thoughts: false
"""

private let ragYAML = """
rag:
  embed_model_id: "bge-small-en-v1.5"
  rerank_model_id: "bge-reranker-v2-m3"
  llm_model_id: "qwen3-4b-q4_k_m"

  vector_store: "usearch"
  vector_store_path: "/tmp/ra-rag.usearch"

  retrieve_k: 24
  rerank_top: 6

  bm25_k1: 1.2
  bm25_b: 0.75
  rrf_k: 60

  prompt_template: "Use the context below to answer.\\n\\nContext:\\n{{context}}\\n\\nQuestion: {{query}}"
"""

struct SolutionsView: View {
    @State private var log: [String] = []
    @State private var isRunning = false

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text("Run a prepackaged pipeline (voice agent or RAG) by handing a YAML config to RunAnywhere.solutions.run.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    Button {
                        runSolution(name: "Voice Agent", yaml: voiceAgentYAML)
                    } label: {
                        Label("Voice Agent", systemImage: "mic.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunning)

                    Button {
                        runSolution(name: "RAG", yaml: ragYAML)
                    } label: {
                        Label("RAG", systemImage: "doc.text.magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunning)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
            }
            .padding()
            .navigationTitle("Solutions")
        }
    }

    private func runSolution(name: String, yaml: String) {
        isRunning = true
        append("→ \(name): creating solution from YAML…")
        Task {
            do {
                let handle = try await RunAnywhere.solutions.run(yaml: yaml)
                append("✓ \(name): handle created. Calling start()…")
                try handle.start()
                append("✓ \(name): started. Tearing down (demo).")
                handle.destroy()
                append("✓ \(name): destroyed.")
            } catch {
                append("✗ \(name): \(error.localizedDescription)")
            }
            await MainActor.run { isRunning = false }
        }
    }

    private func append(_ line: String) {
        Task { @MainActor in
            log.append(line)
        }
    }
}

#Preview {
    SolutionsView()
}
