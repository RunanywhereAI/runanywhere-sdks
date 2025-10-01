//
//  BabyAGIChatView.swift
//  RunAnywhereAI
//

import SwiftUI

struct BabyAGIChatView: View {
    @StateObject private var agent = BabyAGI()
    @State private var inputText = ""
    @State private var showingInfo = false
    @State private var showingBreakdown = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Status bar
                statusBar

                // Main content
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 16) {
                            if let error = agent.error {
                                errorView(error)
                            }

                            if !agent.currentObjective.isEmpty {
                                objectiveView
                            }

                            if let breakdown = agent.taskBreakdownResponse {
                                taskBreakdownView(breakdown: breakdown)
                            }

                            if !agent.tasks.isEmpty {
                                tasksView
                            }

                            if agent.tasks.isEmpty && agent.currentObjective.isEmpty {
                                emptyStateView
                            }
                        }
                        .padding()
                        .id("bottom")
                    }
                    .onChange(of: agent.tasks.count) { _ in
                        withAnimation {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }

                // Input
                inputView
            }
            .navigationTitle("BabyAGI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                    }
                }
            }
            .sheet(isPresented: $showingInfo) {
                infoSheet
            }
        }
    }

    // MARK: - Components

    private var statusBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: agent.currentPhase.icon)
                    .foregroundColor(agent.currentPhase.color)
                    .font(.title3)
                    .symbolEffect(.pulse, options: .repeating, isActive: agent.isProcessing)

                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.currentStatus)
                        .font(.caption)
                        .foregroundColor(.primary)

                    if let model = ModelListViewModel.shared.currentModel {
                        Text(model.name)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if agent.isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding()

            if agent.currentPhase != .idle {
                phaseIndicator
            }
        }
        .background(Color(UIColor.secondarySystemBackground))
    }

    private var phaseIndicator: some View {
        HStack(spacing: 8) {
            ForEach([AgentPhase.analyzing, .generating, .executing, .completed], id: \.description) { phase in
                HStack(spacing: 4) {
                    Circle()
                        .fill(agent.currentPhase == phase || isPhasePassed(phase) ? phase.color : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)

                    Text(phase.description)
                        .font(.caption2)
                        .foregroundColor(agent.currentPhase == phase || isPhasePassed(phase) ? .primary : .secondary)
                }

                if phase != .completed {
                    Rectangle()
                        .fill(isPhasePassed(phase) ? Color.blue : Color.gray.opacity(0.3))
                        .frame(height: 2)
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    private func isPhasePassed(_ phase: AgentPhase) -> Bool {
        let phases: [AgentPhase] = [.analyzing, .generating, .executing, .completed]
        guard let currentIndex = phases.firstIndex(of: agent.currentPhase),
              let targetIndex = phases.firstIndex(of: phase) else {
            return false
        }
        return currentIndex > targetIndex
    }

    private func errorView(_ error: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.orange)
            Text(error)
                .font(.callout)
                .foregroundColor(.primary)
            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }

    private var objectiveView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Objective")
                    .font(.headline)
                Spacer()
                if !agent.tasks.isEmpty {
                    Text("\(agent.tasks.filter { $0.status == .completed }.count)/\(agent.tasks.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text(agent.currentObjective)
                .font(.body)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(8)

            if !agent.tasks.isEmpty {
                ProgressView(value: Double(agent.tasks.filter { $0.status == .completed }.count),
                           total: Double(agent.tasks.count))
                    .tint(.blue)
            }
        }
    }

    private func taskBreakdownView(breakdown: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    showingBreakdown.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.purple)

                    Text("How Tasks Were Generated")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Spacer()

                    Image(systemName: showingBreakdown ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showingBreakdown {
                VStack(alignment: .leading, spacing: 8) {
                    Text("LLM Response")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(breakdown)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.primary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(UIColor.tertiarySystemBackground))
                            .cornerRadius(8)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var tasksView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tasks")
                .font(.headline)

            ForEach(agent.tasks) { task in
                TaskRow(task: task)
            }
            .id(agent.updateTrigger)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "brain")
                .font(.system(size: 48))
                .foregroundColor(.blue)

            VStack(spacing: 8) {
                Text("BabyAGI")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Autonomous Task Agent")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Text("1")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.blue)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Analyze Objective")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Break down your goal into actionable tasks")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    Text("2")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.blue)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Prioritize Tasks")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Order tasks by importance and dependencies")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    Text("3")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.blue)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Execute Autonomously")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Complete each task using local AI")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
        }
        .padding(.vertical, 40)
        .padding(.horizontal)
    }

    private var inputView: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 12) {
                TextField("Enter your objective...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($isInputFocused)
                    .lineLimit(1...3)
                    .onSubmit(send)

                Button(action: send) {
                    Image(systemName: agent.isProcessing ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(canSend ? .blue : .gray)
                }
                .disabled(!canSend)
            }
            .padding()
        }
    }

    private var infoSheet: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "brain")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)

                        Text("BabyAGI")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Autonomous Task Management Agent")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)

                    // What is BabyAGI
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What is BabyAGI?")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("BabyAGI is an autonomous AI agent that breaks down complex objectives into manageable tasks, prioritizes them, and executes them autonomously using a local language model.")
                            .font(.body)
                            .foregroundColor(.primary)
                    }

                    // How it works
                    VStack(alignment: .leading, spacing: 16) {
                        Text("How It Works")
                            .font(.title2)
                            .fontWeight(.semibold)

                        workflowStep(
                            number: 1,
                            title: "Analyze",
                            description: "Understands your objective and identifies key requirements",
                            icon: "magnifyingglass.circle.fill",
                            color: .blue
                        )

                        workflowStep(
                            number: 2,
                            title: "Plan",
                            description: "Breaks down the objective into specific, actionable tasks",
                            icon: "list.bullet.clipboard.fill",
                            color: .orange
                        )

                        workflowStep(
                            number: 3,
                            title: "Prioritize",
                            description: "Orders tasks by importance and dependencies",
                            icon: "arrow.up.arrow.down.circle.fill",
                            color: .purple
                        )

                        workflowStep(
                            number: 4,
                            title: "Execute",
                            description: "Completes each task autonomously using local AI",
                            icon: "bolt.circle.fill",
                            color: .green
                        )
                    }

                    // Origins
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Origins")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Based on the original BabyAGI project by Yohei Nakajima, this implementation showcases autonomous task management with on-device AI models.")
                            .font(.body)
                            .foregroundColor(.primary)
                    }

                    // Features
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Key Features")
                            .font(.title2)
                            .fontWeight(.semibold)

                        featureRow(icon: "lock.shield.fill", title: "Privacy First", description: "All processing happens locally on your device")
                        featureRow(icon: "cpu.fill", title: "On-Device AI", description: "Uses locally running language models")
                        featureRow(icon: "arrow.triangle.branch", title: "Task Prioritization", description: "Intelligently orders tasks by importance")
                        featureRow(icon: "clock.fill", title: "Real-Time Progress", description: "Watch tasks being analyzed and executed")
                    }
                }
                .padding()
            }
            .navigationTitle("About BabyAGI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingInfo = false
                    }
                }
            }
        }
    }

    private func workflowStep(number: Int, title: String, description: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 48, height: 48)

                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(number).")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)

                    Text(title)
                        .font(.headline)
                }

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || agent.isProcessing
    }

    private func send() {
        guard !inputText.isEmpty else { return }
        let objective = inputText
        inputText = ""
        isInputFocused = false
        Task {
            await agent.processObjective(objective)
        }
    }
}

