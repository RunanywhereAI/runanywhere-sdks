import Combine
import Foundation
import RunAnywhere
#if canImport(FoundationModels)
import FoundationModels
#endif

// Note: Message, MessageAnalytics and ConversationAnalytics are now in separate model files

// MARK: - Conversation Store

@MainActor
class ConversationStore: ObservableObject {
    static let shared = ConversationStore()

    @Published var conversations: [Conversation] = []
    @Published var currentConversation: Conversation?

    private let documentsDirectory: URL

    private static func getDocumentsDirectory() -> URL {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Unable to access documents directory")
        }
        return url
    }
    private let conversationsDirectory: URL
    private let attachmentsDirectory: URL
    private let decoder = JSONDecoder()
    /// Serial queue for all disk I/O (encode/write/read) so persistence never
    /// blocks the main thread and writes to a file stay FIFO-ordered.
    private let ioQueue = DispatchQueue(label: "com.runanywhere.conversationstore.io", qos: .utility)

    private init() {
        documentsDirectory = Self.getDocumentsDirectory()
        conversationsDirectory = documentsDirectory.appendingPathComponent("Conversations")
        attachmentsDirectory = conversationsDirectory.appendingPathComponent("Attachments")

        // Create conversations directory if it doesn't exist
        try? FileManager.default.createDirectory(at: conversationsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)

        decoder.dateDecodingStrategy = .iso8601

        // Load existing conversations off the main thread so launch isn't blocked
        // decoding every conversation file.
        loadConversations()
    }

    // MARK: - Public Methods

    func createConversation(title: String? = nil) -> Conversation {
        let conversation = Conversation(
            id: UUID().uuidString,
            title: title ?? "New Chat",
            createdAt: Date(),
            updatedAt: Date(),
            messages: [],
            modelName: nil,
            frameworkName: nil
        )

        // Don't add to conversations list yet - wait until first message is added
        currentConversation = conversation
        // Don't save empty conversation - wait until first message is added

        return conversation
    }

    /// Ids of conversations the user deleted this session. A late write from an
    /// in-flight generation (or a stale ViewModel) must not resurrect them.
    private var deletedConversationIds: Set<String> = []

    func updateConversation(_ conversation: Conversation) {
        var updated = conversation
        updated.updatedAt = Date()

        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            // Update existing conversation
            conversations[index] = updated
        } else if deletedConversationIds.contains(conversation.id) {
            // Tombstoned: a write arriving after the user deleted this chat (e.g.
            // an in-flight generation finalizing) must not re-create it on disk
            // or in the list.
            return
        } else {
            // First time adding this conversation (when first message is sent)
            conversations.insert(updated, at: 0)
        }

        if currentConversation?.id == conversation.id {
            currentConversation = updated
        }

        saveConversation(updated)
    }

    func deleteConversation(_ conversation: Conversation) {
        deletedConversationIds.insert(conversation.id)
        conversations.removeAll { $0.id == conversation.id }

        if currentConversation?.id == conversation.id {
            currentConversation = conversations.first
        }

        // Delete file
        let fileURL = conversationFileURL(for: conversation.id)
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: attachmentDirectory(for: conversation.id))

        // Let the chat ViewModel reset if it was viewing/generating this one.
        NotificationCenter.default.post(name: .conversationDeleted, object: conversation.id)
    }

    func addMessage(_ message: Message, to conversation: Conversation) {
        var updated = conversation
        updated.messages.append(message)
        updated.updatedAt = Date()

        // Always try to generate a fallback title if still "New Chat"
        if updated.title == "New Chat" {
            if let firstUserMessage = updated.messages.first(where: { $0.role == .user }),
               !firstUserMessage.content.isEmpty {
                updated.title = generateTitle(from: firstUserMessage.content)
            }
        }

        updateConversation(updated)

        // Try to generate smart title with Foundation Models after first AI response
        if message.role == .assistant && updated.messages.count >= 2 {
            let conversationId = updated.id
            Task { @MainActor in
                await self.generateSmartTitleIfNeeded(for: conversationId)
            }
        }
    }

    func saveAttachment(
        data: Data,
        filename: String,
        kind: MessageAttachment.Kind,
        conversationID: String,
        detail: String? = nil,
        previewText: String? = nil
    ) throws -> MessageAttachment {
        let directory = attachmentDirectory(for: conversationID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let storedFilename = "\(UUID().uuidString)-\(safeAttachmentFilename(filename))"
        let fileURL = directory.appendingPathComponent(storedFilename)
        try data.write(to: fileURL, options: [.atomic])

        return MessageAttachment(
            kind: kind,
            filename: filename,
            detail: detail,
            relativePath: "Conversations/Attachments/\(conversationID)/\(storedFilename)",
            previewText: previewText
        )
    }

    // MARK: - Foundation Models Title Generation

    /// Public method to generate smart title for a conversation
    func generateSmartTitleForConversation(_ conversationId: String) async {
        await generateSmartTitleIfNeeded(for: conversationId)
    }

    private func generateSmartTitleIfNeeded(for conversationId: String) async {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else { return }

        // Find the conversation
        guard let conversation = conversations.first(where: { $0.id == conversationId }) else {
            return
        }

        // Get the fallback title to compare
        let firstUserMessage = conversation.messages.first { $0.role == .user }
        let fallbackTitle = firstUserMessage.map { generateTitle(from: $0.content) } ?? "New Chat"

        // Only generate if title is still the default or fallback
        let currentTitle = conversation.title
        guard currentTitle == "New Chat" || currentTitle == fallbackTitle else {
            return
        }

        // Use the SDK's platform capability gate so simulator and unsupported
        // devices keep the deterministic fallback title.
        guard SystemFoundationModels.isAvailable else { return }

        // Create conversation text from first few messages
        let conversationText = conversation.messages
            .prefix(4)
            .map { msg in
                "\(msg.role == .user ? "User" : "Assistant"): \(msg.content.prefix(200))"
            }
            .joined(separator: "\n")

        do {
            let titleSession = LanguageModelSession(
                instructions: Instructions("""
                    You are an expert at creating descriptive, readable chat titles.
                    Generate a clear title (2-5 words) that captures the main topic.
                    Respond in the same language as the conversation.
                    Only output the title, nothing else.
                    """)
            )

            let titlePrompt = """
            Create a descriptive, readable title for this conversation:

            \(conversationText)

            Title:
            """

            let response = try await titleSession.respond(to: Prompt(titlePrompt))
            let title = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")

            // Update the conversation with the AI-generated title
            if !title.isEmpty, var conv = self.conversations.first(where: { $0.id == conversationId }) {
                conv.title = String(title.prefix(50))
                self.updateConversation(conv)
            }
        } catch {
            // Keep the fallback title
        }
        #endif
    }

    func loadConversation(_ id: String) -> Conversation? {
        if let conversation = conversations.first(where: { $0.id == id }) {
            currentConversation = conversation
            return conversation
        }

        // Try to load from disk
        let fileURL = conversationFileURL(for: id)
        if let data = try? Data(contentsOf: fileURL),
           let conversation = try? decoder.decode(Conversation.self, from: data) {
            conversations.append(conversation)
            currentConversation = conversation
            return conversation
        }

        return nil
    }

    // MARK: - Search

    func searchConversations(query: String) -> [Conversation] {
        guard !query.isEmpty else { return conversations }

        let lowercasedQuery = query.lowercased()

        return conversations.filter { conversation in
            // Search in title
            if conversation.title.lowercased().contains(lowercasedQuery) {
                return true
            }

            // Search in messages
            return conversation.messages.contains { message in
                message.content.lowercased().contains(lowercasedQuery)
            }
        }
    }

    // MARK: - Private Methods

    private func loadConversations() {
        let directory = conversationsDirectory
        ioQueue.async { [weak self] in
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let files = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)) ?? []
            let loaded: [Conversation] = files
                .filter { $0.pathExtension == "json" }
                .compactMap { file in
                    guard let data = try? Data(contentsOf: file) else { return nil }
                    return try? decoder.decode(Conversation.self, from: data)
                }
            Task { @MainActor in
                guard let self else { return }
                // Merge (not replace): dedupe by id so a conversation created during
                // the async-load window isn't clobbered. Sort newest-first.
                let existing = Set(self.conversations.map { $0.id })
                let merged = self.conversations + loaded.filter { !existing.contains($0.id) }
                self.conversations = merged.sorted { $0.updatedAt > $1.updatedAt }
            }
        }
    }

    private func saveConversation(_ conversation: Conversation) {
        let fileURL = conversationFileURL(for: conversation.id)
        // Encode + write off the main thread. The serial queue keeps writes to the
        // same file FIFO-ordered (last write wins, as before), so moving off-main
        // can't reorder a turn's successive saves.
        ioQueue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            do {
                let data = try encoder.encode(conversation)
                try data.write(to: fileURL, options: [.atomic])
            } catch {
                // Best-effort persistence; a failed write is retried on the next save.
            }
        }
    }

    private func conversationFileURL(for id: String) -> URL {
        conversationsDirectory.appendingPathComponent("\(id).json")
    }

    private func attachmentDirectory(for id: String) -> URL {
        attachmentsDirectory.appendingPathComponent(id)
    }

    private func safeAttachmentFilename(_ filename: String) -> String {
        let cleaned = filename
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>"))
            .joined(separator: "-")
        return cleaned.isEmpty ? "attachment" : cleaned
    }

    private func generateTitle(from content: String) -> String {
        // Take first 50 characters or up to first newline
        let maxLength = 50
        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if let newlineIndex = cleaned.firstIndex(of: "\n") {
            let firstLine = String(cleaned[..<newlineIndex])
            return String(firstLine.prefix(maxLength))
        }

        return String(cleaned.prefix(maxLength))
    }
}

