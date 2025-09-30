//
//  BabyAGIChatView.swift
//  RunAnywhereAI
//
//  Chat interface for BabyAGI autonomous agent
//

import SwiftUI

struct BabyAGIChatView: View {
    @StateObject private var agent = BabyAGI()
    @State private var inputText = ""
    @State private var selectedUseCase: UseCase = .custom
    @State private var showingExplanation = false
    @FocusState private var isInputFocused: Bool

    enum UseCase: String, CaseIterable {
        case custom = "Custom"
        case tripPlanning = "🧳 Trip Planning"
        case recipe = "🍳 Recipe Ideas"
        case brainstorm = "💡 Brainstorming"

        var placeholder: String {
            switch self {
            case .custom:
                return "Enter your objective..."
            case .tripPlanning:
                return "e.g., Help me prepare for my trip to Japan next week"
            case .recipe:
                return "e.g., I have chicken, rice, and vegetables. What can I make?"
            case .brainstorm:
                return "e.g., Ideas for my daughter's 8th birthday party"
            }
        }

        var exampleObjective: String {
            switch self {
            case .custom:
                return ""
            case .tripPlanning:
                return "Help me prepare for my 5-day trip to Tokyo next month"
            case .recipe:
                return "I have chicken breast, brown rice, bell peppers, and onions. Suggest healthy dinner recipes"
            case .brainstorm:
                return "Help me plan a memorable 10th birthday party for my son who loves science"
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with status
                headerView

                // Use case selector
                useCaseSelector

                // Main content area
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 16) {
                            // Error display
                            if let error = agent.error {
                                errorCard(error: error)
                            }

                            // Current objective display
                            if !agent.currentObjective.isEmpty {
                                objectiveCard
                            }

                            // Task visualization
                            if !agent.tasks.isEmpty {
                                taskListView
                            }

                            // Execution log
                            if !agent.executionLog.isEmpty {
                                executionLogView
                            }

                            // Welcome message when empty
                            if agent.tasks.isEmpty && agent.executionLog.isEmpty {
                                welcomeView
                            }
                        }
                        .padding()
                        .id("bottom")
                    }
                    .onChange(of: agent.executionLog.count) { _ in
                        withAnimation {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }

                // Input area
                inputArea
            }
            .navigationTitle("BabyAGI Agent")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - View Components

    private var headerView: some View {
        VStack(spacing: 8) {
            // Agent status bar
            HStack {
                // Animated brain icon when processing
                if agent.isProcessing {
                    Image(systemName: "brain")
                        .foregroundColor(.blue)
                        .symbolEffect(.pulse.byLayer, options: .repeating)
                } else {
                    Image(systemName: "brain")
                        .foregroundColor(.gray)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("BabyAGI Autonomous Agent")
                        .font(.caption)
                        .fontWeight(.semibold)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(agent.isProcessing ? Color.orange : (ModelListViewModel.shared.currentModel != nil ? Color.green : Color.red))
                            .frame(width: 8, height: 8)

                        Text(agent.currentStatus)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Info button
                Button(action: { showingExplanation = true }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                }

                if agent.isProcessing {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Model status
            if let model = ModelListViewModel.shared.currentModel {
                HStack {
                    Image(systemName: "cpu")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Model: \(model.name)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
            }
        }
        .background(Color(UIColor.secondarySystemBackground))
        .sheet(isPresented: $showingExplanation) {
            BabyAGIExplanationView()
        }
    }

    private var useCaseSelector: some View {
        Picker("Use Case", selection: $selectedUseCase) {
            ForEach(UseCase.allCases, id: \.self) { useCase in
                Text(useCase.rawValue).tag(useCase)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding()
        .onChange(of: selectedUseCase) { newValue in
            if newValue != .custom && !newValue.exampleObjective.isEmpty {
                inputText = newValue.exampleObjective
            }
        }
    }

    private func errorCard(error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)

            Text(error)
                .font(.footnote)
                .foregroundColor(.primary)

            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }

    private var objectiveCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Objective", systemImage: "target")
                    .font(.headline)
                    .foregroundColor(.blue)

                Spacer()

                if !agent.tasks.isEmpty {
                    Text("\(agent.tasks.filter { $0.status == .completed }.count)/\(agent.tasks.count) tasks")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                }
            }

            Text(agent.currentObjective)
                .font(.body)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.blue.opacity(0.05), Color.blue.opacity(0.02)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
                .cornerRadius(8)

            // Progress bar
            if !agent.tasks.isEmpty {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.blue)
                            .frame(
                                width: geometry.size.width * (Double(agent.tasks.filter { $0.status == .completed }.count) / Double(agent.tasks.count)),
                                height: 8
                            )
                            .animation(.spring(), value: agent.tasks)
                    }
                }
                .frame(height: 8)
            }
        }
        .padding(.horizontal)
    }

