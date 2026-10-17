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
        return ChatResult(content: reply, tokenCount: 2, inputTokenCount: 3, durationMs: 10,
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
        precondition(session.qaMessages.count == 1 && session.qaMessages[0].content == "Question for A")
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

        precondition(providers.costForMessage(modelId: "custom:gpt-4o", inputTokens: 10, outputTokens: 10) == nil)
        precondition(providers.costForMessage(modelId: "openai:unknown", inputTokens: 10, outputTokens: 10) == nil)
        precondition(providers.costForMessage(modelId: "ollama:model", inputTokens: 10, outputTokens: 10) == 0)
        for method in BrainstormMethod.allCases {
            let phases = method.phases
            precondition(phases.firstIndex(of: .disagreement)! < phases.firstIndex(of: .synthesis)!)
        }
        print("PASS: framing feedback, Round Robin, shortlist, disagreement pass, exports, session isolation, cancellation, and pricing")
    }
}