// MARK: - Conversation Model

struct Conversation: Identifiable, Codable {
    let id: String
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var messages: [Message]
    var modelName: String?
    var frameworkName: String?

    // NEW: Conversation-level analytics
    var analytics: ConversationAnalytics?
    var performanceSummary: PerformanceSummary?

    var summary: String {
        guard !messages.isEmpty else { return "No messages" }

        let messageCount = messages.count
        let userMessages = messages.filter { $0.role == .user }.count
        let assistantMessages = messages.filter { $0.role == .assistant }.count

        return "\(messageCount) messages • \(userMessages) from you, \(assistantMessages) from AI"
    }

    var lastMessagePreview: String {
        guard let lastMessage = messages.last else { return "Start a conversation" }

        let preview = lastMessage.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")

        return String(preview.prefix(100))
    }
}

// Performance summary for quick access
struct PerformanceSummary: Codable {
    let averageResponseTime: TimeInterval
    let totalTokens: Int
    let mainModel: String?
    let completionRate: Double
    let averageTokensPerSecond: Double

    init(from messages: [Message]) {
        let analyticsMessages = messages.compactMap { $0.analytics }

        if !analyticsMessages.isEmpty {
            let count = Double(analyticsMessages.count)
            let totalTime = analyticsMessages.compactMap { $0.totalGenerationTime }.reduce(0, +)
            averageResponseTime = totalTime / count
            totalTokens = analyticsMessages.reduce(0) { $0 + $1.inputTokens + $1.outputTokens }
            mainModel = analyticsMessages.first?.modelName
            let completed = analyticsMessages.filter { $0.completionStatus == .complete }.count
            completionRate = Double(completed) / count
            let totalTPS = analyticsMessages.compactMap { $0.averageTokensPerSecond }.reduce(0, +)
            averageTokensPerSecond = totalTPS / count
        } else {
            averageResponseTime = 0
            totalTokens = 0
            mainModel = nil
            completionRate = 0
            averageTokensPerSecond = 0
        }
    }
}
