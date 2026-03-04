import Foundation
import SwiftUI
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
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        documentsDirectory = Self.getDocumentsDirectory()
        conversationsDirectory = documentsDirectory.appendingPathComponent("Conversations")

        // Create conversations directory if it doesn't exist
        try? FileManager.default.createDirectory(at: conversationsDirectory, withIntermediateDirectories: true)

        // Set up encoder/decoder
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        // Load existing conversations
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

    func updateConversation(_ conversation: Conversation) {
        var updated = conversation
        updated.updatedAt = Date()

        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            // Update existing conversation
            conversations[index] = updated
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
        conversations.removeAll { $0.id == conversation.id }

        if currentConversation?.id == conversation.id {
            currentConversation = conversations.first
        }

        // Delete file
        let fileURL = conversationFileURL(for: conversation.id)
        try? FileManager.default.removeItem(at: fileURL)
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
        let fallbackTitle = conversation.messages.first(where: { $0.role == .user })
            .map { generateTitle(from: $0.content) } ?? "New Chat"

        // Only generate if title is still the default or fallback
        let currentTitle = conversation.title
        guard currentTitle == "New Chat" || currentTitle == fallbackTitle else {
            return
        }

        // Check if Foundation Models is available
        guard SystemLanguageModel.default.isAvailable else { return }

        // Create conversation text from first few messages
        let conversationText = conversation.messages.prefix(4).map { msg in
            "\(msg.role == .user ? "User" : "Assistant"): \(msg.content.prefix(200))"
        }.joined(separator: "\n")

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
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: conversationsDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )

            var loadedConversations: [Conversation] = []

            for file in files where file.pathExtension == "json" {
                if let data = try? Data(contentsOf: file),
                   let conversation = try? decoder.decode(Conversation.self, from: data) {
                    loadedConversations.append(conversation)
                }
            }

            // Sort by update date, newest first
            conversations = loadedConversations.sorted { $0.updatedAt > $1.updatedAt }

            // Don't automatically set current conversation - let ChatViewModel create a new one
        } catch {
            print("Error loading conversations: \(error)")
        }
    }

    private func saveConversation(_ conversation: Conversation) {
        let fileURL = conversationFileURL(for: conversation.id)

        do {
            let data = try encoder.encode(conversation)
            try data.write(to: fileURL)
        } catch {
            print("Error saving conversation: \(error)")
        }
    }

    private func conversationFileURL(for id: String) -> URL {
        conversationsDirectory.appendingPathComponent("\(id).json")
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

// MARK: - Conversation List View

struct ConversationListView: View {
    @StateObject private var store = ConversationStore.shared
    @State private var searchQuery = ""
    @State private var showingDeleteConfirmation = false
    @State private var conversationToDelete: Conversation?

    @Environment(\.dismiss)
    private var dismiss

    private static let conversationSelectedNotification = Notification.Name("ConversationSelected")

    var filteredConversations: [Conversation] {
        store.searchConversations(query: searchQuery)
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(filteredConversations) { conversation in
                    ConversationRow(conversation: conversation, searchQuery: searchQuery)
                        .onTapGesture {
                            store.loadConversation(conversation.id)
                            NotificationCenter.default.post(
                                name: Self.conversationSelectedNotification,
                                object: conversation
                            )
                            dismiss()
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                conversationToDelete = conversation
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .searchable(text: $searchQuery, prompt: "Search conversations")
            .navigationTitle("Conversations")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(
                        action: {
                            let newConversation = store.createConversation()
                            // Notify ChatViewModel about the new conversation
                            let name = Notification.Name("ConversationSelected")
                            NotificationCenter.default.post(name: name, object: newConversation)
                            dismiss()
                        },
                        label: {
                            Image(systemName: "plus")
                        }
                    )
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(
                        action: {
                            let newConversation = store.createConversation()
                            // Notify ChatViewModel about the new conversation
                            let name = Notification.Name("ConversationSelected")
                            NotificationCenter.default.post(name: name, object: newConversation)
                            dismiss()
                        },
                        label: {
                            Image(systemName: "plus")
                        }
                    )
                }
                #endif
            }
            .alert("Delete Conversation?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let conversation = conversationToDelete {
                        store.deleteConversation(conversation)
                    }
                }
            } message: {
                Text("This action cannot be undone.")
            }
        }
        #if os(iOS)
        .navigationViewStyle(.stack)
        #endif
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conversation: Conversation
    let searchQuery: String

    init(conversation: Conversation, searchQuery: String = "") {
        self.conversation = conversation
        self.searchQuery = searchQuery
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Title with highlighting
                if !searchQuery.isEmpty {
                    highlightedText(conversation.title, searchText: searchQuery, isTitle: true)
                        .lineLimit(1)
                } else {
                    Text(conversation.title)
                        .font(.headline)
                        .lineLimit(1)
                }

                Spacer()

                if let frameworkName = conversation.frameworkName {
                    Text(frameworkName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.primaryAccent.opacity(0.1))
                        .cornerRadius(4)
                }
            }

            // Show matching content preview if search is active
            if !searchQuery.isEmpty, let preview = getMatchingPreview() {
                highlightedText(preview, searchText: searchQuery, isTitle: false)
                    .lineLimit(2)
            }

            HStack {
                Text(conversation.summary)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text(relativeDate(conversation.updatedAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // Get preview of matching content
    private func getMatchingPreview() -> String? {
        // Skip if title already matches
        if conversation.title.localizedCaseInsensitiveContains(searchQuery) {
            return nil
        }

        // Search in messages
        for message in conversation.messages {
            if message.content.localizedCaseInsensitiveContains(searchQuery) {
                return createPreview(from: message.content, searchText: searchQuery)
            }
        }

        return nil
    }

    // Create preview with context around search term
    private func createPreview(from text: String, searchText: String) -> String {
        guard let range = text.range(of: searchText, options: .caseInsensitive) else {
            return String(text.prefix(100))
        }

        let beforeContext = 30
        let afterContext = 30

        let startIndex = text.distance(from: text.startIndex, to: range.lowerBound)
        let previewStart = max(0, startIndex - beforeContext)
        let previewEnd = min(text.count, startIndex + searchText.count + afterContext)

        let start = text.index(text.startIndex, offsetBy: previewStart)
        let end = text.index(text.startIndex, offsetBy: previewEnd)

        var preview = String(text[start..<end])

        if previewStart > 0 {
            preview = "..." + preview
        }
        if previewEnd < text.count {
            preview = preview + "..."
        }

        return preview
    }

    // Highlighted text view
    private func highlightedText(_ text: String, searchText: String, isTitle: Bool) -> Text {
        guard let range = text.range(of: searchText, options: .caseInsensitive) else {
            return Text(text)
                .font(isTitle ? .headline : .subheadline)
                .foregroundColor(isTitle ? .primary : .secondary)
        }

        let beforeText = String(text[..<range.lowerBound])
        let matchText = String(text[range])
        let afterText = String(text[range.upperBound...])

        return Text(beforeText)
            .font(isTitle ? .headline : .subheadline)
            .foregroundColor(isTitle ? .primary : .secondary)
        +
        Text(matchText)
            .font(isTitle ? .headline : .subheadline)
            .bold()
            .foregroundColor(.orange)
        +
        Text(afterText)
            .font(isTitle ? .headline : .subheadline)
            .foregroundColor(isTitle ? .primary : .secondary)
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
