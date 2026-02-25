//
//  DictationHistory.swift
//  YapRun
//
//  UserDefaults-backed store for recent dictation entries.
//  Shared between iOS and macOS.
//

import Foundation

@MainActor
final class DictationHistory {

    static let shared = DictationHistory()

    private let key = "dictationHistoryEntries"
    private let maxEntries = 50
    private let defaults = UserDefaults.standard

    private(set) var entries: [DictationEntry] = []

    private init() {
        entries = load()
    }

    func append(_ text: String) {
        let entry = DictationEntry(text: text)
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
    }

    func clear() {
        entries = []
        defaults.removeObject(forKey: key)
    }

    // MARK: - Persistence

    private func load() -> [DictationEntry] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([DictationEntry].self, from: data) else {
            return []
        }
        return decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }
}