    private var taskListView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Generated Tasks", systemImage: "checklist")
                .font(.headline)
                .padding(.horizontal)

            ForEach(agent.tasks) { task in
                TaskCardView(task: task)
                    .padding(.horizontal)
            }
        }
    }

    private var executionLogView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Execution Log", systemImage: "terminal")
                .font(.headline)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(agent.executionLog) { entry in
                    LogEntryView(entry: entry)
                }
            }
            .padding(.horizontal)
        }
    }

    private var welcomeView: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain")
                .font(.system(size: 60))
                .foregroundColor(.blue)
                .padding(.top, 40)

            Text("Welcome to BabyAGI")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("I'm an autonomous agent that breaks down your objectives into actionable tasks and executes them locally on your device.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "lock.fill", text: "100% Private - No data leaves your device", color: .green)
                FeatureRow(icon: "bolt.fill", text: "Fast local AI models", color: .orange)
                FeatureRow(icon: "checklist", text: "Intelligent task decomposition", color: .blue)
                FeatureRow(icon: "arrow.triangle.circlepath", text: "Autonomous execution", color: .purple)
            }
            .padding(.top, 20)

            Text("Try an example above or enter your own objective below!")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.top, 10)
        }
        .padding()
    }

    private var inputArea: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 12) {
                TextField(selectedUseCase.placeholder, text: $inputText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($isInputFocused)
                    .onSubmit {
                        processObjective()
                    }

                Button(action: processObjective) {
                    if agent.isProcessing {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                }
                .disabled(inputText.isEmpty || agent.isProcessing)
                .foregroundColor(inputText.isEmpty || agent.isProcessing ? .gray : .blue)
            }
            .padding()
            .background(Color(UIColor.systemBackground))
        }
    }

    // MARK: - Actions

    private func processObjective() {
        guard !inputText.isEmpty else { return }

        let objective = inputText
        inputText = ""
        isInputFocused = false

        Task {
            await agent.processObjective(objective)
        }
    }
}

// MARK: - Supporting Views

struct TaskCardView: View {
    let task: AgentTask
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Animated status icon
                ZStack {
                    if task.status == .inProgress {
                        Circle()
                            .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: task.status.icon)
                                    .foregroundColor(task.status.color)
                                    .font(.system(size: 16))
                            )
                            .rotationEffect(.degrees(isExpanded ? 360 : 0))
                            .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: task.status)
                    } else {
                        Circle()
                            .fill(task.status.color.opacity(0.1))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: task.status.icon)
                                    .foregroundColor(task.status.color)
                                    .font(.system(size: 16))
                            )
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(task.name)
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(task.status == .completed ? .secondary : .primary)

                        Spacer()

                        HStack(spacing: 4) {
                            if task.status == .inProgress {
                                Text("Executing...")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(4)
                            }

                            Text(task.priority.label)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(task.priority.color.opacity(0.15))
                                .foregroundColor(task.priority.color)
                                .cornerRadius(4)
                        }
                    }

                    Text(task.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(isExpanded ? nil : 2)

                    if let result = task.result {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                Text("Result:")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.green)
                            }
                            Text(result)
                                .font(.caption)
                                .foregroundColor(.primary)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.green.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.green.opacity(0.2), lineWidth: 1)
                                )
                                .cornerRadius(6)
                        }
                        .padding(.top, 4)
                    }
                }

                if task.description.count > 50 {
                    Button(action: { withAnimation { isExpanded.toggle() } }) {
                        Image(systemName: isExpanded ? "chevron.up.circle" : "chevron.down.circle")
                            .foregroundColor(.blue)
                            .font(.system(size: 16))
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(task.status == .inProgress ?
                     Color.blue.opacity(0.05) :
                     Color(UIColor.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            task.status == .inProgress ?
                            Color.blue.opacity(0.3) :
                            Color.clear,
                            lineWidth: 1
                        )
                )
        )
        .scaleEffect(task.status == .inProgress ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: task.status)
    }
}

