import Foundation
import SwiftData

@main
struct DataDeletionRegression {
    @MainActor static func main() throws {
        let now = Date(timeIntervalSince1970: 1000)
        var pause = ChatDeletionPause()
        precondition(!pause.isActive(at: now))
        pause.start(at: now)
        precondition(pause.isActive(at: now.addingTimeInterval(299)))
        precondition(!pause.isActive(at: now.addingTimeInterval(300)))
        precondition(!ChatDeletionPause().isActive(at: now))

        try checkCascades()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let domain = "ChatHarbor.ResetTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: directory)
        }
        let schema = Schema([Harbor.self, Conversation.self, Message.self, Ship.self,
                             ShipConversation.self, ShipMessage.self, BrainstormSession.self, BrainstormEntry.self])
        let url = directory.appendingPathComponent("test.store")
        let configuration = ModelConfiguration(schema: schema, url: url)
        try seed(schema, configuration)
        let untouched = directory.appendingPathComponent("keep.txt")
        try Data("unrelated".utf8).write(to: untouched)
        let cache = directory.appendingPathComponent("cache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("cached".utf8).write(to: cache.appendingPathComponent("response"))
        defaults.set("secret fixture", forKey: "legacyAPIKey")
        var credentialsDeleted = false
        try LocalDataReset.perform(storeURL: url, defaults: defaults, domain: domain, cacheURLs: [cache]) {
            credentialsDeleted = true
        }
        precondition(!credentialsDeleted && FileManager.default.fileExists(atPath: url.path))
        defaults.set(true, forKey: LocalDataReset.pendingKey)
        do {
            try LocalDataReset.perform(storeURL: url, defaults: defaults, domain: domain, cacheURLs: [cache]) {
                throw CocoaError(.fileWriteNoPermission)
            }
            preconditionFailure("Credential failure must abort reset")
        } catch { }
        precondition(defaults.bool(forKey: LocalDataReset.pendingKey))
        precondition(FileManager.default.fileExists(atPath: url.path))
        try LocalDataReset.perform(storeURL: url, defaults: defaults, domain: domain, cacheURLs: [cache]) {
            credentialsDeleted = true
        }
        precondition(credentialsDeleted)
        precondition(defaults.persistentDomain(forName: domain)?.isEmpty != false)
        precondition(!FileManager.default.fileExists(atPath: url.path))
        precondition(!FileManager.default.fileExists(atPath: url.path + "-wal"))
        precondition(!FileManager.default.fileExists(atPath: url.path + "-shm"))
        precondition(!FileManager.default.fileExists(atPath: cache.path))
        try check { try Data(contentsOf: untouched) == Data("unrelated".utf8) }
        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(reopened)
        try check { try context.fetchCount(FetchDescriptor<Harbor>()) == 0 }
        try check { try context.fetchCount(FetchDescriptor<Conversation>()) == 0 }
        try check { try context.fetchCount(FetchDescriptor<Message>()) == 0 }
        try check { try context.fetchCount(FetchDescriptor<Ship>()) == 0 }
        try check { try context.fetchCount(FetchDescriptor<ShipConversation>()) == 0 }
        try check { try context.fetchCount(FetchDescriptor<ShipMessage>()) == 0 }
        try check { try context.fetchCount(FetchDescriptor<BrainstormSession>()) == 0 }
        try check { try context.fetchCount(FetchDescriptor<BrainstormEntry>()) == 0 }
        print("PASS: five-minute expiry, reset isolation, failure recovery, preferences, caches and all persisted models")
    }

    static func check(_ body: () throws -> Bool) throws { let result = try body(); precondition(result) }

    @MainActor static func checkCascades() throws {
        let container = try ModelContainer(for: Conversation.self, Message.self, Ship.self,
            ShipConversation.self, ShipMessage.self, BrainstormSession.self, BrainstormEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let chat = Conversation(title: "Delete")
        chat.messages.append(Message(role: .user, content: "Delete"))
        let fork = Conversation(title: "Keep", forkedFromId: chat.id)
        context.insert(chat)
        context.insert(fork)
        precondition(DataDeletion.delete(chat, in: context))
        try check { try context.fetchCount(FetchDescriptor<Conversation>()) == 1 }
        try check { try context.fetchCount(FetchDescriptor<Message>()) == 0 }
        let ship = Ship(name: "Delete")
        let history = ShipConversation(title: "Delete")
        history.messages.append(ShipMessage(role: .user, content: "Delete"))
        ship.conversations.append(history)
        context.insert(ship)
        precondition(DataDeletion.delete(ship, in: context))
        try check { try context.fetchCount(FetchDescriptor<ShipConversation>()) == 0 }
        try check { try context.fetchCount(FetchDescriptor<ShipMessage>()) == 0 }
        let session = BrainstormSession(topic: "Delete")
        session.entries.append(BrainstormEntry(phase: .ideation, round: 1, role: .wildCard))
        context.insert(session)
        precondition(DataDeletion.delete(session, in: context))
        try check { try context.fetchCount(FetchDescriptor<BrainstormEntry>()) == 0 }
    }

    @MainActor static func seed(_ schema: Schema, _ configuration: ModelConfiguration) throws {
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.insert(Harbor(name: "Test"))
        let chat = Conversation(title: "Test")
        chat.messages.append(Message(role: .user, content: "private"))
        context.insert(chat)
        context.insert(Conversation(title: "Fork", forkedFromId: chat.id))
        let ship = Ship(name: "Test")
        ship.knowledgeText = "private cargo"
        let shipChat = ShipConversation(title: "Test")
        shipChat.messages.append(ShipMessage(role: .user, content: "private"))
        ship.conversations.append(shipChat)
        context.insert(ship)
        let session = BrainstormSession(topic: "private")
        session.entries.append(BrainstormEntry(phase: .ideation, round: 1, role: .wildCard, content: "private"))
        context.insert(session)
        try context.save()
    }
}
