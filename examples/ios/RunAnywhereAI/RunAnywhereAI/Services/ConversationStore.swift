import Foundation
import SwiftUI

// MARK: - Conversation Store

@MainActor
class ConversationStore: ObservableObject {
    static let shared = ConversationStore()
    
    @Published var conversations: [Conversation] = []
    @Published var currentConversation: Conversation?
    
    private let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    private let conversationsDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private init() {
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
            modelInfo: nil,
            framework: nil
        )
        
        conversations.insert(conversation, at: 0)
        currentConversation = conversation
        saveConversation(conversation)
        
        return conversation
    }
    
    func updateConversation(_ conversation: Conversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            var updated = conversation
            updated.updatedAt = Date()
            conversations[index] = updated
            
            if currentConversation?.id == conversation.id {
                currentConversation = updated
            }
            
            saveConversation(updated)
        }
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
        
        // Auto-generate title from first user message if needed
        if updated.title == "New Chat" && message.role == .user && !message.content.isEmpty {
            updated.title = generateTitle(from: message.content)
        }
        
        updateConversation(updated)
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
            
            // Set current conversation to the most recent
            currentConversation = conversations.first
            
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
    var modelInfo: ModelInfo?
    var framework: LLMFramework?
    
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

// MARK: - Conversation List View

struct ConversationListView: View {
    @StateObject private var store = ConversationStore.shared
    @State private var searchQuery = ""
    @State private var showingDeleteConfirmation = false
    @State private var conversationToDelete: Conversation?
    @Environment(\.dismiss) private var dismiss
    
    var filteredConversations: [Conversation] {
        store.searchConversations(query: searchQuery)
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(filteredConversations) { conversation in
                    ConversationRow(conversation: conversation)
                        .onTapGesture {
                            store.currentConversation = conversation
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
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        _ = store.createConversation()
                        dismiss()
                    }) {
                        Image(systemName: "plus")
                    }
                }
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
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conversation: Conversation
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(conversation.title)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                if let framework = conversation.framework {
                    Text(framework.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            
            Text(conversation.lastMessagePreview)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
            
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
    
    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}