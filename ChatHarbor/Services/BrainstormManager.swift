import Foundation
import Combine
import SwiftUI
import SwiftData

// MARK: - Brainstorm Manager
//
// Orchestrates multi-model brainstorm sessions using various methods
// (Osborn, Six Thinking Hats, Reverse Brainstorm, Round Robin, Custom).
// Manages sequential round-based execution where each model sees the
// accumulated context from previous participants, then waits for user
// input at defined checkpoints.

@MainActor
class BrainstormManager: ObservableObject {

    // MARK: - Published State

    @Published var selectedSessionId: UUID?
    @Published var isRunning: Bool = false
    @Published var isPaused: Bool = false
    @Published var currentEntry: BrainstormEntry?
    @Published var streamingContent: String = ""

    /// Whether we're waiting for the user at a checkpoint
    @Published var awaitingUserInput: Bool = false
    @Published var checkpointMessage: String = ""

    let providers: ProviderManager

    private var currentTask: Task<Void, Never>?

    // MARK: - Init

    init(providers: ProviderManager) {
        self.providers = providers
    }

    // MARK: - Session Lifecycle

    /// Create a new brainstorm session
    func createSession(
        topic: String,
        participants: [BrainstormParticipant],
        maxRounds: Int = 3,
        in context: ModelContext
    ) -> BrainstormSession {
        let session = BrainstormSession(
            title: String(topic.prefix(50)),
            topic: topic,
            maxRounds: maxRounds
        )
        session.participants = participants
        context.insert(session)
        try? context.save()
        selectedSessionId = session.id
        return session
    }

    /// Delete a session
    func deleteSession(_ session: BrainstormSession, in context: ModelContext) {
        if selectedSessionId == session.id {
            selectedSessionId = nil
        }
        context.delete(session)
        try? context.save()
    }

    // MARK: - Phase Execution

    /// Start or resume the brainstorm from its current phase
    func run(session: BrainstormSession, context: ModelContext) {
        guard !isRunning else { return }
        isRunning = true
        awaitingUserInput = false

        currentTask = Task {
            switch session.phase {
            case .setup:
                // Move to framing
                session.phase = .framing
                session.updatedAt = Date()
                try? context.save()
                await runFraming(session: session, context: context)

            case .framing:
                await runFraming(session: session, context: context)

            case .ideation:
                await runIdeationRound(session: session, context: context)

            case .evaluation:
                await runEvaluation(session: session, context: context)

            case .synthesis:
                await runSynthesis(session: session, context: context)

            case .complete:
                break
            }

            isRunning = false
        }
    }

    /// Stop the current generation
    func stop() {
        currentTask?.cancel()
        currentTask = nil
        isRunning = false
        streamingContent = ""
        if let entry = currentEntry {
            entry.isStreaming = false
        }
        currentEntry = nil
    }

    /// Retry a failed entry — clears the error, re-streams the response.
    /// Pass an `alternateModelId` to switch to a different model for this entry.
    func retryFailedEntry(_ entry: BrainstormEntry, session: BrainstormSession, context: ModelContext, alternateModelId: String? = nil) {
        guard entry.error != nil, !isRunning else { return }

        // Use alternate model if provided, otherwise keep the original
        let modelId: String
        if let alt = alternateModelId {
            modelId = alt
            entry.qualifiedModelId = alt
        } else {
            guard let existing = entry.qualifiedModelId else { return }
            modelId = existing
        }

        // Clear the failed state
        entry.error = nil
        entry.content = ""
        entry.isStreaming = true
        try? context.save()

        isRunning = true
        currentEntry = entry

        // Determine the appropriate prompt based on the entry's phase and role
        let systemPrompt: String
        let userMessage: String

        switch entry.phase {
        case .framing:
            systemPrompt = entry.role.framingPrompt
            userMessage = "Here is the brainstorm topic:\n\n\(session.topic)\n\nPlease reframe this as a clear problem statement and identify key dimensions to explore."

        case .ideation:
            systemPrompt = entry.role.ideationPrompt
            userMessage = buildIdeationUserMessage(
                session: session,
                previousIdeas: buildIdeationContext(session: session),
                round: entry.round
            )

        case .evaluation:
            systemPrompt = entry.role.evaluationPrompt
            let allIdeas = buildIdeationContext(session: session)
            userMessage = "## Problem Statement\n\(session.problemStatement)\n\n## All Ideas from Ideation\n\(allIdeas)\n\nPlease evaluate these ideas according to your role."

        case .synthesis:
            systemPrompt = entry.role.synthesisPrompt
            let fullContext = buildFullSessionContext(session: session)
            userMessage = "## Full Brainstorm Session\n\n\(fullContext)\n\nPlease provide your synthesis according to your role."

        default:
            isRunning = false
            currentEntry = nil
            return
        }

        currentTask = Task {
            await generate(
                entry: entry,
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                modelId: modelId,
                context: context
            )
            isRunning = false
        }
    }

