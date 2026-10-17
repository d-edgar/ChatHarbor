import Foundation
import SwiftData

@MainActor
private final class RecordingProviders: ProviderManager {
    var requests: [[ChatMessage]] = []
    var suspended: CheckedContinuation<Void, Never>?
    var suspendNext = false

    override func chat(qualifiedModelId: String, messages: [ChatMessage], parameters: ChatParameters = .empty,
                       onToken: @escaping (String) -> Void) async throws -> ChatResult {
        requests.append(messages)
        let reply = "reply-\(requests.count)"
        if suspendNext {
            suspendNext = false
            await withCheckedContinuation { suspended = $0 }
        }
        // Deliberately deliver after cancellation to exercise the manager's ownership guard.
        onToken(reply)
        return ChatResult(content: reply, usage: TokenUsage(input: 3, output: 2), durationMs: 10,
                          model: qualifiedModelId, providerId: "test")
    }
}

@main
struct BrainstormRegression {
    @MainActor static func until(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        preconditionFailure("Timed out waiting for the test task")
    }

    @MainActor static func main() async throws {
        let container = try ModelContainer(for: BrainstormSession.self, BrainstormEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let providers = RecordingProviders(ollama: .shared)
        let savedEndpoints = providers.custom.endpoints
        let otherConnected = providers.connectedProviders.filter { $0.providerId != "custom" }.count
        let studio = CustomEndpoint(name: "Studio", baseURL: "http://localhost:1234/v1", isLMStudio: true)
        let secondStudio = CustomEndpoint(name: "Studio 2", baseURL: "http://localhost:1235/v1", isLMStudio: true)
        let otherEndpoint = CustomEndpoint(name: "Other", baseURL: "http://localhost:8080/v1")
        providers.custom.endpoints = [studio, secondStudio, otherEndpoint]
        precondition(providers.connectionGroupCount == 7)
        precondition(providers.connectedGroupCount == otherConnected)
        studio.isConnected = true
        secondStudio.isConnected = true
        precondition(providers.connectedGroupCount == otherConnected + 1)
        otherEndpoint.isConnected = true
        precondition(providers.connectedGroupCount == otherConnected + 2)
        providers.custom.endpoints = savedEndpoints
        print("PASS: connection groups count LM Studio and other servers once each")
        let manager = BrainstormManager(providers: providers)
        let session = BrainstormSession(topic: "Pick a prototype", method: .roundRobin)
        context.insert(session)
        session.participants = [
            BrainstormParticipant(role: .contributor, qualifiedModelId: "test:one"),
            BrainstormParticipant(role: .contributor, qualifiedModelId: "test:two")
        ]
        session.entries.append(BrainstormEntry(phase: .framing, round: 0, role: .facilitator,
                                               content: "Budget must be $500", isUserInput: true))
        precondition(manager.framingMessage(for: session).contains("Budget must be $500"))
        session.phase = .framing
        let failedFraming = BrainstormEntry(phase: .framing, round: 0, role: .facilitator,
                                           qualifiedModelId: "test:one")
        failedFraming.error = "Test failure"
        session.entries.append(failedFraming)
        manager.retryFailedEntry(failedFraming, session: session, context: context)
        try await until { !manager.isRunning }
        precondition(providers.requests.last!.last!.content.contains("Budget must be $500"))
        precondition(session.problemStatement == failedFraming.content)
        providers.requests = []
        session.problemStatement = "Pick a prototype"
        session.phase = .ideation
        session.currentRound = 1
        manager.run(session: session, context: context)
        try await until { !manager.isRunning }
        precondition(providers.requests.count == 2)
        precondition(providers.requests[1].last!.content.contains("reply-1"), "Round Robin must see the prior turn")

        session.shortlist = "Build the small prototype"
        let evaluation = manager.evaluationMessage(for: session)
        precondition(evaluation.contains("Build the small prototype") && !evaluation.contains("reply-1"))
        session.phase = .disagreement
        manager.run(session: session, context: context)
        try await until { !manager.isRunning }
        precondition(session.entries(for: .disagreement).count == 2)
        precondition(providers.requests.last!.first!.content.contains("Do not invent disagreement"))
        precondition(providers.requests.last!.last!.content.contains("Build the small prototype"))
        session.participants = [BrainstormParticipant(role: .facilitator, qualifiedModelId: "test:one")]
        session.phase = .synthesis
        manager.run(session: session, context: context)
        try await until { !manager.isRunning }
        precondition(providers.requests.last!.last!.content.contains("Disagreements and Tests"))
        session.decisionNotes = "Try the prototype"
        session.outcomeNotes = "It worked"
        manager.saveNotes(for: session, context: context)
        let report = manager.exportToMarkdown(session)
        precondition(report.contains("User Shortlist") && report.contains("Disagreements and Tests"))
        precondition(report.contains("Try the prototype") && report.contains("It worked"))

        // Context compaction preserves originals, user direction, shortlist, and dissent.
        let longIdea = String(repeating: "older idea ", count: 200) + "MIDDLE-SENTINEL" + String(repeating: " supporting detail", count: 200)
        let oldEntry = BrainstormEntry(phase: .ideation, round: 1, role: .contributor, content: longIdea)
        session.entries.append(oldEntry)
        session.currentRound = 4
        session.phase = .ideation
        session.participants = [BrainstormParticipant(role: .contributor, qualifiedModelId: "test:one")]
        manager.run(session: session, context: context)
        try await until { !manager.isRunning }
        let compactPrompt = providers.requests.last!.last!.content
        precondition(!compactPrompt.contains("MIDDLE-SENTINEL") && compactPrompt.contains("Middle omitted"))
        precondition(oldEntry.content == longIdea && manager.exportToMarkdown(session).contains("MIDDLE-SENTINEL"))
        session.entries.append(BrainstormEntry(phase: .evaluation, round: 0, role: .contributor,
            content: "Must work offline", isUserInput: true))
        session.entries.append(BrainstormEntry(phase: .disagreement, round: 0, role: .contributor,
            content: "Dissent: test the battery cost"))
        session.qaMessages = (0..<8).map { index in
            StoredQAMessage(isUser: index % 2 == 0,
                content: index == 1 ? longIdea : "qa-\(index)")
        }
        manager.enterQAMode(session: session, modelId: "test:one", context: context)
        manager.sendQAMessage("What should we build?", session: session)
        try await until { !manager.isQAStreaming }
        let qaRequest = providers.requests.last!
        let qaContext = qaRequest.first!.content
        precondition(qaContext.contains("Session Synthesis") && !qaContext.contains("MIDDLE-SENTINEL"))
        precondition(qaContext.contains("Budget must be $500") && qaContext.contains("Must work offline"))
        precondition(qaContext.contains("Build the small prototype") && qaContext.contains("Dissent: test the battery cost"))
        precondition(qaContext.contains("Try the prototype") && qaContext.contains("It worked"))
        precondition(qaRequest[2].content.contains("Middle omitted") && session.qaMessages[1].content == longIdea)
        precondition(qaRequest.last?.content == "What should we build?")
        precondition(session.qaMessages.last?.usage.total == 5)
        manager.exitQAMode()
        session.qaMessages = []

        let other = BrainstormSession(topic: "Another session")
        context.insert(other)
        manager.enterQAMode(session: session, modelId: "test:one", context: context)
        providers.suspendNext = true
        manager.sendQAMessage("Question for A", session: session)
        try await until { providers.suspended != nil }
        manager.selectSession(other.id)
        precondition(!manager.isQAMode && manager.qaMessages.isEmpty && !manager.isQAStreaming)
        manager.enterQAMode(session: other, modelId: "test:two", context: context)
        manager.sendQAMessage("Question for B", session: other)
        try await until { !manager.isQAStreaming }
        let bMessages = manager.qaMessages.map(\.content)
        providers.suspended?.resume()
        providers.suspended = nil
        try await Task.sleep(for: .milliseconds(20))
        precondition(manager.qaMessages.map(\.content) == bMessages, "Cancelled A must not write into B")
        precondition(session.qaMessages.count == 2 && session.qaMessages[0].content == "Question for A")
        precondition(session.qaMessages.last?.usage.total == nil, "Interrupted usage stays unavailable")
        precondition(other.qaMessages.count == 2)
        precondition(other.qaMessages.last?.inputTokenCount == 3)

        // Cancelling before the task even starts must prevent the provider request.
        manager.exitQAMode()
        let previousRequests = providers.requests.count
        other.phase = .framing
        other.participants = session.participants
        manager.run(session: other, context: context)
        manager.selectSession(session.id)
        try await Task.sleep(for: .milliseconds(20))
        precondition(providers.requests.count == previousRequests)

        var receivedCancelledCompare = false
        providers.suspendNext = true
        let comparison = providers.compare(prompt: "Compare", qualifiedModelIds: ["test:one"],
            onSlotUpdate: { _, _ in receivedCancelledCompare = true },
            onSlotComplete: { _, _ in receivedCancelledCompare = true },
            onSlotError: { _, _ in receivedCancelledCompare = true })
        try await until { providers.suspended != nil }
        comparison.forEach { $0.cancel() }
        providers.suspended?.resume()
        providers.suspended = nil
        try await Task.sleep(for: .milliseconds(20))
        precondition(!receivedCancelledCompare)

        precondition(providers.costForMessage(modelId: "custom:gpt-4o", usage: TokenUsage(input: 10, output: 10)) == nil)
        precondition(providers.costForMessage(modelId: "openai:unknown", usage: TokenUsage(input: 10, output: 10)) == nil)
        precondition(providers.costForMessage(modelId: "ollama:model", usage: TokenUsage(input: 10, output: 10)) == 0)
        precondition(providers.costForMessage(modelId: "openai:gpt-4o", usage: TokenUsage()) == nil)
        precondition(providers.costForMessage(modelId: "openai:gpt-4o", usage: TokenUsage(input: 10, output: 10, cachedInput: 5)) == nil)
        precondition(providers.costForMessage(modelId: "openai:gpt-4o", usage: TokenUsage(input: 0, output: 0)) == 0)
        for method in BrainstormMethod.allCases {
            let phases = method.phases
            precondition(phases.firstIndex(of: .disagreement)! < phases.firstIndex(of: .synthesis)!)
        }
        print("PASS: framing feedback, Round Robin, shortlist, disagreement pass, exports, session isolation, cancellation, and pricing")
    }
}
