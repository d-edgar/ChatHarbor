import SwiftUI
import SwiftData
import WebKit
import UniformTypeIdentifiers

// MARK: - Brainstorm View
//
// The main brainstorm session interface. Shows a phase progress bar at top,
// a scrolling timeline of entries from each participant, and a user input
// bar that activates at checkpoints between phases.

struct BrainstormView: View {
    let session: BrainstormSession
    @EnvironmentObject var brainstormManager: BrainstormManager
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var userInput: String = ""
    @State private var showingExport: Bool = false
    @State private var showingQAModelPicker: Bool = false
    @FocusState private var inputFocused: Bool
    @Namespace private var bottomAnchor

    private var accent: Color {
        chatManager.currentTheme.accentColor(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            brainstormHeader

            Divider()

            // MARK: - Phase Progress
            phaseProgressBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

            Divider()

            // MARK: - Session Content
            if session.phase == .setup {
                BrainstormSetupView(session: session)
                    .environmentObject(brainstormManager)
                    .environmentObject(chatManager)
            } else if brainstormManager.isQAMode {
                // Q&A conversation mode
                VStack(spacing: 0) {
                    qaTimeline

                    Divider()

                    qaInputBar
                }
            } else {
                // Timeline + Input
                VStack(spacing: 0) {
                    sessionTimeline

                    Divider()

                    // MARK: - Input Bar
                    inputBar
                }
            }
        }
    }

    // MARK: - Header