    /// User provides input at a checkpoint (or resumable state), then advance
    func submitUserInput(_ text: String, session: BrainstormSession, context: ModelContext) {
        // Record user input as an entry
        let entry = BrainstormEntry(
            phase: session.phase,
            round: session.currentRound,
            role: .facilitator,
            content: text,
            isUserInput: true
        )
        session.entries.append(entry)
        session.updatedAt = Date()
        try? context.save()

        awaitingUserInput = false
        checkpointMessage = ""

        // Continue execution
        run(session: session, context: context)
    }

    /// User approves and advances to next phase
    func advancePhase(session: BrainstormSession, context: ModelContext) {
        guard awaitingUserInput else { return }
        awaitingUserInput = false
        checkpointMessage = ""

        let phases = session.method.phases
        if let currentIndex = phases.firstIndex(of: session.phase),
           currentIndex + 1 < phases.count {
            let nextPhase = phases[currentIndex + 1]
            session.phase = nextPhase
            if nextPhase == .ideation || nextPhase == .evaluation {
                session.currentRound = 1
            }
        } else {
            // Past last phase → complete
            session.phase = .complete
            session.isComplete = true
        }

        session.updatedAt = Date()
        try? context.save()

        if session.phase != .complete {
            run(session: session, context: context)
        } else {
            isRunning = false
        }
    }

    /// Continue ideation with another round
    func continueIdeation(session: BrainstormSession, context: ModelContext) {
        guard awaitingUserInput, session.phase == .ideation else { return }
        awaitingUserInput = false
        checkpointMessage = ""

        session.currentRound += 1
        session.updatedAt = Date()
        try? context.save()

        run(session: session, context: context)
    }

    // MARK: - Framing Phase

    /// Facilitator reframes the topic into a clear problem statement
    private func runFraming(session: BrainstormSession, context: ModelContext) async {
        guard let facilitator = session.participants.first(where: { $0.role == .facilitator && $0.isEnabled }) else {
            await pauseForUser(
                session: session,
                message: "No facilitator assigned. Please assign a model to the Facilitator role."
            )
            return
        }

        let systemPrompt = BrainstormRole.facilitator.framingPrompt
        let userMessage = """
        Here is the brainstorm topic:

        \(session.topic)

        Please reframe this as a clear problem statement and identify key dimensions to explore.
        """

        let entry = BrainstormEntry(
            phase: .framing,
            round: 0,
            role: .facilitator,
            qualifiedModelId: facilitator.qualifiedModelId,
            isStreaming: true
        )
        session.entries.append(entry)
        try? context.save()
        currentEntry = entry

        await generate(
            entry: entry,
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: facilitator.qualifiedModelId,
            context: context
        )

        // Extract the problem statement from the response
        if !entry.content.isEmpty {
            session.problemStatement = entry.content
            session.updatedAt = Date()
            try? context.save()
        }

        // Checkpoint: user approves the problem framing
        await pauseForUser(
            session: session,
            message: "Review the problem framing above. You can provide feedback, or approve to start idea generation."
        )
    }

    // MARK: - Ideation Phase

