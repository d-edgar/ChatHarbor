import Foundation
import SwiftData

@main
struct DecisionNotesSmoke {
    @MainActor static func main() throws {
        let storeURL = FileManager.default.temporaryDirectory.appendingPathComponent("chatharbor-test-\(UUID().uuidString).store")
        let schema = Schema([BrainstormSession.self, BrainstormEntry.self])
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        let id: UUID
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            let session = BrainstormSession(topic: "Choose a prototype")
            precondition(session.decisionNotes == nil && session.outcomeNotes == nil)
            session.shortlist = "Option A\nOption B"
            session.decisionNotes = "Test option A because it is reversible."
            session.outcomeNotes = "Three users completed the task."
            session.decisionReviewedAt = Date()
            id = session.id
            context.insert(session)
            try context.save()
        }
        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        let sessions = try ModelContext(reopened).fetch(FetchDescriptor<BrainstormSession>())
        let restored = sessions.first { $0.id == id }!
        precondition(restored.shortlist == "Option A\nOption B")
        precondition(restored.decisionNotes == "Test option A because it is reversible.")
        precondition(restored.outcomeNotes == "Three users completed the task.")
        precondition(restored.decisionReviewedAt != nil)
        print("PASS: shortlist, decision notes, outcomes, and review timestamp survive store reopening")
    }
}
