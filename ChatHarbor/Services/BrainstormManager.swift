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

    /// Throttle streaming UI updates to ~30fps to avoid re-render storms
    private var streamingBuffer: String = ""
    private var lastStreamFlush: Date = .distantPast
    private var streamFlushTask: Task<Void, Never>?
    private let streamFlushInterval: TimeInterval = 0.033  // ~30fps

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
        resetStreamingBuffer()
        if let entry = currentEntry {
            entry.isStreaming = false
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
            flushStreamingBuffer()
        } else if streamFlushTask == nil {
            streamFlushTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(self?.streamFlushInterval ?? 0.033 * 1_000_000_000))
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
            flushQAStreamingBuffer()
        } else if qaStreamFlushTask == nil {
            qaStreamFlushTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(self?.streamFlushInterval ?? 0.033 * 1_000_000_000))
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
                Task { @MainActor in
                    self?.appendStreamingToken(token)
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

        resetStreamingBuffer()
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

    /// Export the brainstorm as a styled HTML string suitable for PDF rendering
    func exportToHTML(_ session: BrainstormSession) -> String {
        let md = exportToMarkdown(session)
        return convertMarkdownToStyledHTML(md, title: session.title)
    }

    /// Convert a markdown string to a clean, print-friendly HTML document
    private func convertMarkdownToStyledHTML(_ markdown: String, title: String) -> String {
        // Simple markdown → HTML conversion (handles headers, bold, lists, paragraphs, hr)
        var html = markdown

        // Escape HTML entities first (preserve markdown syntax)
        // Skip this since our markdown doesn't have raw HTML

        // Convert headers (must process ### before ## before #)
        let headerPatterns: [(pattern: String, tag: String)] = [
            ("^### (.+)$", "h3"),
            ("^## (.+)$", "h2"),
            ("^# (.+)$", "h1")
        ]
        for (pattern, tag) in headerPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) {
                html = regex.stringByReplacingMatches(
                    in: html, range: NSRange(html.startIndex..., in: html),
                    withTemplate: "<\(tag)>$1</\(tag)>"
                )
            }
        }

        // Bold: **text**
        if let boldRegex = try? NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*") {
            html = boldRegex.stringByReplacingMatches(
                in: html, range: NSRange(html.startIndex..., in: html),
                withTemplate: "<strong>$1</strong>"
            )
        }

        // Italic: *text* (single asterisks not preceded/followed by another asterisk)
        if let italicRegex = try? NSRegularExpression(pattern: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)") {
            html = italicRegex.stringByReplacingMatches(
                in: html, range: NSRange(html.startIndex..., in: html),
                withTemplate: "<em>$1</em>"
            )
        }

        // Unordered list items: - text
        if let listRegex = try? NSRegularExpression(pattern: "^- (.+)$", options: .anchorsMatchLines) {
            html = listRegex.stringByReplacingMatches(
                in: html, range: NSRange(html.startIndex..., in: html),
                withTemplate: "<li>$1</li>"
            )
        }
        // Wrap consecutive <li> items in <ul>
        if let ulRegex = try? NSRegularExpression(pattern: "(<li>.+</li>\n?)+", options: .dotMatchesLineSeparators) {
            let matches = ulRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            for match in matches.reversed() {
                if let range = Range(match.range, in: html) {
                    let listContent = String(html[range])
                    html.replaceSubrange(range, with: "<ul>\(listContent)</ul>")
                }
            }
        }

        // Numbered list items: 1. text
        if let olRegex = try? NSRegularExpression(pattern: "^\\d+\\. (.+)$", options: .anchorsMatchLines) {
            html = olRegex.stringByReplacingMatches(
                in: html, range: NSRange(html.startIndex..., in: html),
                withTemplate: "<li>$1</li>"
            )
        }

        // Horizontal rules: ---
        if let hrRegex = try? NSRegularExpression(pattern: "^---+$", options: .anchorsMatchLines) {
            html = hrRegex.stringByReplacingMatches(
                in: html, range: NSRange(html.startIndex..., in: html),
                withTemplate: "<hr>"
            )
        }

        // Wrap remaining plain-text lines in <p> tags (lines that aren't already wrapped)
        let lines = html.components(separatedBy: "\n")
        var processedLines: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                processedLines.append("")
            } else if trimmed.hasPrefix("<h") || trimmed.hasPrefix("<ul") || trimmed.hasPrefix("<li")
                        || trimmed.hasPrefix("</ul") || trimmed.hasPrefix("<hr") || trimmed.hasPrefix("<ol")
                        || trimmed.hasPrefix("</ol") {
                processedLines.append(line)
            } else {
                processedLines.append("<p>\(line)</p>")
            }
        }
        html = processedLines.joined(separator: "\n")

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>\(title)</title>
        <style>
            @page { margin: 0.75in; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
                font-size: 12px;
                line-height: 1.6;
                color: #1d1d1f;
                max-width: 100%;
                padding: 0;
            }
            h1 {
                font-size: 22px;
                font-weight: 700;
                border-bottom: 2px solid #0071e3;
                padding-bottom: 8px;
                margin-top: 0;
                color: #1d1d1f;
            }
            h2 {
                font-size: 16px;
                font-weight: 600;
                color: #0071e3;
                margin-top: 24px;
                margin-bottom: 8px;
            }
            h3 {
                font-size: 14px;
                font-weight: 600;
                color: #1d1d1f;
                margin-top: 16px;
                margin-bottom: 6px;
            }
            p { margin: 6px 0; }
            em { color: #6e6e73; }
            ul, ol { padding-left: 20px; margin: 8px 0; }
            li { margin: 3px 0; }
            strong { color: #1d1d1f; }
            hr {
                border: none;
                border-top: 1px solid #d2d2d7;
                margin: 24px 0;
            }
        </style>
        </head>
        <body>
        \(html)
        </body>
        </html>
        """
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
        try? context.save()
        selectedSessionId = newSession.id
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
        try? context.save()
        selectedSessionId = newSession.id
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

    /// Check if a session has Q&A conversation history
    func hasQAHistory(for session: BrainstormSession) -> Bool {
        return session.hasQAConversation
    }

    /// Overload that takes a sessionId — checks the active session if it matches
    func hasQAHistory(for sessionId: UUID) -> Bool {
        if qaSession?.id == sessionId && !qaMessages.isEmpty {
            return true
        }
        // Can't check SwiftData without the session object from here,
        // but the sidebar passes the session object directly
        return false
    }

    /// Enter Q&A mode for a completed session
    func enterQAMode(session: BrainstormSession, modelId: String, context: ModelContext? = nil) {
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
        currentTask?.cancel()
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
                qualifiedModelId: msg.role == .assistant ? qaModelId : nil,
                tokenCount: msg.tokenCount,
                durationMs: msg.durationMs
            )
        }
        session.qaModelId = qaModelId
        session.updatedAt = Date()
        try? qaContext?.save()
    }

    /// Send a Q&A message about the brainstorm session
    func sendQAMessage(_ text: String, session: BrainstormSession) {
        guard let modelId = qaModelId, !isQAStreaming else { return }

        // Add user message
        qaMessages.append(BrainstormQAMessage(role: .user, content: text))

        // Build the full context: system prompt + session transcript + conversation history
        let transcript = exportToMarkdown(session)
        let systemPrompt = """
        You are a helpful assistant analyzing a brainstorm session that was conducted in ChatHarbor. \
        Below is the full transcript of the session. The user will ask questions about the ideas, \
        the participants' contributions, patterns in the discussion, or request further development \
        of specific ideas. Answer based on the session content. Be specific — reference which role \
        or model said what when relevant.

        ## Full Session Transcript

        \(transcript)
        """

        var messages: [ChatMessage] = [
            ChatMessage(role: .system, content: systemPrompt)
        ]

        // Add conversation history
        for msg in qaMessages {
            messages.append(ChatMessage(
                role: msg.role == .user ? .user : .assistant,
                content: msg.content
            ))
        }

        isQAStreaming = true
        resetQAStreamingBuffer()

        currentTask = Task {
            do {
                let result = try await providers.chat(
                    qualifiedModelId: modelId,
                    messages: messages,
                    parameters: ChatParameters(temperature: 0.7, maxTokens: 2048)
                ) { [weak self] token in
                    Task { @MainActor in
                        self?.appendQAStreamingToken(token)
                    }
                }

                // Flush any remaining buffered content before reading
                flushQAStreamingBuffer()
                let response = qaStreamingContent
                qaMessages.append(BrainstormQAMessage(
                    role: .assistant,
                    content: response,
                    tokenCount: result.tokenCount,
                    durationMs: result.durationMs
                ))
            } catch {
                if !Task.isCancelled {
                    qaMessages.append(BrainstormQAMessage(
                        role: .assistant,
                        content: "Error: \(error.localizedDescription)"
                    ))
                }
            }

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
    var durationMs: Double?

    enum QARole {
        case user
        case assistant
    }
}
