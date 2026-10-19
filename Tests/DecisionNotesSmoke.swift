import Foundation
import SwiftData

@main
struct DecisionNotesSmoke {
    @MainActor static func main() throws {
        do {
            let conversation = Conversation()
            conversation.messages.append(Message(role: .user, content: "First message"))
            conversation.updateAutoTitle(enabled: false)
            precondition(conversation.title == "New Conversation", "Disabled auto-title must preserve the title")
            conversation.updateAutoTitle(enabled: true)
            precondition(conversation.title == "First message", "Enabled auto-title must name the first turn")
            conversation.title = "My chosen title"
            conversation.updateAutoTitle(enabled: true)
            precondition(conversation.title == "My chosen title", "Auto-title must preserve manual names")
            conversation.title = "New Conversation"
            conversation.messages.append(Message(role: .user, content: "Later message"))
            conversation.updateAutoTitle(enabled: true)
            precondition(conversation.title == "New Conversation", "Enabling auto-title must not rename existing chats")
        }
        do {
            let conversation = ShipConversation()
            conversation.messages.append(ShipMessage(role: .user, content: "First message"))
            conversation.updateAutoTitle(enabled: false)
            precondition(conversation.title == "New Conversation", "Disabled auto-title must preserve the title")
            conversation.updateAutoTitle(enabled: true)
            precondition(conversation.title == "First message", "Enabled auto-title must name the first turn")
            conversation.title = "My chosen title"
            conversation.updateAutoTitle(enabled: true)
            precondition(conversation.title == "My chosen title", "Auto-title must preserve manual names")
            conversation.title = "New Conversation"
            conversation.messages.append(ShipMessage(role: .user, content: "Later message"))
            conversation.updateAutoTitle(enabled: true)
            precondition(conversation.title == "New Conversation", "Enabling auto-title must not rename existing chats")
        }
        print("PASS: regular and Ship auto-titles honor the setting and preserve existing titles")
        let storeURL = FileManager.default.temporaryDirectory.appendingPathComponent("chatharbor-test-\(UUID().uuidString).store")
        let schema = Schema([BrainstormSession.self, BrainstormEntry.self, Conversation.self, Message.self, Ship.self, ShipConversation.self, ShipMessage.self])
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
            let entry = BrainstormEntry(phase: .ideation, round: 1, role: .wildCard)
            let usage = TokenUsage(input: 100, output: 50, cachedInput: 20, reasoning: 10)
            entry.tokenCount = usage.output
            entry.inputTokenCount = usage.input
            entry.usageData = usage.encoded
            session.entries.append(entry)
            session.qaMessages = [StoredQAMessage(isUser: false, content: "Answer", tokenCount: 4,
                inputTokenCount: 10, usageData: TokenUsage(input: 10, output: 4, isEstimated: true).encoded)]
            id = session.id
            let message = Message(role: .assistant, content: "Chat answer")
            message.usageData = usage.encoded
            context.insert(message)
            let shipMessage = ShipMessage(role: .assistant, content: "Ship answer")
            shipMessage.usageData = usage.encoded
            context.insert(shipMessage)
            context.insert(session)
            try context.save()
        }
        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        let reopenedContext = ModelContext(reopened)
        let sessions = try reopenedContext.fetch(FetchDescriptor<BrainstormSession>())
        let messages = try reopenedContext.fetch(FetchDescriptor<Message>())
        let shipMessages = try reopenedContext.fetch(FetchDescriptor<ShipMessage>())
        precondition(messages.first?.usage.total == 150 && shipMessages.first?.usage.total == 150)
        let restored = sessions.first { $0.id == id }!
        precondition(restored.shortlist == "Option A\nOption B")
        precondition(restored.decisionNotes == "Test option A because it is reversible.")
        precondition(restored.outcomeNotes == "Three users completed the task.")
        precondition(restored.decisionReviewedAt != nil)
        precondition(restored.entries.first?.usage.total == 150)
        precondition(restored.entries.first?.usage.reasoning == 10 && restored.entries.first?.usage.cachedInput == 20)
        precondition(restored.qaMessages.first?.usage.isEstimated == true)
        let legacyQA = try JSONDecoder().decode(StoredQAMessage.self, from: JSONEncoder().encode(
            StoredQAMessage(isUser: false, content: "Legacy", tokenCount: 7, inputTokenCount: 0)))
        precondition(legacyQA.usage.output == 7 && legacyQA.usage.input == nil)
        print("PASS: shortlist, decision notes, outcomes, and review timestamp survive store reopening")
    }
}
