import Foundation

/// An async-safe queue for sequential task execution
public actor AsyncQueue {
    private var tasks: [() async throws -> Void] = []
    private var isExecuting = false

    /// Add a task to the queue
    public func enqueue(_ task: @escaping () async throws -> Void) {
        tasks.append(task)
        Task {
            await executeNext()
        }
    }

    /// Execute the next task if not already executing
    private func executeNext() async {
        guard !isExecuting, !tasks.isEmpty else { return }

        isExecuting = true
        let task = tasks.removeFirst()

        do {
            try await task()
        } catch {
            // Log error but continue processing queue
            print("AsyncQueue task failed: \(error)")
        }

        isExecuting = false

        // Execute next task if available
        if !tasks.isEmpty {
            await executeNext()
        }
    }

    /// Get the number of pending tasks
    public var pendingCount: Int {
        tasks.count
    }

    /// Clear all pending tasks
    public func clear() {
        tasks.removeAll()
    }

    /// Wait for all tasks to complete
    public func waitForCompletion() async {
        while isExecuting || !tasks.isEmpty {
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
    }
}
