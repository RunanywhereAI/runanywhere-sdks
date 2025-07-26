import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Export Format

enum ExportFormat: String, CaseIterable {
    case markdown = "Markdown"
    case json = "JSON"
    case text = "Plain Text"
    case csv = "CSV"
    
    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .json: return "json"
        case .text: return "txt"
        case .csv: return "csv"
        }
    }
    
    var contentType: UTType {
        switch self {
        case .markdown: return .text
        case .json: return .json
        case .text: return .plainText
        case .csv: return .commaSeparatedText
        }
    }
}

// MARK: - Conversation Exporter

struct ConversationExporter {
    
    static func exportConversation(_ conversation: Conversation, format: ExportFormat) -> Data? {
        switch format {
        case .markdown:
            return exportAsMarkdown(conversation)
        case .json:
            return exportAsJSON(conversation)
        case .text:
            return exportAsPlainText(conversation)
        case .csv:
            return exportAsCSV(conversation)
        }
    }
    
    static func exportConversations(_ conversations: [Conversation], format: ExportFormat) -> Data? {
        switch format {
        case .markdown:
            return exportMultipleAsMarkdown(conversations)
        case .json:
            return exportMultipleAsJSON(conversations)
        case .text:
            return exportMultipleAsPlainText(conversations)
        case .csv:
            return exportMultipleAsCSV(conversations)
        }
    }
    
    // MARK: - Markdown Export
    
    private static func exportAsMarkdown(_ conversation: Conversation) -> Data? {
        var markdown = "# \(conversation.title)\n\n"
        markdown += "**Created:** \(formatDate(conversation.createdAt))\n"
        markdown += "**Updated:** \(formatDate(conversation.updatedAt))\n"
        
        if let model = conversation.modelInfo {
            markdown += "**Model:** \(model.name)\n"
        }
        if let framework = conversation.framework {
            markdown += "**Framework:** \(framework.displayName)\n"
        }
        
        markdown += "\n---\n\n"
        
        for message in conversation.messages {
            let roleEmoji = message.role == .user ? "👤" : "🤖"
            let roleLabel = message.role == .user ? "User" : "Assistant"
            
            markdown += "### \(roleEmoji) \(roleLabel)\n"
            markdown += "_\(formatTime(message.timestamp))_\n\n"
            markdown += "\(message.content)\n\n"
        }
        
        return markdown.data(using: .utf8)
    }
    
    private static func exportMultipleAsMarkdown(_ conversations: [Conversation]) -> Data? {
        var markdown = "# Exported Conversations\n\n"
        markdown += "**Export Date:** \(formatDate(Date()))\n"
        markdown += "**Total Conversations:** \(conversations.count)\n\n"
        markdown += "---\n\n"
        
        for (index, conversation) in conversations.enumerated() {
            if let conversationMarkdown = exportAsMarkdown(conversation),
               let conversationString = String(data: conversationMarkdown, encoding: .utf8) {
                markdown += conversationString
                if index < conversations.count - 1 {
                    markdown += "\n\n———\n\n"
                }
            }
        }
        
        return markdown.data(using: .utf8)
    }
    
    // MARK: - JSON Export
    
