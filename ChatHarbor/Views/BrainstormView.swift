import SwiftUI
import SwiftData

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
                    Label("Export as Markdown", systemImage: "square.and.arrow.up")
                }

                Divider()

                Button("Delete Session", role: .destructive) {
                    brainstormManager.deleteSession(session, in: modelContext)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .sheet(isPresented: $showingExport) {
            ExportSheet(markdown: brainstormManager.exportToMarkdown(session))
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

                    // Bottom anchor for auto-scroll
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(20)
            }
            .onChange(of: session.entries.count) { _, _ in
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: brainstormManager.streamingContent) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: entry.role.icon)
                    .font(.system(size: 10))
                Text(entry.role.displayName)
                    .font(.system(size: 11, weight: .semibold))
                ProgressView()
                    .scaleEffect(0.5)
            }
            .foregroundStyle(roleColor(entry.role))

            if !brainstormManager.streamingContent.isEmpty {
                Text(brainstormManager.streamingContent)
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
        .background(roleColor(entry.role).opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(roleColor(entry.role).opacity(0.15), lineWidth: 1)
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
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(accent.opacity(0.2), lineWidth: 1)
        )
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

        return HStack(spacing: 12) {
            if entryCount > 0 {
                Label("\(entryCount) responses", systemImage: "text.bubble")
                Label("\(totalTokens + totalInputTokens) tokens", systemImage: "number")
                if totalDuration > 0 {
                    Label(ChatManager.formatDuration(totalDuration), systemImage: "clock")
                }
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }

    private func copyReportToClipboard() {
        let markdown = brainstormManager.exportToMarkdown(session)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    private func retryEntry(_ entry: BrainstormEntry, withModel alternateModelId: String? = nil) {
        brainstormManager.retryFailedEntry(entry, session: session, context: modelContext, alternateModelId: alternateModelId)
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

// MARK: - Brainstorm Entry Card

struct BrainstormEntryCard: View {
    let entry: BrainstormEntry
    let accent: Color
    /// Retry with an optional different model ID (nil = same model)
    var onRetry: ((String?) -> Void)?
    @EnvironmentObject var chatManager: ChatManager

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
                        let info = chatManager.providers.providerInfo(for: modelId)
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
                                let allModels = chatManager.providers.allModels
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

            // Stats — show whenever any metadata exists
            if !entry.isStreaming, entry.error == nil, !entry.isUserInput,
               (entry.tokenCount != nil || entry.durationMs != nil) {
                HStack(spacing: 5) {
                    Image(systemName: "gauge.low")
                        .font(.system(size: 9))

                    let parts = entryStatParts(entry)
                    ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                        if index > 0 {
                            Text("·")
                        }
                        Text(part)
                    }
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
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
    }

    /// Build an array of stat strings, avoiding leading/trailing separators
    private func entryStatParts(_ entry: BrainstormEntry) -> [String] {
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
        return parts
    }
}

// MARK: - Export Sheet

private struct ExportSheet: View {
    let markdown: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Export Brainstorm")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
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

            HStack {
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
                    dismiss()
                } label: {
                    Label("Copy to Clipboard", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 600, minHeight: 500)
    }
}
