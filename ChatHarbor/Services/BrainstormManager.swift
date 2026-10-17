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
    @Published var currentEntry: BrainstormEntry?
    @Published var streamingContent: String = ""

    /// Whether we're waiting for the user at a checkpoint
    @Published var awaitingUserInput: Bool = false
    @Published var checkpointMessage: String = ""

    let providers: ProviderManager

    @Published var persistenceError: String?
    private var runID = UUID()
    private var currentTask: Task<Void, Never>?

    /// Throttle streaming UI updates to ~30fps to avoid re-render storms
    private var streamingBuffer: String = ""
    private var lastStreamFlush: Date = .distantPast
    private var streamFlushTask: Task<Void, Never>?
    private let streamFlushInterval: TimeInterval = 0.033  // ~30fps

    // MARK: - Init

    init(providers: ProviderManager) {
        self.providers = providers
    }

    /// Keep save failures visible while retaining edits in memory.
    private func safeSave(_ context: ModelContext) {
        do {
            try context.save()
            persistenceError = nil
        } catch {
            persistenceError = "Could not save brainstorm changes: \(error.localizedDescription)"
        }
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
        safeSave(context)
        return session
    }

    /// Delete a session
    func deleteSession(_ session: BrainstormSession, in context: ModelContext) {
        if selectedSessionId == session.id {
            selectSession(nil)
        }
        context.delete(session)
        safeSave(context)
    }

    func selectSession(_ id: UUID?) {
        guard selectedSessionId != id else { return }
        if isQAMode { persistQAMessages() }
        stop()
        selectedSessionId = id
        awaitingUserInput = false
        checkpointMessage = ""
        isQAMode = false
        qaMessages = []
        qaModelId = nil
        qaSession = nil
        qaContext = nil
        resetQAStreamingBuffer()
    }

    func restoreCheckpoint(for session: BrainstormSession) {
        selectSession(session.id)
        guard !isRunning, !isQAMode, session.phase != .setup, session.phase != .complete,
              !session.entries(for: session.phase).isEmpty else { return }
        awaitingUserInput = true
        checkpointMessage = "Review the saved results. Retry any interrupted responses, add direction, or continue."
    }

    func saveNotes(for session: BrainstormSession, context: ModelContext) {
        session.updatedAt = Date()
        safeSave(context)
    }

    // MARK: - Phase Execution

    /// Start or resume the brainstorm from its current phase
    func run(session: BrainstormSession, context: ModelContext) {
        selectSession(session.id)
        guard !isRunning, !isQAStreaming else { return }
        runID = UUID()
        let requestID = runID
        isRunning = true
        awaitingUserInput = false

        currentTask = Task {
            guard runID == requestID, !Task.isCancelled else { return }
            switch session.phase {
            case .setup:
                // Move to framing
                session.phase = .framing
                session.updatedAt = Date()
                safeSave(context)
                await runFraming(session: session, context: context)

            case .framing:
                await runFraming(session: session, context: context)

            case .ideation:
                await runIdeationRound(session: session, context: context)

            case .evaluation:
                await runEvaluation(session: session, context: context)

            case .disagreement:
                await runDisagreement(session: session, context: context)

            case .synthesis:
                await runSynthesis(session: session, context: context)

            case .complete:
                break
            }

            if runID == requestID { isRunning = false }
        }
    }

    /// Stop the current generation
    func stop() {
        runID = UUID()
        currentTask?.cancel()
        currentTask = nil
        isRunning = false
        if isQAStreaming {
            qaMessages.append(BrainstormQAMessage(role: .assistant,
                content: qaStreamingBuffer + "\n[Response interrupted; usage unavailable.]", qualifiedModelId: qaModelId))
            persistQAMessages()
        }
        isQAStreaming = false
        resetStreamingBuffer()
        if let entry = currentEntry {
            entry.isStreaming = false
            entry.error = "Response interrupted. Retry to complete it."
            if let context = entry.modelContext { safeSave(context) }
        }
        currentEntry = nil
    }

    /// Append a token to the streaming buffer and flush to the UI at a throttled rate.
    /// This prevents re-rendering the entire view hierarchy on every single token.
    @MainActor
    private func appendStreamingToken(_ token: String) {
        streamingBuffer += token
        let now = Date()
        if now.timeIntervalSince(lastStreamFlush) >= streamFlushInterval {
            streamFlushTask?.cancel()
            streamFlushTask = nil
            flushStreamingBuffer()
        } else if streamFlushTask == nil {
            streamFlushTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: UInt64((self?.streamFlushInterval ?? 0.033) * 1_000_000_000)) } catch { return }
                self?.flushStreamingBuffer()
                self?.streamFlushTask = nil
            }
        }
    }

    @MainActor
    private func flushStreamingBuffer() {
        guard !streamingBuffer.isEmpty else { return }
        streamingContent = streamingBuffer
        lastStreamFlush = Date()
    }

    @MainActor
    private func resetStreamingBuffer() {
        streamFlushTask?.cancel()
        streamFlushTask = nil
        streamingBuffer = ""
        streamingContent = ""
        lastStreamFlush = .distantPast
    }

    @MainActor
    private func appendQAStreamingToken(_ token: String) {
        qaStreamingBuffer += token
        let now = Date()
        if now.timeIntervalSince(lastQAStreamFlush) >= streamFlushInterval {
            qaStreamFlushTask?.cancel()
            qaStreamFlushTask = nil
            flushQAStreamingBuffer()
        } else if qaStreamFlushTask == nil {
            qaStreamFlushTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: UInt64((self?.streamFlushInterval ?? 0.033) * 1_000_000_000)) } catch { return }
                self?.flushQAStreamingBuffer()
                self?.qaStreamFlushTask = nil
            }
        }
    }

    @MainActor
    private func flushQAStreamingBuffer() {
        guard !qaStreamingBuffer.isEmpty else { return }
        qaStreamingContent = qaStreamingBuffer
        lastQAStreamFlush = Date()
    }

    @MainActor
    private func resetQAStreamingBuffer() {
        qaStreamFlushTask?.cancel()
        qaStreamFlushTask = nil
        qaStreamingBuffer = ""
        qaStreamingContent = ""
        lastQAStreamFlush = .distantPast
    }

    /// Retry a failed entry — clears the error, re-streams the response.
    /// Pass an `alternateModelId` to switch to a different model for this entry.
    func retryFailedEntry(_ entry: BrainstormEntry, session: BrainstormSession, context: ModelContext, alternateModelId: String? = nil) {
        selectSession(session.id)
        guard entry.error != nil, !isRunning, !isQAStreaming else { return }
        runID = UUID()
        let requestID = runID

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
        safeSave(context)

        isRunning = true
        currentEntry = entry

        // Determine the appropriate prompt based on the entry's phase and role
        let systemPrompt: String
        let userMessage: String

        switch entry.phase {
        case .framing:
            systemPrompt = entry.role.framingPrompt
            userMessage = framingMessage(for: session)

        case .ideation:
            systemPrompt = entry.role.ideationPrompt
            userMessage = buildIdeationUserMessage(
                session: session,
                previousIdeas: buildIdeationContext(session: session),
                round: entry.round
            )

        case .evaluation:
            systemPrompt = entry.role.evaluationPrompt
            userMessage = evaluationMessage(for: session)

        case .disagreement:
            systemPrompt = entry.role.disagreementPrompt
            userMessage = buildFullSessionContext(session: session)

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
            guard runID == requestID, !Task.isCancelled else { return }
            await generate(
                entry: entry,
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                modelId: modelId,
                context: context
            )
            if runID == requestID {
                if entry.phase == .framing, entry.error == nil {
                    session.problemStatement = entry.content
                    safeSave(context)
                }
                isRunning = false
            }
        }
    }

    /// User provides input at a checkpoint (or resumable state), then advance
    func submitUserInput(_ text: String, session: BrainstormSession, context: ModelContext) {
        guard selectedSessionId == session.id, !isRunning, !isQAStreaming else { return }
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
        safeSave(context)

        awaitingUserInput = false
        checkpointMessage = ""

        // Continue execution
        run(session: session, context: context)
    }

    /// User approves and advances to next phase
    func advancePhase(session: BrainstormSession, context: ModelContext) {
        guard awaitingUserInput, selectedSessionId == session.id, !isRunning else { return }
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
        safeSave(context)

        if session.phase != .complete {
            run(session: session, context: context)
        } else {
            isRunning = false
        }
    }

    /// Continue ideation with another round
    func continueIdeation(session: BrainstormSession, context: ModelContext) {
        guard awaitingUserInput, selectedSessionId == session.id, session.phase == .ideation else { return }
        awaitingUserInput = false
        checkpointMessage = ""

        session.currentRound += 1
        session.updatedAt = Date()
        safeSave(context)

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
        let userMessage = framingMessage(for: session)

        let entry = BrainstormEntry(
            phase: .framing,
            round: 0,
            role: .facilitator,
            qualifiedModelId: facilitator.qualifiedModelId,
            isStreaming: true
        )
        session.entries.append(entry)
        safeSave(context)
        currentEntry = entry

        await generate(
            entry: entry,
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: facilitator.qualifiedModelId,
            context: context
        )

        // Extract the problem statement from the response
        if !Task.isCancelled, entry.error == nil, !entry.content.isEmpty {
            session.problemStatement = entry.content
            session.updatedAt = Date()
            safeSave(context)
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
                previousIdeas: session.method == .roundRobin ? buildIdeationContext(session: session) : previousIdeas,
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
            safeSave(context)
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

        for participant in evaluators {
            guard !Task.isCancelled else { return }

            let systemPrompt = participant.role.evaluationPrompt
            let userMessage = evaluationMessage(for: session)

            let entry = BrainstormEntry(
                phase: .evaluation,
                round: session.currentRound,
                role: participant.role,
                qualifiedModelId: participant.qualifiedModelId,
                isStreaming: true
            )
            session.entries.append(entry)
            safeSave(context)
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
            message: "Evaluation complete. Review the analysis above, add your thoughts, or advance to the disagreement pass."
        )
    }

    private func runDisagreement(session: BrainstormSession, context: ModelContext) async {
        let transcript = buildFullSessionContext(session: session)
        for participant in session.participants where participant.isEnabled && participant.role.activePhases.contains(.disagreement) {
            guard !Task.isCancelled else { return }
            let entry = BrainstormEntry(phase: .disagreement, round: 0, role: participant.role,
                                       qualifiedModelId: participant.qualifiedModelId, isStreaming: true)
            session.entries.append(entry)
            currentEntry = entry
            safeSave(context)
            await generate(entry: entry, systemPrompt: participant.role.disagreementPrompt,
                           userMessage: transcript, modelId: participant.qualifiedModelId, context: context)
        }
        await pauseForUser(session: session, message: "Review the disagreements and proposed tests, then create the decision brief.")
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
            safeSave(context)
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
            message: "Decision brief complete. Review the options and disagreements, record your decision below, or export the session."
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
        let requestID = runID
        resetStreamingBuffer()

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
                guard let self, self.runID == requestID, !Task.isCancelled else { return }
                self.appendStreamingToken(token)
                entry.content += token
            }

            guard runID == requestID, !Task.isCancelled else { return }
            entry.content = result.content
            entry.isStreaming = false
            entry.tokenCount = result.tokenCount
            entry.inputTokenCount = result.inputTokenCount
            entry.usageData = result.usage.encoded
            entry.durationMs = result.durationMs
            safeSave(context)
        } catch {
            if runID == requestID, !Task.isCancelled {
                entry.isStreaming = false
                entry.error = error.localizedDescription
                safeSave(context)
            }
        }

        if runID == requestID {
            resetStreamingBuffer()
            currentEntry = nil
        }
    }

    // MARK: - Checkpoints

    private func pauseForUser(session: BrainstormSession, message: String) async {
        guard !Task.isCancelled, selectedSessionId == session.id else { return }
        awaitingUserInput = true
        checkpointMessage = message
        isRunning = false
    }

    // MARK: - Context Builders

    func framingMessage(for session: BrainstormSession) -> String {
        let feedback = session.entries(for: .framing).filter(\.isUserInput).map(\.content).joined(separator: "\n\n")
        return "Topic: \(session.topic)\n\nPrevious framing: \(session.problemStatement)\n\nUser feedback:\n\(feedback)\n\nReframe the problem, incorporating the user's constraints and corrections."
    }

    func evaluationMessage(for session: BrainstormSession) -> String {
        let shortlist = session.shortlist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ideas = shortlist.isEmpty ? buildIdeationContext(session: session) : shortlist
        let direction = session.entries(for: .evaluation).filter(\.isUserInput).map(\.content).joined(separator: "\n")
        let method = session.method == .reverse ? "Invert the sabotage ideas into constructive solutions." : "Evaluate the selected ideas according to your role."
        return "Problem: \(session.problemStatement.isEmpty ? session.topic : session.problemStatement)\n\nIdeas to evaluate:\n\(ideas)\n\nUser direction:\n\(direction)\n\n\(method)"
    }


    // shortcut: excerpts retain the beginning/end, not every detail; add retrieval if long sessions need exact recall.
    static func contextExcerpt(_ text: String) -> String {
        guard text.count > 1600 else { return text }
        return String(text.prefix(800)) + "\n[Middle omitted from model context; full text remains in the report.]\n" + String(text.suffix(800))
    }

    /// Build a summary of all ideas generated so far in ideation
    private func buildIdeationContext(session: BrainstormSession, compact: Bool = true) -> String {
        let ideationEntries = session.entries(for: .ideation).filter { !compact || (!$0.isStreaming && $0.error == nil) }
        if ideationEntries.isEmpty { return "(No ideas yet)" }

        var context = ""
        for entry in ideationEntries {
            let roleName = entry.role.displayName
            let round = entry.round
            if entry.isUserInput {
                context += "### User Input (Round \(round))\n\(entry.content)\n\n"
            } else {
                let content = compact && round < session.currentRound - 1 ? Self.contextExcerpt(entry.content) : entry.content
                context += "### \(roleName) — Round \(round)\n\(content)\n\n"
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
    private func buildFullSessionContext(session: BrainstormSession, compact: Bool = true) -> String {
        var context = "## Problem Statement\n\(session.problemStatement.isEmpty ? session.topic : session.problemStatement)\n\n"

        // Framing
        let framingEntries = session.entries(for: .framing).filter { !compact || (!$0.isStreaming && $0.error == nil) }
        if !framingEntries.isEmpty {
            context += "## Problem Framing\n"
            for entry in framingEntries {
                context += entry.content + "\n\n"
            }
        }

        let synthesis = session.entries(for: .synthesis).filter { !$0.isStreaming && $0.error == nil && !$0.content.isEmpty }
        let useSynthesis = compact && isQAMode && !synthesis.isEmpty
        if useSynthesis {
            context += "## Session Synthesis\n"
            for entry in synthesis {
                context += "### \(entry.role.displayName)\n\(entry.content)\n\n"
            }
            context += "Earlier ideation and evaluation are represented by the synthesis; consult the full report for omitted details.\n\n"
            if let synthesizedAt = synthesis.map(\.createdAt).max() {
                for entry in session.sortedEntries where !entry.isUserInput && !entry.isStreaming && entry.error == nil
                    && [.ideation, .evaluation].contains(entry.phase) && entry.createdAt > synthesizedAt {
                    let content = entry.round < session.currentRound - 1 ? Self.contextExcerpt(entry.content) : entry.content
                    context += "### Added after synthesis — \(entry.role.displayName)\n\(content)\n\n"
                }
            }
            for entry in session.sortedEntries where entry.isUserInput && [.ideation, .evaluation].contains(entry.phase) {
                context += "### User Direction\n\(entry.content)\n\n"
            }
        } else {
            context += "## Ideation\n"
            context += buildIdeationContext(session: session, compact: compact)
        }

        if let shortlist = session.shortlist, !shortlist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            context += "## User Shortlist\nFocus evaluation and recommendations on these ideas:\n\(shortlist)\n\n"
        }

        // Evaluation
        let evalEntries = session.entries(for: .evaluation).filter { !compact || (!$0.isStreaming && $0.error == nil) }
        if !evalEntries.isEmpty && !useSynthesis {
            context += "## Evaluation\n"
            for entry in evalEntries {
                let roleName = entry.role.displayName
                context += "### \(roleName)\n\(entry.content)\n\n"
            }
        }

        let disagreements = session.entries(for: .disagreement).filter { !compact || (!$0.isStreaming && $0.error == nil) }
        if !disagreements.isEmpty {
            context += "## Disagreements and Tests\n"
            for entry in disagreements {
                context += "### \(entry.isUserInput ? "User" : entry.role.displayName)\n\(entry.content)\n\n"
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

        md += buildFullSessionContext(session: session, compact: false)

        // Synthesis
        let synthEntries = session.entries(for: .synthesis)
        if !synthEntries.isEmpty {
            md += "## Synthesis\n"
            for entry in synthEntries {
                let roleName = entry.role.displayName
                md += "### \(roleName)\n\(entry.content)\n\n"
            }
        }

        if let decision = session.decisionNotes, !decision.isEmpty {
            md += "## Your Decision and Reasoning\n\n\(decision)\n\n"
        }
        if let outcome = session.outcomeNotes, !outcome.isEmpty {
            md += "## Outcome and Lessons\n\n\(outcome)\n\n"
        }
        if let reviewedAt = session.decisionReviewedAt {
            md += "*Decision notes updated: \(reviewedAt.formatted(date: .long, time: .shortened))*\n\n"
        }

        let qa = session.qaMessages
        if !qa.isEmpty {
            md += "## Follow-up Q&A\n\n"
            for message in qa {
                md += "### \(message.isUser ? "You" : "Assistant")\n\n\(message.content)\n\n"
            }
        }
        md += "## Usage — Saved Responses\n\n"
        for entry in session.sortedEntries where !entry.isUserInput && !entry.isStreaming {
            md += "- \(entry.phase.rawValue), \(entry.role.displayName): \(entry.usage.summary) · \(entry.usage.details)\n"
        }
        for message in qa where !message.isUser {
            md += "- Q&A: \(message.usage.summary) · \(message.usage.details)\n"
        }
        md += "\nUsage covers saved responses, not a billing ledger of retries. Unreported usage is unavailable.\n\n"
        md += "---\n\n*Generated with ChatHarbor Brainstorm*\n"
        return md
    }

    /// Export the brainstorm as a styled HTML string suitable for PDF rendering
    func exportToHTML(_ session: BrainstormSession) -> String {
        let md = exportToMarkdown(session)
        return BrainstormReport.html(md, title: session.title)
    }

    // MARK: - Rerun

    /// Clone session configuration and start a fresh run immediately
    func rerunSession(
        _ session: BrainstormSession,
        in context: ModelContext
    ) -> BrainstormSession {
        let newSession = BrainstormSession(
            title: "\(session.title) (Rerun)",
            topic: session.topic,
            method: session.method,
            maxRounds: session.maxRounds
        )
        newSession.participants = session.participants
        context.insert(newSession)
        safeSave(context)
        // Kick off immediately
        run(session: newSession, context: context)
        return newSession
    }

    /// Clone session configuration into a new session in setup phase (for tweaking before launch)
    func cloneSessionForSetup(
        _ session: BrainstormSession,
        in context: ModelContext
    ) -> BrainstormSession {
        let newSession = BrainstormSession(
            title: "\(session.title) (Copy)",
            topic: session.topic,
            method: session.method,
            maxRounds: session.maxRounds
        )
        newSession.participants = session.participants
        // Stay in setup so the user can tweak before launching
        context.insert(newSession)
        safeSave(context)
        return newSession
    }

    // MARK: - Post-Brainstorm Q&A

    /// Published state for the Q&A conversation mode
    @Published var qaMessages: [BrainstormQAMessage] = []
    @Published var isQAStreaming: Bool = false
    @Published var qaStreamingContent: String = ""
    private var qaStreamingBuffer: String = ""
    private var lastQAStreamFlush: Date = .distantPast
    private var qaStreamFlushTask: Task<Void, Never>?
    @Published var qaModelId: String?
    @Published var isQAMode: Bool = false
    /// The active Q&A session (kept as a reference for saving)
    private weak var qaSession: BrainstormSession?
    /// ModelContext for persisting Q&A changes
    private var qaContext: ModelContext?

    /// Enter Q&A mode for a completed session
    func enterQAMode(session: BrainstormSession, modelId: String, context: ModelContext? = nil) {
        selectSession(session.id)
        if isQAMode { persistQAMessages() }
        stop()
        qaModelId = modelId
        isQAMode = true
        qaSession = session
        qaContext = context
        // Restore previous Q&A conversation from persisted data
        qaMessages = session.qaMessages.map { stored in
            BrainstormQAMessage(
                role: stored.isUser ? .user : .assistant,
                content: stored.content,
                tokenCount: stored.tokenCount,
                inputTokenCount: stored.inputTokenCount,
                usageData: stored.usage.encoded,
                qualifiedModelId: stored.qualifiedModelId,
                durationMs: stored.durationMs
            )
        }
        // Restore the last model used if none specified
        if session.qaModelId != nil && modelId.isEmpty {
            qaModelId = session.qaModelId
        }
        resetQAStreamingBuffer()
        isQAStreaming = false
    }

    /// Exit Q&A mode (persists conversation to SwiftData)
    func exitQAMode() {
        stop()
        // Save conversation to the session model
        persistQAMessages()
        isQAMode = false
        resetQAStreamingBuffer()
        isQAStreaming = false
    }

    /// Persist current Q&A messages to the session's SwiftData model
    private func persistQAMessages() {
        guard let session = qaSession else { return }
        session.qaMessages = qaMessages.map { msg in
            StoredQAMessage(
                isUser: msg.role == .user,
                content: msg.content,
                qualifiedModelId: msg.qualifiedModelId,
                tokenCount: msg.tokenCount,
                inputTokenCount: msg.inputTokenCount,
                usageData: msg.usage.encoded,
                durationMs: msg.durationMs
            )
        }
        session.qaModelId = qaModelId
        session.updatedAt = Date()
        if let ctx = qaContext {
            safeSave(ctx)
        }
    }

    /// Send a Q&A message about the brainstorm session
    func sendQAMessage(_ text: String, session: BrainstormSession) {
        guard let modelId = qaModelId, !isQAStreaming, selectedSessionId == session.id, qaSession?.id == session.id else { return }
        runID = UUID()
        let requestID = runID

        // Add user message
        qaMessages.append(BrainstormQAMessage(role: .user, content: text))
        persistQAMessages()

        var transcript = buildFullSessionContext(session: session)
        if let decision = session.decisionNotes { transcript += "\n## User Decision\n\(decision)" }
        if let outcome = session.outcomeNotes { transcript += "\n## Outcome\n\(outcome)" }
        let systemPrompt = """
        You are a helpful assistant analyzing a brainstorm session that was conducted in ChatHarbor. \
        Below is condensed context from the session. The user will ask questions about the ideas, \
        the participants' contributions, patterns in the discussion, or request further development \
        of specific ideas. Answer based on the session content. Be specific — reference which role \
        or model said what when relevant. If details are omitted, say so rather than inventing them.

        ## Session Context

        \(transcript)
        """

        var messages: [ChatMessage] = [
            ChatMessage(role: .system, content: systemPrompt)
        ]

        // Add conversation history
        for (index, msg) in qaMessages.enumerated() {
            let olderAnswer = msg.role == .assistant && index < qaMessages.count - 6
            messages.append(ChatMessage(
                role: msg.role == .user ? .user : .assistant,
                content: olderAnswer ? Self.contextExcerpt(msg.content) : msg.content
            ))
        }

        isQAStreaming = true
        resetQAStreamingBuffer()

        currentTask = Task { [self] in
            guard runID == requestID, !Task.isCancelled else { return }
            do {
                let result = try await providers.chat(
                    qualifiedModelId: modelId,
                    messages: messages,
                    parameters: ChatParameters(temperature: 0.7, maxTokens: 2048)
                ) { [weak self] token in
                    guard let self, self.runID == requestID, !Task.isCancelled else { return }
                    self.appendQAStreamingToken(token)
                }

                guard runID == requestID, !Task.isCancelled else { return }
                let response = result.content
                qaMessages.append(BrainstormQAMessage(
                    role: .assistant,
                    content: response,
                    tokenCount: result.tokenCount,
                    inputTokenCount: result.inputTokenCount,
                    usageData: result.usage.encoded,
                    qualifiedModelId: modelId,
                    durationMs: result.durationMs
                ))
            } catch {
                if runID == requestID, !Task.isCancelled {
                    qaMessages.append(BrainstormQAMessage(
                        role: .assistant,
                        content: "Error: \(error.localizedDescription)"
                    ))
                }
            }

            guard runID == requestID else { return }
            resetQAStreamingBuffer()
            isQAStreaming = false

            // Persist conversation to SwiftData
            persistQAMessages()
        }
    }
}

// MARK: - Q&A Message Model

struct BrainstormQAMessage: Identifiable {
    let id: UUID = UUID()
    let role: QARole
    let content: String
    var tokenCount: Int?
    var inputTokenCount: Int?
    var usageData: Data?
    var usage: TokenUsage { TokenUsage.restore(usageData, input: inputTokenCount, output: tokenCount) }
    var qualifiedModelId: String?
    var durationMs: Double?

    enum QARole {
        case user
        case assistant
    }
}