// MARK: - Task Row

struct TaskRow: View {
    let task: AgentTask
    @State private var isExpanded = false

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }) {
            VStack(spacing: 0) {
                // Main row (always visible)
                HStack(spacing: 12) {
                    Image(systemName: task.status.icon)
                        .foregroundColor(task.status.color)
                        .font(.title3)
                        .frame(width: 24)
                        .symbolEffect(.pulse, options: .repeating, isActive: task.status == .inProgress)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)

                        if task.status == .completed, task.executionTime > 0 {
                            Text("Generated in \(String(format: "%.1f", task.executionTime))s")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    VStack(spacing: 4) {
                        Text(task.priority.label)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(task.priority.color.opacity(0.15))
                            .foregroundColor(task.priority.color)
                            .cornerRadius(4)

                        Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()

                // Expanded content
                if isExpanded {
                    VStack(alignment: .leading, spacing: 16) {
                        Divider()

                        // Full description
                        VStack(alignment: .leading, spacing: 6) {
                            Text("TASK DESCRIPTION")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            Text(task.description)
                                .font(.callout)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal)

                        // AI Suggestion
                        if task.status == .completed {
                            if let result = task.result, !result.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "lightbulb.fill")
                                            .foregroundColor(.orange)
                                            .font(.caption)

                                        Text("AI SUGGESTION")
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.secondary)
                                    }

                                    Text(result)
                                        .font(.callout)
                                        .foregroundColor(.primary)
                                        .padding(12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            LinearGradient(
                                                colors: [Color.orange.opacity(0.08), Color.yellow.opacity(0.08)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.orange.opacity(0.25), lineWidth: 1.5)
                                        )
                                        .cornerRadius(8)
                                }
                                .padding(.horizontal)
                            }
                        } else if task.status == .inProgress {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Generating AI suggestion...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .buttonStyle(.plain)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}