    private static func exportAsJSON(_ conversation: Conversation) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        do {
            return try encoder.encode(conversation)
        } catch {
            print("Failed to encode conversation: \(error)")
            return nil
        }
    }
    
    private static func exportMultipleAsJSON(_ conversations: [Conversation]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let exportData = [
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "version": "1.0",
            "conversations": conversations
        ] as [String : Any]
        
        do {
            return try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
        } catch {
            print("Failed to encode conversations: \(error)")
            return nil
        }
    }
    
    // MARK: - Plain Text Export
    
    private static func exportAsPlainText(_ conversation: Conversation) -> Data? {
        var text = "\(conversation.title)\n"
        text += String(repeating: "=", count: conversation.title.count) + "\n\n"
        text += "Created: \(formatDate(conversation.createdAt))\n"
        text += "Updated: \(formatDate(conversation.updatedAt))\n\n"
        
        for message in conversation.messages {
            let role = message.role == .user ? "USER" : "ASSISTANT"
            text += "[\(role) - \(formatTime(message.timestamp))]\n"
            text += "\(message.content)\n\n"
        }
        
        return text.data(using: .utf8)
    }
    
    private static func exportMultipleAsPlainText(_ conversations: [Conversation]) -> Data? {
        var text = "EXPORTED CONVERSATIONS\n"
        text += "=====================\n\n"
        text += "Export Date: \(formatDate(Date()))\n"
        text += "Total: \(conversations.count) conversations\n\n"
        text += String(repeating: "-", count: 50) + "\n\n"
        
        for conversation in conversations {
            if let conversationText = exportAsPlainText(conversation),
               let conversationString = String(data: conversationText, encoding: .utf8) {
                text += conversationString
                text += "\n" + String(repeating: "-", count: 50) + "\n\n"
            }
        }
        
        return text.data(using: .utf8)
    }
    
    // MARK: - CSV Export
    
    private static func exportAsCSV(_ conversation: Conversation) -> Data? {
        var csv = "Timestamp,Role,Content,Conversation Title\n"
        
        for message in conversation.messages {
            let content = message.content
                .replacingOccurrences(of: "\"", with: "\"\"")
                .replacingOccurrences(of: "\n", with: " ")
            
            csv += "\"\(ISO8601DateFormatter().string(from: message.timestamp))\","
            csv += "\"\(message.role == .user ? "User" : "Assistant")\","
            csv += "\"\(content)\","
            csv += "\"\(conversation.title)\"\n"
        }
        
        return csv.data(using: .utf8)
    }
    
    private static func exportMultipleAsCSV(_ conversations: [Conversation]) -> Data? {
        var csv = "Timestamp,Role,Content,Conversation Title,Conversation ID\n"
        
        for conversation in conversations {
            for message in conversation.messages {
                let content = message.content
                    .replacingOccurrences(of: "\"", with: "\"\"")
                    .replacingOccurrences(of: "\n", with: " ")
                
                csv += "\"\(ISO8601DateFormatter().string(from: message.timestamp))\","
                csv += "\"\(message.role == .user ? "User" : "Assistant")\","
                csv += "\"\(content)\","
                csv += "\"\(conversation.title)\","
                csv += "\"\(conversation.id)\"\n"
            }
        }
        
        return csv.data(using: .utf8)
    }
    
    // MARK: - Helper Functions
    
    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Export View

struct ConversationExportView: View {
    let conversation: Conversation?
    let conversations: [Conversation]
    @State private var selectedFormat: ExportFormat = .markdown
    @State private var isExporting = false
    @State private var exportedFileURL: URL?
    @Environment(\.dismiss) private var dismiss
    
    var isMultipleExport: Bool {
        conversation == nil && !conversations.isEmpty
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Export Info
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                            .font(.largeTitle)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading) {
                            Text(isMultipleExport ? "Export Conversations" : "Export Conversation")
                                .font(.title2)
                                .bold()
                            
                            Text(exportSummary)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                
                // Format Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Export Format")
                        .font(.headline)
                    
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        HStack {
                            Image(systemName: selectedFormat == format ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(format.rawValue)
                                    .font(.body)
                                
                                Text(formatDescription(format))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedFormat = format
                        }
                    }
                }
                .padding()
                
                Spacer()
                
                // Export Button
                Button(action: exportConversation) {
                    HStack {
                        if isExporting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Text("Export")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isExporting)
            }
            .padding()
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $exportedFileURL) { url in
                ShareSheet(items: [url])
            }
        }
    }
    
    private var exportSummary: String {
        if isMultipleExport {
            return "\(conversations.count) conversations"
        } else if let conversation = conversation {
            return "\(conversation.messages.count) messages"
        } else {
            return "No conversation selected"
        }
    }
    
    private func formatDescription(_ format: ExportFormat) -> String {
        switch format {
        case .markdown:
            return "Rich text with formatting"
        case .json:
            return "Structured data for developers"
        case .text:
            return "Simple readable text"
        case .csv:
            return "Spreadsheet compatible"
        }
    }
    
    private func exportConversation() {
        isExporting = true
        
        DispatchQueue.global().async {
            let data: Data?
            let filename: String
            
            if isMultipleExport {
                data = ConversationExporter.exportConversations(conversations, format: selectedFormat)
                filename = "conversations_\(Date().ISO8601Format()).\(selectedFormat.fileExtension)"
            } else if let conversation = conversation {
                data = ConversationExporter.exportConversation(conversation, format: selectedFormat)
                let sanitizedTitle = conversation.title
                    .replacingOccurrences(of: " ", with: "_")
                    .replacingOccurrences(of: "/", with: "-")
                filename = "\(sanitizedTitle).\(selectedFormat.fileExtension)"
            } else {
                data = nil
                filename = ""
            }
            
            guard let exportData = data else {
                DispatchQueue.main.async {
                    isExporting = false
                }
                return
            }
            
            // Save to temporary directory
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            
            do {
                try exportData.write(to: tempURL)
                
                DispatchQueue.main.async {
                    isExporting = false
                    exportedFileURL = tempURL
                }
            } catch {
                print("Export failed: \(error)")
                DispatchQueue.main.async {
                    isExporting = false
                }
            }
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - URL Extension

extension URL: Identifiable {
    public var id: String { absoluteString }
}