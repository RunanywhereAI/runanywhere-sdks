import Foundation
import GRDB

/// Migration to add thinkingPattern column to models table
struct Migration002_AddThinkingPattern {

    static func migrate(_ db: Database) throws {
        // Add thinkingPattern column to models table
        try db.alter(table: "models") { t in
            t.add(column: "thinkingPattern", .blob) // JSON: ThinkingTagPattern
        }
    }
}
