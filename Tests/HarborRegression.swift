import Foundation
import SwiftData

@main
struct HarborRegression {
    @MainActor static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([Harbor.self, Conversation.self, Message.self, Ship.self,
                             ShipConversation.self, ShipMessage.self, BrainstormSession.self, BrainstormEntry.self])
        let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("test.store"))
        let workID: UUID
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            let personal = Harbor(name: "Personal", id: Harbor.defaultID)
            let work = Harbor(name: "Work")
            workID = work.id
            context.insert(personal)
            context.insert(work)
            let original = Conversation(title: "Existing chat")
            let fork = Conversation(forkedFromId: original.id)
            let nestedFork = Conversation(forkedFromId: fork.id)
            let unrelated = Conversation(title: "Personal chat")
            let chats = [original, fork, nestedFork, unrelated]
            chats.forEach { context.insert($0) }
            precondition(chats.allSatisfy { Harbor.contains($0.harborID, in: personal.id) })
            precondition(!Harbor.contains(nil, in: work.id))
            let family = nestedFork.forkFamily(in: chats)
            precondition(Set(family.map(\.id)) == Set([original.id, fork.id, nestedFork.id]))
            family.forEach { $0.harborID = work.id }
            let ship = Ship(name: "Work ship")
            ship.harborID = work.id
            let shipChat = ShipConversation(title: "Ship history")
            ship.conversations.append(shipChat)
            context.insert(ship)
            let session = BrainstormSession(topic: "Work ideas")
            session.harborID = work.id
            context.insert(session)
            work.name = "Office"
            try context.save()
        }
        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(reopened)
        let harbors = try context.fetch(FetchDescriptor<Harbor>())
        precondition(harbors.first { $0.id == workID }?.name == "Office")
        let chats = try context.fetch(FetchDescriptor<Conversation>())
        precondition(chats.filter { Harbor.contains($0.harborID, in: workID) }.count == 3)
        precondition(chats.filter { Harbor.contains($0.harborID, in: Harbor.defaultID) }.count == 1)
        let ship = try context.fetch(FetchDescriptor<Ship>()).first!
        precondition(ship.harborID == workID && ship.conversations.first?.title == "Ship history")
        let sessions = try context.fetch(FetchDescriptor<BrainstormSession>())
        precondition(sessions.first?.harborID == workID)
        print("PASS: harbor persistence, legacy membership, chat-family moves, ships and brainstorms")
    }
}