    /// Run one round of ideation with all active participants
    private func runIdeationRound(session: BrainstormSession, context: ModelContext) async {
        // Filter to participants active in ideation, excluding observer-only roles
        let observerRoles: Set<BrainstormRole> = [.devilsAdvocate, .scribe]
        let activeParticipants = session.participants.filter {
            $0.isEnabled && $0.role.activePhases.contains(.ideation) && !observerRoles.contains($0.role)
        }

        guard !activeParticipants.isEmpty else {
            await pauseForUser(
                session: session,
                message: "No participants assigned for ideation. Please configure roles."
            )
            return
        }

        // Build accumulated context from previous rounds
        let previousIdeas = buildIdeationContext(session: session)

        for participant in activeParticipants {
            guard !Task.isCancelled else { return }

            let systemPrompt = participant.role.ideationPrompt
            let userMessage = buildIdeationUserMessage(
                session: session,
                previousIdeas: previousIdeas,
                round: session.currentRound
            )

            let entry = BrainstormEntry(
                phase: .ideation,
                round: session.currentRound,
                role: participant.role,
                qualifiedModelId: participant.qualifiedModelId,
                isStreaming: true
            )
            session.entries.append(entry)
            try? context.save()
            currentEntry = entry

            await generate(
                entry: entry,
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                modelId: participant.qualifiedModelId,
                context: context
            )
        }

        // Checkpoint: user decides to continue, provide input, or move to evaluation
        if session.currentRound >= session.maxRounds {
            await pauseForUser(
                session: session,
                message: "Round \(session.currentRound) of \(session.maxRounds) complete. You can provide direction, run another round, or advance to evaluation."
            )
        } else {
            await pauseForUser(
                session: session,
                message: "Round \(session.currentRound) of \(session.maxRounds) complete. Add your thoughts, continue to the next round, or skip to evaluation."
            )
        }
    }

    // MARK: - Evaluation Phase

    /// Run evaluation with method-appropriate evaluators
    private func runEvaluation(session: BrainstormSession, context: ModelContext) async {
        let evaluators = session.participants.filter {
            $0.isEnabled && $0.role.activePhases.contains(.evaluation)
        }

        // Collect all ideas from ideation
        let allIdeas = buildIdeationContext(session: session)

        let methodContext: String
        switch session.method {
        case .reverse:
            methodContext = "This is a Reverse Brainstorm. The ideation phase generated ways to make the problem worse. Now flip those into real solutions."
        default:
            methodContext = "Please evaluate these ideas according to your role."
        }

        for participant in evaluators {
            guard !Task.isCancelled else { return }

            let systemPrompt = participant.role.evaluationPrompt
            let userMessage = """
            ## Problem Statement
            \(session.problemStatement)

            ## All Ideas from Ideation
            \(allIdeas)

            \(methodContext)
            """

            let entry = BrainstormEntry(
                phase: .evaluation,
                round: session.currentRound,
                role: participant.role,
                qualifiedModelId: participant.qualifiedModelId,
                isStreaming: true
            )
            session.entries.append(entry)
            try? context.save()
            currentEntry = entry

            await generate(
                entry: entry,
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                modelId: participant.qualifiedModelId,
                context: context
            )
        }

        // Checkpoint: user reviews evaluation before synthesis
        await pauseForUser(
            session: session,
            message: "Evaluation complete. Review the analysis above, add your thoughts, or advance to final synthesis."
        )
    }

    // MARK: - Synthesis Phase

    /// Facilitator and scribe produce final output
    private func runSynthesis(session: BrainstormSession, context: ModelContext) async {
        let synthesizers = session.participants.filter {
            $0.isEnabled && $0.role.activePhases.contains(.synthesis)
        }

        // Build full session context
        let fullContext = buildFullSessionContext(session: session)

        for participant in synthesizers {
            guard !Task.isCancelled else { return }

            let systemPrompt = participant.role.synthesisPrompt
            guard !systemPrompt.isEmpty else { continue }

            let userMessage = """
            ## Full Brainstorm Session

            \(fullContext)

            Please provide your synthesis according to your role.
            """

            let entry = BrainstormEntry(
                phase: .synthesis,
                round: 0,
                role: participant.role,
                qualifiedModelId: participant.qualifiedModelId,
                isStreaming: true
            )
            session.entries.append(entry)
            try? context.save()
            currentEntry = entry

            await generate(
                entry: entry,
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                modelId: participant.qualifiedModelId,
                context: context
            )
        }

        // Checkpoint: session complete
        await pauseForUser(
            session: session,
            message: "Synthesis complete! Review the final output. You can export this session or mark it as complete."
        )
    }

    // MARK: - Core Generation

