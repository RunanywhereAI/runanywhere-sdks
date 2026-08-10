import Combine
import Foundation
import os.log
import RunAnywhere

// Note: Message, MessageAnalytics and ConversationAnalytics are now in separate model files

// MARK: - Conversation Store

@MainActor
class ConversationStore: ObservableObject {
    static let shared = ConversationStore()

    @Published var conversations: [Conversation] = []
    @Published var currentConversation: Conversation?

    private let documentsDirectory: URL
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "ConversationStore")

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

        // Titling is NOT triggered here. `LLMViewModel.finalizeGeneration` asks
        // for it once, when the turn it owns has finished — and it is the only
        // caller that knows the turn is over. Firing a second request from here
        // meant every reply queued two generations for the same chat, which on
        // the single-generation LLM component is a race by construction.
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

    // MARK: - Smart Titles

    // A chat title is written by the same model that answers, through the same
    // `RunAnywhere.llm` entry point every other generation in this app uses.
    //
    // It used to open its own `FoundationModels.LanguageModelSession` here in
    // the app. That is a second inference client for the one on-device model the
    // SDK already holds a session on, and Apple's Foundation Models will not
    // serve two: the title request never returned, and — because it never
    // returned — every *subsequent* chat turn wedged behind it with no error and
    // no timeout. Reproduced on macOS 26.5: turn one answered in 0.8s, the title
    // request that followed it hung, and turn two hung forever. Selecting a chat
    // whose title was already set (so no title request fired) made turn two
    // answer normally.
    //
    // Routing through the SDK also means a title is no longer an
    // Apple-Intelligence-only feature: whatever model is loaded writes it.

    /// The title request in flight, so a new chat turn can take the model back.
    /// Only one exists at a time — a title is a nicety and the turn the user
    /// just started is not, and the two cannot share one LLM component.
    private var titleTask: Task<Void, Never>?

    /// Give the model back to the chat. Called by the chat view model the moment
    /// it claims a new turn.
    func cancelPendingTitleGeneration() {
        titleTask?.cancel()
        titleTask = nil
    }

    /// Ask the loaded model to name a conversation, if it still has a
    /// placeholder name. Returns once the title has been written or abandoned.
    func generateSmartTitleForConversation(_ conversationId: String) async {
        cancelPendingTitleGeneration()
        let task: Task<Void, Never> = Task { @MainActor [weak self] in
            await self?.writeSmartTitle(for: conversationId)
        }
        titleTask = task
        await task.value
        if titleTask == task { titleTask = nil }
    }

    private func writeSmartTitle(for conversationId: String) async {
        guard let conversation = conversations.first(where: { $0.id == conversationId }) else { return }

        // Only ever replace a placeholder: "New Chat", or the deterministic
        // first-line title `addMessage` writes. A name the user typed, or one a
        // model already produced, is left alone.
        let firstUserMessage = conversation.messages.first { $0.role == .user }
        let fallbackTitle = firstUserMessage.map { generateTitle(from: $0.content) } ?? "New Chat"
        guard conversation.title == "New Chat" || conversation.title == fallbackTitle else { return }

        let transcript = conversation.messages
            .prefix(4)
            .map { "\($0.role == .user ? "User" : "Assistant"): \($0.content.prefix(200))" }
            .joined(separator: "\n")
        guard !transcript.isEmpty else { return }

        var options = LlmOptions()
        // A title is five words. Anything past this is the model ignoring the
        // instruction, and capping it keeps the request off the user's next turn.
        options.maxOutputTokens = 24
        // Low but not zero: at 0 a small model repeats the prompt's first line.
        options.temperature = 0.2
        options.systemPrompt = """
            You name chat conversations. Reply with a title of 2 to 5 words that \
            names the main topic, in the language of the conversation. Output the \
            title and nothing else — no quotes, no punctuation, no explanation.
            """
        // Tools are registered app-wide, and a title request must not trigger a
        // web search. Reasoning off for the same reason: thought tokens here are
        // pure latency on a request nobody is waiting to read.
        options.toolChoice = .none
        options.reasoning = ReasoningOptions(mode: .off)

        logger.debug("Requesting a smart title")
        do {
            let result = try await RunAnywhere.llm.generate(
                prompt: "Name this conversation:\n\n\(transcript)",
                options: options
            )
            guard !Task.isCancelled else { return }
            let title = Self.sanitizedTitle(result.text)
            if title.isEmpty {
                // The raw text is model output about the user's own conversation,
                // so it stays private in the log: enough to debug the sanitizer,
                // never enough to leak a chat into a sysdiagnose.
                logger.info("Smart title rejected, keeping the fallback: \(result.text)")
            }
            guard !title.isEmpty,
                  var conversation = conversations.first(where: { $0.id == conversationId }),
                  // A model that just echoes the first line has produced the
                  // fallback again; writing it stamps `updatedAt` and reorders
                  // the sidebar for no change the reader can see.
                  conversation.title != title else { return }
            conversation.title = title
            updateConversation(conversation)
            logger.debug("Smart title written")
        } catch {
            // Busy, cancelled, or no model loaded — the deterministic title
            // already on the row stays. Logged and not surfaced: nothing about a
            // chat's name is worth interrupting the reader for, but a feature
            // that silently never fires is one nobody can debug either.
            logger.info("Smart title skipped: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Reduce model output to something that fits a sidebar row, or `""` when it
    /// cannot be reduced to one.
    ///
    /// Small on-device models do not answer "name this conversation" with a
    /// title. Measured against Apple's built-in model, they answer with a
    /// sentence around one — `Sure! A good title would be "Capital of France".`
    /// — or with a `Title:` preamble, or with a Markdown heading. Every one of
    /// those contains the answer; a strict length check threw all three away and
    /// the feature never fired once. So the wrappers are peeled in the order
    /// they actually occur, and only genuinely title-less output is rejected.
    private static func sanitizedTitle(_ raw: String) -> String {
        var candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // A quoted span is the model handing over the title inside a sentence,
        // and it is unambiguous wherever it appears — so it wins outright.
        if let quoted = firstQuotedSpan(in: candidate) {
            candidate = quoted
        } else {
            // Otherwise the title is on one line: the first non-empty one, minus
            // any Markdown heading marker or bullet the model decorated it with.
            candidate = candidate
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty } ?? ""
            candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "#*->• \t"))

            candidate = Self.strippingLeadingLabel(from: candidate)
        }

        candidate = candidate
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’*`.,;:"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Still a sentence, not a name. Truncating it would put an ellipsis in
        // the sidebar where a title belongs, and the deterministic first-line
        // title already there is the better of the two. Both a word count and a
        // character count, because the failures look different: an ignored
        // instruction comes back as a clause ("This conversation is about how to
        // clean a bathroom"), and a run-on comes back as one very long line.
        let words = candidate.split(whereSeparator: \.isWhitespace)
        guard !candidate.isEmpty, words.count <= 8, candidate.count <= 48 else { return "" }

        // Only the first character, and only when it is lowercase. A small model
        // often answers in lower case and a sidebar of lowercase rows reads as
        // unfinished; `localizedCapitalized` is the wrong tool because it would
        // also rewrite "iPhone" and "macOS".
        guard let first = candidate.first, first.isLowercase else { return candidate }
        return candidate.replacingCharacters(
            in: candidate.startIndex...candidate.startIndex,
            with: String(first).localizedUppercase
        )
    }

    /// Drop a leading `Title:` / `Name —` style label, keeping the rest.
    ///
    /// Matched on the *last* word before the separator rather than against a
    /// list of whole phrases, because the model rewords the label every few
    /// turns and a phrase list only ever grows: "Title:", "Name:", "Suggested
    /// title:", and — observed verbatim — "Conversation Name**:". Requiring that
    /// last word to be one of a handful of nouns is what keeps a real title
    /// containing a colon ("Swift: generics explained") intact.
    private static func strippingLeadingLabel(from text: String) -> String {
        let labelNouns: Set<String> = ["title", "name", "subject", "topic", "heading"]
        let separators: Set<Character> = [":", "-", "—", "–"]

        guard let separatorIndex = text.prefix(30).firstIndex(where: { separators.contains($0) }) else {
            return text
        }
        let remainder = text[text.index(after: separatorIndex)...]
            .trimmingCharacters(in: .whitespaces)
        guard !remainder.isEmpty else { return text }

        let label = text[..<separatorIndex]
        let words = label.split(whereSeparator: \.isWhitespace)
        guard words.count <= 3,
              let last = words.last?
                  .trimmingCharacters(in: CharacterSet(charactersIn: "*_`"))
                  .lowercased(),
              labelNouns.contains(last) else {
            return text
        }
        return remainder
    }

    /// What the model put in quotes, if it quoted anything.
    ///
    /// The closing quote is optional. A small model asked for a title inside a
    /// 24-token budget routinely runs out mid-answer and returns
    /// `This conversation is named "Cleaning the Bathroom.` — an opening quote,
    /// the title, and no close. Requiring the pair threw that away and let the
    /// whole sentence through as the title instead, which is how the sidebar
    /// ended up with a row reading `This conversation is named "Capital of
    /// France.`
    private static func firstQuotedSpan(in text: String) -> String? {
        let openers: [Character: Character] = ["\"": "\"", "“": "”", "'": "'", "‘": "’"]
        guard let openIndex = text.firstIndex(where: { openers.keys.contains($0) }),
              let closer = openers[text[openIndex]] else { return nil }
        let afterOpen = text.index(after: openIndex)
        guard afterOpen < text.endIndex else { return nil }

        let remainder = text[afterOpen...]
        let span = remainder.firstIndex(of: closer).map { String(remainder[..<$0]) }
            ?? String(remainder)
        // A one-word quote in the middle of a sentence is usually emphasis, not
        // the title; require something title-shaped.
        return span.count >= 3 ? span : nil
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
