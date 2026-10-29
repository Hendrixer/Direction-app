import Foundation
import GRDB

// Phase 2 (design/spec/specs/editor.md, footage-index.md, agent-timeline.md, looks.md, graphics.md,
// made-media.md). Each area keeps its tables, types and store functions in its own folder.
extension ProjectStore {
    static func ensurePhase2Tables(_ db: Database) throws {
        try ensureRunTables(db)
        try ensureIndexTables(db)
        try ensureLookTables(db)
        try ensureGraphicTables(db)
        try ensureMadeTables(db)
    }
}