struct LogEntryView: View {
    let entry: ExecutionLogEntry

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(entry.type.color)
                .frame(width: 6, height: 6)

            Text(entry.message)
                .font(.footnote)
                .foregroundColor(.secondary)

            Spacer()

            Text(entry.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)

            Text(text)
                .font(.footnote)
                .foregroundColor(.primary)

            Spacer()
        }
    }
}

// MARK: - Preview

// MARK: - Explanation View

struct BabyAGIExplanationView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .center, spacing: 12) {
                        Image(systemName: "brain")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                            .symbolEffect(.pulse)

                        Text("BabyAGI Autonomous Agent")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Powered by Local AI Models")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)

                    // What is BabyAGI?
                    VStack(alignment: .leading, spacing: 12) {
                        Label("What is BabyAGI?", systemImage: "questionmark.circle.fill")
                            .font(.headline)
                            .foregroundColor(.blue)

                        Text("BabyAGI is an autonomous AI agent that breaks down complex objectives into actionable tasks and executes them independently. It demonstrates how AI can plan, prioritize, and complete multi-step workflows without human intervention.")
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(12)

                    // How it works
                    VStack(alignment: .leading, spacing: 16) {
                        Label("How It Works", systemImage: "gearshape.2.fill")
                            .font(.headline)
                            .foregroundColor(.green)

                        VStack(alignment: .leading, spacing: 12) {
                            StepRow(number: "1", title: "Objective Analysis", description: "Understands your goal and context")
                            StepRow(number: "2", title: "Task Generation", description: "Creates specific, actionable tasks")
                            StepRow(number: "3", title: "Prioritization", description: "Orders tasks by importance and dependencies")
                            StepRow(number: "4", title: "Execution", description: "Completes each task using local LLM")
                            StepRow(number: "5", title: "Result Synthesis", description: "Combines results to achieve objective")
                        }
                    }
                    .padding()
                    .background(Color.green.opacity(0.05))
                    .cornerRadius(12)

                    // Key Features
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Key Features", systemImage: "star.fill")
                            .font(.headline)
                            .foregroundColor(.orange)

                        VStack(alignment: .leading, spacing: 8) {
                            FeatureRow(icon: "lock.shield.fill", text: "100% on-device processing", color: .green)
                            FeatureRow(icon: "bolt.fill", text: "No internet required", color: .orange)
                            FeatureRow(icon: "brain", text: "Autonomous task execution", color: .blue)
                            FeatureRow(icon: "arrow.triangle.circlepath", text: "Adaptive planning", color: .purple)
                        }
                    }
                    .padding()
                    .background(Color.orange.opacity(0.05))
                    .cornerRadius(12)

                    // Privacy Note
                    HStack {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.green)
                        Text("All processing happens locally on your device. Your data never leaves your phone.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(8)
                }
                .padding()
            }
            .navigationTitle("About BabyAGI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct StepRow: View {
    let number: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(.caption, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.blue))

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
}

struct BabyAGIChatView_Previews: PreviewProvider {
    static var previews: some View {
        BabyAGIChatView()
    }
}
