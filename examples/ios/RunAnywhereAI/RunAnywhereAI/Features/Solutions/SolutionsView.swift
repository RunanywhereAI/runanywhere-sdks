//
//  SolutionsView.swift
//  RunAnywhereAI
//
//  Demo screen for `RunAnywhere.solutions.run(yaml:)`.
//
//  Two buttons run the canonical voice_agent.yaml and rag.yaml solutions
//  via the SDK's solutions capability namespace. The YAML payloads come from
//  `Generated/SolutionsYaml.swift`, emitted by
//  `scripts/sync-solutions-yamls.sh` from the canonical
//  `sdk/runanywhere-commons/examples/solutions/*.yaml` — no inline copies,
//  no drift (mirrors the React Native example's sync script).
//
//  The screen renders the solution lifecycle as a simple log: every state
//  transition (creating, started, error) is appended to a scrollable text
//  view so the demo stays readable without wiring up streaming output.
//

import RunAnywhere
import SwiftUI

struct SolutionsView: View {
    @State private var log: [String] = []
    @State private var isRunning = false

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text(
                    "Run a prepackaged pipeline (voice agent or RAG) "
                    + "by handing a YAML config to RunAnywhere.solutions.run."
                )
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    Button {
                        runSolution(name: "Voice Agent", yaml: SolutionsYaml.voiceAgent)
                    } label: {
                        Label("Voice Agent", systemImage: "mic.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunning)

                    Button {
                        runSolution(name: "RAG", yaml: SolutionsYaml.rag)
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
                .background(Color.gray.opacity(0.12))
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