    private var brainstormHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 18))
                .foregroundStyle(accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                Text("\(session.method.displayName) · \(session.phase.displayName) · \(session.updatedAt.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Participant badges
            HStack(spacing: -4) {
                ForEach(session.participants.filter(\.isEnabled)) { participant in
                    roleBadge(participant.role)
                }
            }

            // Actions
            if brainstormManager.isRunning {
                Button {
                    brainstormManager.stop()
                } label: {
                    Label("Stop", systemImage: "stop.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }

            Menu {
                Button {
                    showingExport = true
                } label: {
                    Label("Export Report", systemImage: "square.and.arrow.up")
                }

                if session.isComplete || session.phase == .synthesis {
                    Divider()

                    Button {
                        showingQAModelPicker = true
                    } label: {
                        Label("Ask Questions About Session", systemImage: "bubble.left.and.text.bubble.right")
                    }
                    .disabled(brainstormManager.isQAMode)
                }

                if session.phase != .setup {
                    Divider()

                    Button {
                        let newSession = brainstormManager.rerunSession(session, in: modelContext)
                        chatManager.selectedBrainstormId = newSession.id
                    } label: {
                        Label("Rerun Brainstorm", systemImage: "arrow.clockwise")
                    }

                    Button {
                        let newSession = brainstormManager.cloneSessionForSetup(session, in: modelContext)
                        chatManager.selectedBrainstormId = newSession.id
                    } label: {
                        Label("Rerun with Changes", systemImage: "arrow.clockwise.circle")
                    }
                }

                Divider()

                if brainstormManager.isQAMode {
                    Button {
                        brainstormManager.exitQAMode()
                    } label: {
                        Label("Exit Q&A Mode", systemImage: "xmark.circle")
                    }

                    Divider()
                }

                Button("Delete Session", role: .destructive) {
                    brainstormManager.deleteSession(session, in: modelContext)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .sheet(isPresented: $showingExport) {
            ExportSheet(
                markdown: brainstormManager.exportToMarkdown(session),
                html: brainstormManager.exportToHTML(session),
                title: session.title
            )
        }
        .sheet(isPresented: $showingQAModelPicker) {
            QAModelPickerSheet(session: session)
                .environmentObject(brainstormManager)
                .environmentObject(chatManager)
        }
    }

    // MARK: - Phase Progress Bar

    private var phaseProgressBar: some View {
        let phases: [BrainstormPhase] = session.method.phases + [.complete]
        let currentIndex = phases.firstIndex(of: session.phase) ?? 0

        return HStack(spacing: 0) {
            ForEach(phases.indices, id: \.self) { index in
                let phase = phases[index]
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(index <= currentIndex ? accent : Color.gray.opacity(0.2))
                            .frame(width: 24, height: 24)

                        if index < currentIndex {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        } else if index == currentIndex {
                            Image(systemName: phase.icon)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if phase != .complete {
                        Text(phase.displayName)
                            .font(.system(size: 10, weight: index == currentIndex ? .bold : .regular))
                            .foregroundStyle(index <= currentIndex ? .primary : .secondary)
                    }
                }

                if index < phases.count - 1 {
                    Rectangle()
                        .fill(index < currentIndex ? accent : Color.gray.opacity(0.2))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    // MARK: - Session Timeline

    private var sessionTimeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(session.sortedEntries.filter { entry in
                        // Hide the entry currently being streamed — the
                        // streaming indicator below handles its display
                        entry.id != brainstormManager.currentEntry?.id
                    }) { entry in
                        BrainstormEntryCard(
                            entry: entry,
                            accent: accent,
                            statParts: buildStatParts(for: entry),
                            providers: chatManager.providers,
                            onRetry: entry.error != nil ? { alternateModelId in
                                retryEntry(entry, withModel: alternateModelId)
                            } : nil
                        )
                        .id(entry.id)
                    }

                    // Streaming indicator (single view for the active entry)
                    if brainstormManager.isRunning, let current = brainstormManager.currentEntry {
                        streamingIndicator(for: current)
                    }

                    // Checkpoint banner
                    if brainstormManager.awaitingUserInput {
                        checkpointBanner
                    }

                    // Prominent Q&A call-to-action after session completes
                    if (session.isComplete || session.phase == .complete) && !brainstormManager.isQAMode {
                        qaCallToAction
                    }

                    // Bottom anchor for auto-scroll
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(20)
            }
            .onAppear {
                // Scroll to bottom when timeline appears (initial load or returning from Q&A)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: session.entries.count) { _, _ in
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: brainstormManager.isRunning) { _, running in
                if running {
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .onChange(of: brainstormManager.awaitingUserInput) { _, awaiting in
                if awaiting {
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Streaming Indicator

    private func streamingIndicator(for entry: BrainstormEntry) -> some View {
        StreamingEntryView(
            manager: brainstormManager,
            role: entry.role,
            roleColor: roleColor(entry.role)
        )
    }

    // MARK: - Checkpoint Banner

    private var checkpointBanner: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(accent)
                Text("Your Turn")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }

            Text(brainstormManager.checkpointMessage)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            // Session stats
            sessionStats

            HStack(spacing: 8) {
                if session.phase == .ideation {
                    Button {
                        brainstormManager.continueIdeation(session: session, context: modelContext)
                    } label: {
                        Label("Next Round", systemImage: "arrow.forward")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                // Export report (always available at synthesis checkpoint)
                if session.phase == .synthesis || session.phase == .complete {
                    Button {
                        showingExport = true
                    } label: {
                        Label("Export Report", systemImage: "doc.text")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        copyReportToClipboard()
                    } label: {
                        Label("Copy Report", systemImage: "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if session.phase != .complete {
                    Button {
                        brainstormManager.advancePhase(session: session, context: modelContext)
                    } label: {
                        Label(advanceButtonLabel, systemImage: "forward.fill")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .controlSize(.small)
                }

            }

            // Rerun options (compact row)
            if session.isComplete || session.phase == .complete {
                Divider()
                    .padding(.vertical, 4)

                HStack(spacing: 8) {
                    Menu {
                        Button {
                            let newSession = brainstormManager.rerunSession(session, in: modelContext)
                            chatManager.selectedBrainstormId = newSession.id
                        } label: {
                            Label("Rerun Brainstorm", systemImage: "arrow.clockwise")
                        }

                        Button {
                            let newSession = brainstormManager.cloneSessionForSetup(session, in: modelContext)
                            chatManager.selectedBrainstormId = newSession.id
                        } label: {
                            Label("Rerun with Changes", systemImage: "arrow.clockwise.circle")
                        }
                    } label: {
                        Label("Rerun", systemImage: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    Spacer()
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(accent.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Q&A Call-to-Action

    private var qaCallToAction: some View {
        let hasHistory = session.hasQAConversation
        let resumeModelId = session.qaModelId ?? chatManager.providers.allModels.first?.id ?? ""

        return Button {
            if hasHistory && !resumeModelId.isEmpty {
                // Jump straight into Q&A with previous model
                brainstormManager.enterQAMode(session: session, modelId: resumeModelId, context: modelContext)
            } else {
                // No history — show the model picker
                showingQAModelPicker = true
            }
        } label: {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: hasHistory
                          ? "bubble.left.and.text.bubble.right"
                          : "bubble.left.and.text.bubble.right.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.purple)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(hasHistory
                             ? "Resume Q&A Conversation"
                             : "Ask Questions About This Session")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)

                        if hasHistory, let modelId = session.qaModelId {
                            let info = chatManager.providers.providerInfo(for: modelId)
                            let messageCount = session.qaMessages.count
                            Text("Continue chatting with \(info.modelName) · \(messageCount) messages")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        } else {
                            Text("Chat with an AI about the ideas, analysis, and outcomes from this brainstorm.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                    }

                    Spacer()

                    Image(systemName: hasHistory ? "arrow.right" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.purple.opacity(0.6))
                }

                // If there's history, also offer to start fresh with a different model
                if hasHistory {
                    Divider()

                    HStack {
                        Button {
                            showingQAModelPicker = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.bubble")
                                    .font(.system(size: 10))
                                Text("Start New Q&A with Different Model")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(.purple.opacity(0.7))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.purple.opacity(0.25), lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var advanceButtonLabel: String {
        let phases = session.method.phases
        if let currentIndex = phases.firstIndex(of: session.phase),
           currentIndex + 1 < phases.count {
            let next = phases[currentIndex + 1]
            return "Start \(next.displayName)"
        }
        // Last phase in the method or .complete → mark done
        return "Complete"
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 12) {
            // Resume button when session is stuck between phases
            if isResumable {
                Button {
                    brainstormManager.run(session: session, context: modelContext)
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .controlSize(.small)
            }

            TextField(inputPlaceholder, text: $userInput, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($inputFocused)
                .onSubmit {
                    if !NSEvent.modifierFlags.contains(.shift) {
                        submitInput()
                    }
                }
                .font(.body)
                .padding(.vertical, 8)
                .disabled(!brainstormManager.awaitingUserInput && !isResumable && session.phase != .setup)

            Button {
                submitInput()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(canSubmit ? accent : Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    /// Whether the session is in a resumable state (not running, not awaiting input,
    /// but also not complete or in setup)
    private var isResumable: Bool {
        !brainstormManager.isRunning
        && !brainstormManager.awaitingUserInput
        && session.phase != .setup
        && session.phase != .complete
    }

    private var inputPlaceholder: String {
        if brainstormManager.awaitingUserInput {
            return "Add your thoughts or direction…"
        }
        if brainstormManager.isRunning {
            return "Waiting for models to finish…"
        }
        if isResumable {
            return "Type feedback, or tap Resume to continue…"
        }
        return "Session is paused"
    }

    private var canSubmit: Bool {
        let hasText = !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText && (brainstormManager.awaitingUserInput || isResumable)
    }

    /// Summary stats for the session
    private var sessionStats: some View {
        let entries = session.sortedEntries.filter { !$0.isUserInput && $0.error == nil }
        let totalTokens = entries.compactMap(\.tokenCount).reduce(0, +)
        let totalInputTokens = entries.compactMap(\.inputTokenCount).reduce(0, +)
        let totalDuration = entries.compactMap(\.durationMs).reduce(0, +)
        let entryCount = entries.count
        let totalCost = entries.compactMap { entry -> Double? in
            guard let modelId = entry.qualifiedModelId else { return nil }
            return chatManager.providers.costForMessage(
                modelId: modelId,
                inputTokens: entry.inputTokenCount ?? 0,
                outputTokens: entry.tokenCount ?? 0
            )
        }.reduce(0, +)

        return HStack(spacing: 12) {
            if entryCount > 0 {
                Label("\(entryCount) responses", systemImage: "text.bubble")
                Label("\(totalTokens + totalInputTokens) tokens", systemImage: "number")
                if totalDuration > 0 {
                    Label(ChatManager.formatDuration(totalDuration), systemImage: "clock")
                }
                if totalCost > 0 {
                    Label(formatCost(totalCost), systemImage: "dollarsign.circle")
                }
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }

    private func formatCost(_ cost: Double) -> String {
        if cost < 0.001 {
            return String(format: "$%.4f", cost)
        } else if cost < 0.01 {
            return String(format: "$%.3f", cost)
        } else {
            return String(format: "$%.2f", cost)
        }
    }

    private func copyReportToClipboard() {
        let markdown = brainstormManager.exportToMarkdown(session)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    private func retryEntry(_ entry: BrainstormEntry, withModel alternateModelId: String? = nil) {
        brainstormManager.retryFailedEntry(entry, session: session, context: modelContext, alternateModelId: alternateModelId)
    }

    /// Pre-compute stat parts for a brainstorm entry (avoids recalculating in child views)
    private func buildStatParts(for entry: BrainstormEntry) -> [String] {
        var parts: [String] = []
        if let tokens = entry.tokenCount, tokens > 0 {
            parts.append("\(tokens) tok")
        }
        if let tokens = entry.tokenCount, let ms = entry.durationMs,
           tokens > 0, ms > 0 {
            parts.append(String(format: "%.1f tok/s", Double(tokens) / (ms / 1000.0)))
        }
        if let ms = entry.durationMs, ms > 0 {
            parts.append(ChatManager.formatDuration(ms))
        }
        if let modelId = entry.qualifiedModelId,
           let cost = chatManager.providers.costForMessage(
               modelId: modelId,
               inputTokens: entry.inputTokenCount ?? 0,
               outputTokens: entry.tokenCount ?? 0
           ), cost > 0 {
            parts.append(formatCost(cost))
        }
        return parts
    }

    private func submitInput() {
        let text = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if brainstormManager.awaitingUserInput {
            userInput = ""
            brainstormManager.submitUserInput(text, session: session, context: modelContext)
        } else if isResumable {
            // Record user feedback, then resume
            userInput = ""
            brainstormManager.submitUserInput(text, session: session, context: modelContext)
        }
    }

    // MARK: - Q&A Mode Views

    private var qaTimeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    // Q&A mode banner
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .font(.system(size: 14))
                            .foregroundStyle(accent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Q&A Mode")
                                .font(.system(size: 13, weight: .semibold))

                            if let modelId = brainstormManager.qaModelId {
                                let info = chatManager.providers.providerInfo(for: modelId)
                                Text("Chatting with \(info.modelName) about this brainstorm session")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Button {
                            brainstormManager.exitQAMode()
                        } label: {
                            Label("Exit Q&A", systemImage: "xmark.circle")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(accent.opacity(0.2), lineWidth: 1)
                    )

                    // Q&A messages
                    ForEach(brainstormManager.qaMessages) { message in
                        qaMessageCard(message)
                            .id(message.id)
                    }

                    // Streaming indicator
                    if brainstormManager.isQAStreaming {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10))
                                Text("Assistant")
                                    .font(.system(size: 11, weight: .semibold))
                                ProgressView()
                                    .scaleEffect(0.5)
                            }
                            .foregroundStyle(accent)

                            if !brainstormManager.qaStreamingContent.isEmpty {
                                MarkdownText(content: brainstormManager.qaStreamingContent)
                            } else {
                                HStack(spacing: 4) {
                                    ProgressView().scaleEffect(0.6)
                                    Text("Thinking…")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(accent.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(accent.opacity(0.15), lineWidth: 1)
                        )
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("qa-bottom")
                }
                .padding(20)
            }
            .onChange(of: brainstormManager.qaMessages.count) { _, _ in
                withAnimation {
                    proxy.scrollTo("qa-bottom", anchor: .bottom)
                }
            }
            .onChange(of: brainstormManager.qaStreamingContent) { _, _ in
                proxy.scrollTo("qa-bottom", anchor: .bottom)
            }
        }
    }

    private func qaMessageCard(_ message: BrainstormQAMessage) -> some View {
        QAMessageCardView(
            message: message,
            accent: accent,
            qaModelId: brainstormManager.qaModelId,
            providerInfo: brainstormManager.qaModelId.map { chatManager.providers.providerInfo(for: $0) }
        )
    }

    private var qaInputBar: some View {
        VStack(spacing: 0) {
            // Model switcher row
            HStack(spacing: 8) {
                Text("Model:")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Picker("", selection: Binding(
                    get: { brainstormManager.qaModelId ?? "" },
                    set: { brainstormManager.qaModelId = $0 }
                )) {
                    ForEach(chatManager.providers.allModels) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .controlSize(.small)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Input row
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Ask about the brainstorm…", text: $userInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($inputFocused)
                    .onSubmit {
                        if !NSEvent.modifierFlags.contains(.shift) {
                            submitQAInput()
                        }
                    }
                    .font(.body)
                    .padding(.vertical, 8)
                    .disabled(brainstormManager.isQAStreaming)

                Button {
                    submitQAInput()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(canSubmitQA ? accent : Color.gray.opacity(0.3))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canSubmitQA)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(.bar)
    }

    private var canSubmitQA: Bool {
        let hasText = !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText && !brainstormManager.isQAStreaming
    }

    private func submitQAInput() {
        let text = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !brainstormManager.isQAStreaming else { return }
        userInput = ""
        brainstormManager.sendQAMessage(text, session: session)
    }

    // MARK: - Helpers

    private func roleBadge(_ role: BrainstormRole) -> some View {
        Image(systemName: role.icon)
            .font(.system(size: 9))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(roleColor(role), in: Circle())
            .overlay(Circle().stroke(.background, lineWidth: 2))
            .help(role.displayName)
    }

    private func roleColor(_ role: BrainstormRole) -> Color {
        colorForRole(role.color)
    }
}

// MARK: - Streaming Entry View
//
// Isolated view that observes BrainstormManager for streaming content.
// By keeping this separate from the main timeline, token-by-token updates
// only re-render this small view instead of the entire LazyVStack.

struct StreamingEntryView: View {
    @ObservedObject var manager: BrainstormManager
    let role: BrainstormRole
    let roleColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: role.icon)
                    .font(.system(size: 10))
                Text(role.displayName)
                    .font(.system(size: 11, weight: .semibold))
                ProgressView()
                    .scaleEffect(0.5)
            }
            .foregroundStyle(roleColor)

            if !manager.streamingContent.isEmpty {
                Text(manager.streamingContent)
                    .font(.body)
                    .textSelection(.enabled)
            } else {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Thinking…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(roleColor.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(roleColor.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Brainstorm Entry Card

struct BrainstormEntryCard: View {
    let entry: BrainstormEntry
    let accent: Color
    /// Pre-computed stat parts to avoid recalculating on every re-render
    let statParts: [String]
    /// Provider manager for the usage popover (lightweight, not observed)
    let providers: ProviderManager
    /// Retry with an optional different model ID (nil = same model)
    var onRetry: ((String?) -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @State private var copied: Bool = false
    @State private var showUsagePopover: Bool = false

    private var roleColor: Color {
        colorForRole(entry.role.color)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                if entry.isUserInput {
                    Image(systemName: "person.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(accent)
                    Text("You")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                } else {
                    Image(systemName: entry.role.icon)
                        .font(.system(size: 10))
                        .foregroundStyle(roleColor)
                    Text(entry.role.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(roleColor)

                    if let modelId = entry.qualifiedModelId {
                        let info = providers.providerInfo(for: modelId)
                        Text("· \(info.modelName)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Phase + round badge
                HStack(spacing: 4) {
                    Text(entry.phase.displayName)
                        .font(.system(size: 9, weight: .medium))
                    if entry.round > 0 {
                        Text("R\(entry.round)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary.opacity(0.3), in: Capsule())
            }

            // Content
            if let error = entry.error {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let onRetry {
                        HStack(spacing: 8) {
                            // Retry with same model
                            Button {
                                onRetry(nil)
                            } label: {
                                Label("Retry", systemImage: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            // Retry with a different model
                            Menu {
                                let allModels = providers.allModels
                                ForEach(allModels) { model in
                                    Button {
                                        onRetry(model.id)
                                    } label: {
                                        HStack {
                                            Image(systemName: model.isLocal ? "desktopcomputer" : "cloud")
                                            Text(model.displayName)
                                            if model.id == entry.qualifiedModelId {
                                                Text("(current)")
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Label("Try Different Model", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()

                            Spacer()
                        }
                    }
                }
            } else if entry.content.isEmpty && entry.isStreaming {
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.6)
                    Text("Thinking…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                MarkdownText(content: entry.content)
            }

            // Stats pill — clickable, opens usage popover
            if !entry.isStreaming, entry.error == nil, !entry.isUserInput,
               (entry.tokenCount != nil || entry.durationMs != nil) {
                Button {
                    showUsagePopover = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 8))

                        ForEach(Array(statParts.enumerated()), id: \.offset) { index, part in
                            if index > 0 {
                                Text("·")
                            }
                            Text(part)
                        }

                        Image(systemName: "chevron.right")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(roleColor.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(roleColor.opacity(colorScheme == .dark ? 0.08 : 0.06))
                    )
                    .overlay(
                        Capsule()
                            .stroke(roleColor.opacity(0.12), lineWidth: 0.5)
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showUsagePopover, arrowEdge: .bottom) {
                    BrainstormUsagePopoverView(
                        entry: entry,
                        providers: providers,
                        accent: accent
                    )
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            entry.isUserInput
                ? AnyShapeStyle(accent.opacity(0.04))
                : AnyShapeStyle(roleColor.opacity(0.04))
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    entry.isUserInput
                        ? accent.opacity(0.15)
                        : roleColor.opacity(0.1),
                    lineWidth: 1
                )
        )
        .onDisappear {
            // Kill popover when card scrolls off-screen to prevent
            // layout loop / memory leak in LazyVStack
            showUsagePopover = false
        }
        .contextMenu {
            Button {
                copyWithFeedback(entry.content)
            } label: {
                Label(copied ? "Copied!" : "Copy", systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
            }

            Button {
                let plain = entry.content
                    .replacingOccurrences(of: "**", with: "")
                    .replacingOccurrences(of: "###", with: "")
                    .replacingOccurrences(of: "##", with: "")
                    .replacingOccurrences(of: "# ", with: "")
                    .replacingOccurrences(of: "- ", with: "  ")
                copyWithFeedback(plain)
            } label: {
                Label("Copy as Plain Text", systemImage: "doc.plaintext")
            }
        }
    }

    private func copyWithFeedback(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }

}

// MARK: - Brainstorm Usage Popover

struct BrainstormUsagePopoverView: View {
    let entry: BrainstormEntry
    let providers: ProviderManager
    let accent: Color

    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }
    private var qualifiedModelId: String { entry.qualifiedModelId ?? "" }
    private var modelInfo: (providerName: String, modelName: String, icon: String) {
        providers.providerInfo(for: qualifiedModelId)
    }
    private var pricing: (input: Double, output: Double)? {
        providers.pricingInfo(for: qualifiedModelId)
    }
    private var outputTokens: Int { entry.tokenCount ?? 0 }
    private var inputTokens: Int { entry.inputTokenCount ?? 0 }
    private var messageCost: Double? {
        guard !qualifiedModelId.isEmpty else { return nil }
        return providers.costForMessage(
            modelId: qualifiedModelId,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }
    private var tokensPerSecond: Double? {
        guard let dur = entry.durationMs, outputTokens > 0, dur > 0 else { return nil }
        return Double(outputTokens) / (dur / 1000.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — model info
            HStack(spacing: 6) {
                Image(systemName: modelInfo.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(accent)
                Text(modelInfo.modelName)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(entry.role.displayName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Stats
            VStack(alignment: .leading, spacing: 8) {
                Text("THIS ENTRY")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 0) {
                    UsageStatColumn(
                        label: "Input",
                        value: inputTokens > 0 ? "\(formatTokens(inputTokens))" : "—",
                        icon: "arrow.up.circle"
                    )
                    UsageStatColumn(
                        label: "Output",
                        value: outputTokens > 0 ? "\(formatTokens(outputTokens))" : "—",
                        icon: "arrow.down.circle"
                    )
                    UsageStatColumn(
                        label: "Speed",
                        value: tokensPerSecond.map { String(format: "%.1f/s", $0) } ?? "—",
                        icon: "bolt"
                    )
                    UsageStatColumn(
                        label: "Cost",
                        value: messageCost.map { formatCost($0) } ?? "Free",
                        icon: "dollarsign.circle"
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // Pricing info footer
            if let price = pricing {
                Divider()
                HStack(spacing: 12) {
                    Label {
                        Text("Input: $\(String(format: "%.2f", price.input))/M tokens")
                    } icon: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 8))
                    }
                    Label {
                        Text("Output: $\(String(format: "%.2f", price.output))/M tokens")
                    } icon: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 8))
                    }
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }

            // Console link
            if modelInfo.providerName == "Anthropic" || modelInfo.providerName == "OpenAI" {
                Divider()
                let consoleURL = modelInfo.providerName == "Anthropic"
                    ? "https://console.anthropic.com/settings/billing"
                    : "https://platform.openai.com/usage"
                Button {
                    if let url = URL(string: consoleURL) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "safari")
                            .font(.system(size: 10))
                        Text("View balance & billing")
                            .font(.system(size: 10, weight: .medium))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8))
                    }
                    .foregroundStyle(accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 320)
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 10_000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        } else {
            return "\(count)"
        }
    }

    private func formatCost(_ cost: Double) -> String {
        if cost < 0.001 {
            return String(format: "$%.4f", cost)
        } else if cost < 0.01 {
            return String(format: "$%.3f", cost)
        } else {
            return String(format: "$%.2f", cost)
        }
    }
}

// MARK: - Q&A Message Card

struct QAMessageCardView: View {
    let message: BrainstormQAMessage
    let accent: Color
    let qaModelId: String?
    let providerInfo: (providerName: String, modelName: String, icon: String)?
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var copied: Bool = false
    @State private var showUsagePopover: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if message.role == .user {
                    Image(systemName: "person.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(accent)
                    Text("You")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundStyle(.purple)
                    Text("Assistant")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.purple)

                    if let info = providerInfo {
                        Text("· \(info.modelName)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()

                // Copy button with feedback
                Button {
                    copyToClipboard(message.content)
                } label: {
                    Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(copied ? .green : .secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(copied ? "Copied!" : "Copy to clipboard")
                .animation(.easeInOut(duration: 0.15), value: copied)
            }

            if message.role == .user {
                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
            } else {
                MarkdownText(content: message.content)
            }

            // Stats pill for assistant messages
            if message.role == .assistant, let tokens = message.tokenCount {
                Button {
                    showUsagePopover = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 8))
                        Text("\(tokens) tok")
                        if let ms = message.durationMs, ms > 0 {
                            Text("·")
                            Text(String(format: "%.1f tok/s", Double(tokens) / (ms / 1000.0)))
                            Text("·")
                            Text(ChatManager.formatDuration(ms))
                        }
                        if let modelId = qaModelId,
                           let cost = chatManager.providers.costForMessage(
                               modelId: modelId,
                               inputTokens: 0,
                               outputTokens: tokens
                           ), cost > 0 {
                            Text("·")
                            Text(formatQACost(cost))
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.purple.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(.purple.opacity(colorScheme == .dark ? 0.08 : 0.06))
                    )
                    .overlay(
                        Capsule()
                            .stroke(.purple.opacity(0.12), lineWidth: 0.5)
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showUsagePopover, arrowEdge: .bottom) {
                    qaUsagePopover(tokens: tokens)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            message.role == .user
                ? AnyShapeStyle(accent.opacity(0.04))
                : AnyShapeStyle(Color.purple.opacity(0.04))
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    message.role == .user ? accent.opacity(0.15) : Color.purple.opacity(0.1),
                    lineWidth: 1
                )
        )
        .onDisappear {
            showUsagePopover = false
        }
        .contextMenu {
            Button {
                copyToClipboard(message.content)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            if message.role == .assistant {
                Button {
                    // Copy just the text without markdown formatting
                    let plain = message.content
                        .replacingOccurrences(of: "**", with: "")
                        .replacingOccurrences(of: "###", with: "")
                        .replacingOccurrences(of: "##", with: "")
                        .replacingOccurrences(of: "# ", with: "")
                        .replacingOccurrences(of: "- ", with: "  ")
                    copyToClipboard(plain)
                } label: {
                    Label("Copy as Plain Text", systemImage: "doc.plaintext")
                }
            }

            Divider()

            Button {
                copyToClipboard(message.content)
            } label: {
                Label("Select All & Copy", systemImage: "text.badge.checkmark")
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }

    private func formatQACost(_ cost: Double) -> String {
        if cost < 0.001 {
            return String(format: "$%.4f", cost)
        } else if cost < 0.01 {
            return String(format: "$%.3f", cost)
        } else {
            return String(format: "$%.2f", cost)
        }
    }

    @ViewBuilder
    private func qaUsagePopover(tokens: Int) -> some View {
        let modelId = qaModelId ?? ""
        let info = chatManager.providers.providerInfo(for: modelId)
        let cost = chatManager.providers.costForMessage(modelId: modelId, inputTokens: 0, outputTokens: tokens)
        let pricing = chatManager.providers.pricingInfo(for: modelId)
        let tokPerSec: Double? = {
            guard let ms = message.durationMs, tokens > 0, ms > 0 else { return nil }
            return Double(tokens) / (ms / 1000.0)
        }()

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: info.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(.purple)
                Text(info.modelName)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("Q&A")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("THIS RESPONSE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 0) {
                    UsageStatColumn(label: "Output", value: "\(tokens)", icon: "arrow.down.circle")
                    UsageStatColumn(
                        label: "Speed",
                        value: tokPerSec.map { String(format: "%.1f/s", $0) } ?? "—",
                        icon: "bolt"
                    )
                    UsageStatColumn(
                        label: "Cost",
                        value: cost.map { formatQACost($0) } ?? "Free",
                        icon: "dollarsign.circle"
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if let price = pricing {
                Divider()
                HStack(spacing: 12) {
                    Label {
                        Text("Input: $\(String(format: "%.2f", price.input))/M tokens")
                    } icon: {
                        Image(systemName: "arrow.up").font(.system(size: 8))
                    }
                    Label {
                        Text("Output: $\(String(format: "%.2f", price.output))/M tokens")
                    } icon: {
                        Image(systemName: "arrow.down").font(.system(size: 8))
                    }
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }

            if info.providerName == "Anthropic" || info.providerName == "OpenAI" {
                Divider()
                let consoleURL = info.providerName == "Anthropic"
                    ? "https://console.anthropic.com/settings/billing"
                    : "https://platform.openai.com/usage"
                Button {
                    if let url = URL(string: consoleURL) { NSWorkspace.shared.open(url) }
                } label: {
                    HStack {
                        Image(systemName: "safari").font(.system(size: 10))
                        Text("View balance & billing").font(.system(size: 10, weight: .medium))
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 8))
                    }
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 280)
    }
}

// MARK: - Export Sheet

private struct ExportSheet: View {
    let markdown: String
    let html: String
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var exportFeedback: String = ""

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Export Brainstorm")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                Text(markdown)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)

            if !exportFeedback.isEmpty {
                Text(exportFeedback)
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }

            HStack(spacing: 12) {
                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
                    withAnimation { exportFeedback = "Copied to clipboard!" }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { exportFeedback = "" }
                    }
                } label: {
                    Label("Copy to Clipboard", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Button {
                    saveMarkdownFile()
                } label: {
                    Label("Save as Markdown", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)

                Button {
                    savePDF()
                } label: {
                    Label("Save as PDF", systemImage: "doc.richtext")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 600, minHeight: 500)
    }

    private func saveMarkdownFile() {
        let panel = NSSavePanel()
        panel.title = "Save Brainstorm Report"
        panel.nameFieldStringValue = sanitizeFilename(title) + ".md"
        panel.allowedContentTypes = [.plainText]
        panel.allowsOtherFileTypes = true

        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try markdown.write(to: url, atomically: true, encoding: .utf8)
                    withAnimation { exportFeedback = "Saved to \(url.lastPathComponent)" }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation { exportFeedback = "" }
                    }
                } catch {
                    withAnimation { exportFeedback = "Error: \(error.localizedDescription)" }
                }
            }
        }
    }

    private func savePDF() {
        let panel = NSSavePanel()
        panel.title = "Save Brainstorm Report as PDF"
        panel.nameFieldStringValue = sanitizeFilename(title) + ".pdf"
        panel.allowedContentTypes = [.pdf]

        panel.begin { response in
            if response == .OK, let url = panel.url {
                renderHTMLToPDF(html: html, to: url) { success in
                    if success {
                        withAnimation { exportFeedback = "PDF saved to \(url.lastPathComponent)" }
                    } else {
                        withAnimation { exportFeedback = "Error generating PDF" }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation { exportFeedback = "" }
                    }
                }
            }
        }
    }

    private func sanitizeFilename(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "[^a-zA-Z0-9\\s\\-_]", with: "", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "-")
    }

    /// Renders HTML content to a PDF file using WebKit's built-in print support
    private func renderHTMLToPDF(html: String, to url: URL, completion: @escaping (Bool) -> Void) {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        webView.loadHTMLString(html, baseURL: nil)

        // Wait for the page to finish loading, then create PDF
        let delegate = PDFPrintDelegate(url: url, completion: completion)
        webView.navigationDelegate = delegate

        // Prevent delegate from being deallocated
        objc_setAssociatedObject(webView, "pdfDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
    }
}

/// Helper class that waits for WebKit to finish loading, then creates a PDF
private class PDFPrintDelegate: NSObject, WKNavigationDelegate {
    let url: URL
    let completion: (Bool) -> Void

    init(url: URL, completion: @escaping (Bool) -> Void) {
        self.url = url
        self.completion = completion
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let config = WKPDFConfiguration()
        config.rect = NSRect(x: 0, y: 0, width: 612, height: 792) // US Letter

        webView.createPDF(configuration: config) { [self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    do {
                        try data.write(to: self.url)
                        self.completion(true)
                    } catch {
                        self.completion(false)
                    }
                case .failure:
                    self.completion(false)
                }
            }
        }
    }
}

// MARK: - Q&A Model Picker Sheet

private struct QAModelPickerSheet: View {
    let session: BrainstormSession
    @EnvironmentObject var brainstormManager: BrainstormManager
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var selectedModelId: String = ""

    private var allModels: [ProviderModel] {
        chatManager.providers.allModels
    }

    private var groupedModels: [(provider: String, models: [ProviderModel])] {
        let grouped = Dictionary(grouping: allModels, by: { $0.providerLabel })
        return grouped
            .sorted { $0.key < $1.key }
            .map { (provider: $0.key, models: $0.value) }
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ask Questions About This Brainstorm")
                        .font(.headline)

                    Text("Choose a model to chat with about the session's ideas, analysis, and outcomes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Picker("Model", selection: $selectedModelId) {
                if selectedModelId.isEmpty {
                    Text("Select a model…").tag("")
                }
                ForEach(groupedModels, id: \.provider) { group in
                    Section(group.provider) {
                        ForEach(group.models) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                }
            }
            .pickerStyle(.menu)

            HStack {
                Text("The model will have access to the full brainstorm transcript and can answer questions about ideas, participant contributions, and session dynamics.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack {
                Spacer()

                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)

                Button {
                    brainstormManager.enterQAMode(session: session, modelId: selectedModelId, context: modelContext)
                    dismiss()
                } label: {
                    Label("Start Q&A", systemImage: "bubble.left.and.text.bubble.right")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedModelId.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 450)
        .onAppear {
            // Default to the first available model
            if let first = allModels.first {
                selectedModelId = first.id
            }
        }
    }
}
