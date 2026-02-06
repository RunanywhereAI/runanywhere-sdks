//
//  MemoryTestView.swift
//  RunAnywhereAI
//
//  Test UI for the Memory/Vector Search layer.
//  Runs a suite of tests against CppBridge.Memory and displays results.
//

import SwiftUI

struct MemoryTestView: View {
    @StateObject private var viewModel = MemoryTestViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            // Results list
            if viewModel.results.isEmpty {
                emptyState
            } else {
                resultsList
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 12) {
            Text("Memory Layer Tests")
                .font(.title2.bold())

            Text("Vector similarity search (Flat + HNSW backends)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(action: viewModel.runAllTests) {
                HStack {
                    if viewModel.isRunning {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(viewModel.isRunning ? "Running..." : "Run Tests")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(viewModel.isRunning ? Color.gray : AppColors.primaryAccent)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(viewModel.isRunning)

            Text(viewModel.statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "memorychip")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No test results yet")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var resultsList: some View {
        List(viewModel.results) { result in
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(result.passed ? .green : .red)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(result.name)
                        .font(.subheadline.bold())

                    Text(result.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                    Text(String(format: "%.1f ms", result.duration * 1000))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
        .listStyle(.plain)
    }
}

#Preview {
    MemoryTestView()
}