    /// Send a message to a model and stream the response into an entry
    private func generate(
        entry: BrainstormEntry,
        systemPrompt: String,
        userMessage: String,
        modelId: String,
        context: ModelContext
    ) async {
        streamingContent = ""

        var messages: [ChatMessage] = []
        if !systemPrompt.isEmpty {
            messages.append(ChatMessage(role: .system, content: systemPrompt))
        }
        messages.append(ChatMessage(role: .user, content: userMessage))

        do {
            let result = try await providers.chat(
                qualifiedModelId: modelId,
                messages: messages,
                parameters: ChatParameters(temperature: 0.9, maxTokens: 2048)
            ) { [weak self] token in
                Task { @MainActor in
                    self?.streamingContent += token
                    entry.content += token
                }
            }

            entry.isStreaming = false
            entry.tokenCount = result.tokenCount
            entry.inputTokenCount = result.inputTokenCount
            entry.durationMs = result.durationMs
            try? context.save()
        } catch {
            if !Task.isCancelled {
                entry.isStreaming = false
                entry.error = error.localizedDescription
                try? context.save()
            }
        }

        streamingContent = ""
        currentEntry = nil
    }

    // MARK: - Checkpoints

    private func pauseForUser(session: BrainstormSession, message: String) async {
        awaitingUserInput = true
        checkpointMessage = message
        isRunning = false
    }

    // MARK: - Context Builders

    /// Build a summary of all ideas generated so far in ideation
    private func buildIdeationContext(session: BrainstormSession) -> String {
        let ideationEntries = session.entries(for: .ideation)
        if ideationEntries.isEmpty { return "(No ideas yet)" }

        var context = ""
        for entry in ideationEntries {
            let roleName = entry.role.displayName
            let round = entry.round
            if entry.isUserInput {
                context += "### User Input (Round \(round))\n\(entry.content)\n\n"
            } else {
                context += "### \(roleName) — Round \(round)\n\(entry.content)\n\n"
            }
        }
        return context
    }

    private func buildIdeationUserMessage(session: BrainstormSession, previousIdeas: String, round: Int) -> String {
        var message = """
        ## Problem Statement
        \(session.problemStatement.isEmpty ? session.topic : session.problemStatement)

        """

        if round > 1 || !previousIdeas.contains("(No ideas yet)") {
            message += """
            ## Ideas Generated So Far
            \(previousIdeas)

            Build on these ideas, riff on them, or go in a completely new direction. \
            Remember: no criticism, quantity over quality. Number your ideas.
            """
        } else {
            message += """
            This is Round 1. Generate your initial ideas for this problem. \
            Be bold. Number your ideas. Aim for at least 3-5 distinct ideas.
            """
        }

        // Include any user interjections from the most recent checkpoint
        let userInputs = session.sortedEntries.filter { $0.isUserInput && $0.phase == .ideation }
        if let lastInput = userInputs.last {
            message += "\n\n## Direction from the Session Owner\n\(lastInput.content)"
        }

        return message
    }

    /// Build full session transcript for synthesis
    private func buildFullSessionContext(session: BrainstormSession) -> String {
        var context = "## Problem Statement\n\(session.problemStatement.isEmpty ? session.topic : session.problemStatement)\n\n"

        // Framing
        let framingEntries = session.entries(for: .framing)
        if !framingEntries.isEmpty {
            context += "## Problem Framing\n"
            for entry in framingEntries {
                context += entry.content + "\n\n"
            }
        }

        // Ideation
        context += "## Ideation\n"
        context += buildIdeationContext(session: session)

        // Evaluation
        let evalEntries = session.entries(for: .evaluation)
        if !evalEntries.isEmpty {
            context += "## Evaluation\n"
            for entry in evalEntries {
                let roleName = entry.role.displayName
                context += "### \(roleName)\n\(entry.content)\n\n"
            }
        }

        return context
    }

    // MARK: - Export

    /// Export the full brainstorm session as Markdown
    func exportToMarkdown(_ session: BrainstormSession) -> String {
        var md = "# Brainstorm: \(session.title)\n\n"
        md += "*\(session.createdAt.formatted(date: .long, time: .shortened)) · ChatHarbor · \(session.method.displayName)*\n\n"

        // Participants
        md += "## Participants\n\n"
        for p in session.participants where p.isEnabled {
            let modelInfo = providers.providerInfo(for: p.qualifiedModelId)
            md += "- **\(p.role.displayName)**: \(modelInfo.modelName) (\(modelInfo.providerName))\n"
        }
        md += "\n"

        md += buildFullSessionContext(session: session)

        // Synthesis
        let synthEntries = session.entries(for: .synthesis)
        if !synthEntries.isEmpty {
            md += "## Synthesis\n"
            for entry in synthEntries {
                let roleName = entry.role.displayName
                md += "### \(roleName)\n\(entry.content)\n\n"
            }
        }

        md += "---\n\n*Generated with ChatHarbor Brainstorm*\n"
        return md
    }
}
