import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Chat View
//
// The main chat interface. Shows message history with the selected
// conversation and provides a text input for sending messages.

struct ChatView: View {
    let conversation: Conversation
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var inputText: String = ""
    @State private var showConversationSettings: Bool = false
    @FocusState private var inputFocused: Bool

    private var accent: Color {
        chatManager.currentTheme.accentColor(for: colorScheme)
    }

    private var isDark: Bool { colorScheme == .dark }

    /// Label for the conversation settings badge — shows the user-saved name,
    /// a matching built-in template name, or "Custom"
    private var conversationSettingsLabel: String {
        // 1) If the user saved a custom name for this preset, always use it
        if let saved = conversation.savedPresetName, !saved.isEmpty {
            return saved
        }
        let prompt = conversation.systemPrompt
        if prompt.isEmpty {
            // Only parameter overrides, no prompt
            if conversation.temperature != nil || conversation.maxTokens != nil {
                return "Custom"
            }
            return ""
        }
        // 2) Check built-in templates (use short display names for the badge)
        if let match = PromptLibrary.builtIn.first(where: { !$0.systemPrompt.isEmpty && $0.systemPrompt == prompt }) {
            return Self.shortBadgeName[match.name] ?? match.name
        }
        // 3) Check user's custom saved templates
        if let match = chatManager.customTemplates.first(where: { $0.systemPrompt == prompt }) {
            return match.name
        }
        return "Custom"
    }

    /// Short names for the header badge to keep it compact
    private static let shortBadgeName: [String: String] = [
        "Code Assistant": "Code",
        "Creative Writer": "Creative",
        "Writing Editor": "Editor",
        "Research Analyst": "Research",
        "Socratic Tutor": "Tutor",
        "Devil's Advocate": "Advocate",
    ]

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Chat Header
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    if conversation.isForked {
                        Button {
                            // Navigate to parent conversation
                            if let parentId = conversation.forkedFromId {
                                chatManager.selectedConversationId = parentId
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 9))
                                Text("Forked")
                                    .font(.system(size: 10))
                                Image(systemName: "arrow.turn.left.up")
                                    .font(.system(size: 8))
                                Text("Go to parent")
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(accent.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .help("Navigate to the parent conversation")
                    }
                }

                Spacer()

                // Conversation settings button (system prompt + parameters)
                Button {
                    showConversationSettings.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 10))
                        if !conversation.systemPrompt.isEmpty || conversation.temperature != nil || conversation.maxTokens != nil {
                            Text(conversationSettingsLabel)
                                .font(.system(size: 10))
                        }
                    }
                    .foregroundColor(
                        (!conversation.systemPrompt.isEmpty || conversation.temperature != nil)
                        ? accent : Color.secondary
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.gray.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Conversation settings — system prompt & parameters")
                .popover(isPresented: $showConversationSettings, arrowEdge: .bottom) {
                    ConversationSettingsPopover(conversation: conversation)
                        .environmentObject(chatManager)
                }

                Button {
                    exportConversation()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Export as Markdown")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            // MARK: - Message List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(conversation.sortedMessages) { message in
                            MessageRow(message: message)
                                .id(message.id)
                                .contextMenu {
                                    // Copy
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(message.content, forType: .string)
                                    } label: {
                                        Label("Copy Text", systemImage: "doc.on.doc")
                                    }

                                    Divider()

                                    // Regenerate (assistant messages only)
                                    if message.role == .assistant {
                                        Button {
                                            regenerateResponse(for: message)
                                        } label: {
                                            Label("Regenerate Response", systemImage: "arrow.clockwise")
                                        }
                                        .disabled(chatManager.isGenerating)

                                        // Regenerate with a different model
                                        Menu("Regenerate with…") {
                                            ForEach(chatManager.providers.allModels) { model in
                                                Button {
                                                    regenerateResponse(for: message, withModel: model.id)
                                                } label: {
                                                    Label(
                                                        model.displayName,
                                                        systemImage: model.isLocal ? "desktopcomputer" : "cloud"
                                                    )
                                                }
                                            }
                                        }
                                        .disabled(chatManager.isGenerating)

                                        Divider()
                                    }

                                    // Fork (keeps current model)
                                    Button {
                                        let fork = chatManager.forkConversation(
                                            conversation,
                                            atMessage: message,
                                            in: modelContext
                                        )
                                        // Use the currently selected model, not the original's
                                        fork.modelId = chatManager.selectedModelId
                                        try? modelContext.save()
                                    } label: {
                                        Label("Fork from Here", systemImage: "arrow.triangle.branch")
                                    }

                                    Menu("Fork to Model…") {
                                        ForEach(chatManager.providers.allModels) { model in
                                            Button {
                                                let fork = chatManager.forkConversation(
                                                    conversation,
                                                    atMessage: message,
                                                    in: modelContext
                                                )
                                                fork.modelId = model.id
                                                fork.title = "\(chatManager.forkPrefix) \(model.displayName)"
                                                try? modelContext.save()
                                            } label: {
                                                Label(
                                                    model.displayName,
                                                    systemImage: model.isLocal ? "desktopcomputer" : "cloud"
                                                )
                                            }
                                        }
                                    }

                                    Divider()

                                    // Switch model for this conversation
                                    Menu("Switch Model…") {
                                        ForEach(chatManager.providers.allModels) { model in
                                            Button {
                                                conversation.modelId = model.id
                                                chatManager.selectModel(model.id)
                                                try? modelContext.save()
                                            } label: {
                                                HStack {
                                                    Label(
                                                        model.displayName,
                                                        systemImage: model.isLocal ? "desktopcomputer" : "cloud"
                                                    )
                                                    if model.id == (conversation.modelId.isEmpty ? chatManager.selectedModelId : conversation.modelId) {
                                                        Spacer()
                                                        Image(systemName: "checkmark")
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Button {
                                        exportConversation()
                                    } label: {
                                        Label("Export Conversation", systemImage: "square.and.arrow.up")
                                    }
                                }
                        }

                        // Invisible anchor for auto-scroll
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: chatManager.streamingContent) { _, _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: conversation.messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onAppear {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }

            // MARK: - Input Area
            VStack(spacing: 0) {
                Divider()

                VStack(spacing: 8) {
                    HStack(alignment: .center, spacing: 10) {
                        // Model icon — uses conversation's model if set, else global
                        let effectiveModelId = conversation.modelId.isEmpty ? chatManager.selectedModelId : conversation.modelId
                        let info = chatManager.providers.providerInfo(for: effectiveModelId)
                        Image(systemName: info.icon)
                            .font(.system(size: 12))
                            .foregroundStyle(accent.opacity(0.5))
                            .frame(width: 20)
                            .help(info.modelName)

                        TextField("Message \(info.modelName)…", text: $inputText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(1...10)
                            .focused($inputFocused)
                            .onSubmit {
                                if !NSEvent.modifierFlags.contains(.shift) {
                                    send()
                                }
                            }
                            .font(.system(size: 13))

                        if chatManager.isGenerating {
                            Button {
                                chatManager.stopGenerating()
                            } label: {
                                Image(systemName: "stop.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Stop generating")
                        } else {
                            Button {
                                send()
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(
                                        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                            ? Color.gray.opacity(0.3)
                                            : accent
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .help("Send message (Enter)")
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .onAppear {
            inputFocused = true
        }
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        chatManager.sendMessage(text, in: conversation, context: modelContext)
    }

    /// Delete the assistant response and re-send the last user message,
    /// optionally with a different model.
    private func regenerateResponse(for assistantMessage: Message, withModel modelId: String? = nil) {
        guard assistantMessage.role == .assistant else { return }
        guard !chatManager.isGenerating else { return }

        // Find the user message immediately before this assistant message
        let sorted = conversation.sortedMessages
        guard let index = sorted.firstIndex(where: { $0.id == assistantMessage.id }),
              index > 0,
              sorted[index - 1].role == .user else { return }

        let userMessage = sorted[index - 1]
        let userText = userMessage.content

        // If switching model, update the conversation
        if let newModel = modelId {
            conversation.modelId = newModel
            chatManager.selectModel(newModel)
        }

        // Remove the assistant message
        modelContext.delete(assistantMessage)
        try? modelContext.save()

        // Re-send the user's message
        chatManager.sendMessage(userText, in: conversation, context: modelContext)
    }

    private func exportConversation() {
        let markdown = chatManager.exportToMarkdown(conversation)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(conversation.title).md"
        panel.title = "Export Conversation"
        panel.message = "Save your conversation as Markdown"

        if panel.runModal() == .OK, let url = panel.url {
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Message Row

struct MessageRow: View {
    let message: Message
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var showUsagePopover = false

    private var isUser: Bool { message.role == .user }
    private var isDark: Bool { colorScheme == .dark }

    private var accent: Color {
        chatManager.currentTheme.accentColor(for: colorScheme)
    }

    /// Friendly name for the model powering this message
    private var modelInfo: (providerName: String, modelName: String, icon: String) {
        let qualifiedId = message.modelUsed ?? message.conversation?.modelId ?? chatManager.selectedModelId
        return chatManager.providers.providerInfo(for: qualifiedId)
    }

    /// Estimated cost for this message
    private var messageCost: Double? {
        guard let outputTokens = message.tokenCount else { return nil }
        let inputTokens = message.inputTokenCount ?? 0
        let modelId = message.modelUsed ?? message.conversation?.modelId ?? chatManager.selectedModelId
        return chatManager.providers.costForMessage(
            modelId: modelId,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if !isUser {
                // Assistant avatar
                Image(systemName: modelInfo.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(accent)
                    .frame(width: 26, height: 26)
                    .background(accent.opacity(0.1), in: Circle())
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
                // Message content
                if message.isStreaming && message.content.isEmpty {
                    // Thinking dots
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle()
                                .fill(accent.opacity(0.4))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                    )
                } else if isUser {
                    Text(LocalizedStringKey(message.content))
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(accent.opacity(isDark ? 0.25 : 0.15))
                        )
                } else {
                    MarkdownText(content: message.content)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                        )
                }

                // Clickable token/cost pill — show whenever any metadata exists
                if !isUser, !message.isStreaming,
                   (message.tokenCount != nil || message.durationMs != nil) {
                    Button {
                        showUsagePopover = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 8))

                            if let tokens = message.tokenCount, tokens > 0 {
                                Text("\(tokens) tokens")
                            } else if let duration = message.durationMs, duration > 0 {
                                // No token count — lead with duration instead
                                Text(formatDuration(duration))
                            }

                            if let tokens = message.tokenCount, tokens > 0,
                               let cost = messageCost {
                                Text("·")
                                Text(formatCost(cost))
                            }

                            if let tokens = message.tokenCount, tokens > 0,
                               let duration = message.durationMs, duration > 0 {
                                Text("·")
                                Text(formatDuration(duration))
                            }

                            Image(systemName: "chevron.right")
                                .font(.system(size: 7, weight: .bold))
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(accent.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(accent.opacity(isDark ? 0.08 : 0.06))
                        )
                        .overlay(
                            Capsule()
                                .stroke(accent.opacity(0.12), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showUsagePopover, arrowEdge: .bottom) {
                        UsagePopoverView(
                            message: message,
                            conversation: message.conversation,
                            chatManager: chatManager,
                            accent: accent
                        )
                    }
                    .padding(.leading, 4)
                }
            }
            .frame(maxWidth: 520, alignment: isUser ? .trailing : .leading)
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .onDisappear {
            // Kill popover when bubble scrolls off-screen to prevent
            // layout loop in LazyVStack
            showUsagePopover = false
        }
    }

    private func formatDuration(_ ms: Double) -> String {
        if ms < 1000 {
            return "\(Int(ms))ms"
        } else {
            return String(format: "%.1fs", ms / 1000.0)
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

// MARK: - Usage Popover

struct UsagePopoverView: View {
    let message: Message
    let conversation: Conversation?
    let chatManager: ChatManager
    let accent: Color

    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }
    private var qualifiedModelId: String {
        message.modelUsed ?? conversation?.modelId ?? chatManager.selectedModelId
    }
    private var modelInfo: (providerName: String, modelName: String, icon: String) {
        chatManager.providers.providerInfo(for: qualifiedModelId)
    }
    private var pricing: (input: Double, output: Double)? {
        chatManager.providers.pricingInfo(for: qualifiedModelId)
    }

    // This message stats
    private var outputTokens: Int { message.tokenCount ?? 0 }
    private var inputTokens: Int { message.inputTokenCount ?? 0 }
    private var messageCost: Double? {
        chatManager.providers.costForMessage(
            modelId: qualifiedModelId,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }
    private var tokensPerSecond: Double? {
        guard let dur = message.durationMs, outputTokens > 0, dur > 0 else { return nil }
        return Double(outputTokens) / (dur / 1000.0)
    }

    // Conversation totals
    private var conversationStats: (inputTokens: Int, outputTokens: Int, cost: Double, messageCount: Int) {
        guard let conv = conversation else { return (0, 0, 0, 0) }
        var totalIn = 0
        var totalOut = 0
        var totalCost = 0.0
        var msgCount = 0

        for msg in conv.sortedMessages where msg.role == .assistant {
            let outTok = msg.tokenCount ?? 0
            let inTok = msg.inputTokenCount ?? 0
            totalOut += outTok
            totalIn += inTok
            msgCount += 1

            let mid = msg.modelUsed ?? conv.modelId
            if let cost = chatManager.providers.costForMessage(modelId: mid, inputTokens: inTok, outputTokens: outTok) {
                totalCost += cost
            }
        }
        return (totalIn, totalOut, totalCost, msgCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: modelInfo.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(accent)
                Text(modelInfo.modelName)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(modelInfo.providerName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // This Message section
            VStack(alignment: .leading, spacing: 8) {
                Text("THIS MESSAGE")
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
                        value: "\(formatTokens(outputTokens))",
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

            Divider()

            // Conversation Totals section
            VStack(alignment: .leading, spacing: 8) {
                let stats = conversationStats
                Text("CONVERSATION (\(stats.messageCount) responses)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 0) {
                    UsageStatColumn(
                        label: "Input",
                        value: stats.inputTokens > 0 ? "\(formatTokens(stats.inputTokens))" : "—",
                        icon: "arrow.up.circle"
                    )
                    UsageStatColumn(
                        label: "Output",
                        value: "\(formatTokens(stats.outputTokens))",
                        icon: "arrow.down.circle"
                    )
                    UsageStatColumn(
                        label: "Total",
                        value: "\(formatTokens(stats.inputTokens + stats.outputTokens))",
                        icon: "sum"
                    )
                    UsageStatColumn(
                        label: "Total Cost",
                        value: stats.cost > 0 ? formatCost(stats.cost) : "Free",
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

            // Estimate section
            if pricing != nil, conversationStats.messageCount > 0 {
                Divider()
                let stats = conversationStats
                let avgCostPerMsg = stats.messageCount > 0 ? stats.cost / Double(stats.messageCount) : 0
                VStack(alignment: .leading, spacing: 4) {
                    Text("ESTIMATES")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)

                    if avgCostPerMsg > 0 {
                        let msgsPerDollar = 1.0 / avgCostPerMsg
                        let msgsPerFive = 5.0 / avgCostPerMsg
                        HStack(spacing: 12) {
                            Label(
                                "\(Int(msgsPerDollar)) msgs / $1",
                                systemImage: "message"
                            )
                            Label(
                                "\(Int(msgsPerFive)) msgs / $5",
                                systemImage: "message.fill"
                            )
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    } else {
                        Text("Local models — no API cost")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
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
        }
        return "\(count)"
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

// MARK: - Usage Stat Column

struct UsageStatColumn: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Conversation Settings Popover
//
// Per-conversation overrides for system prompt and parameters.
// Everything here is transparent — what you see is what gets sent.

struct ConversationSettingsPopover: View {
    var conversation: Conversation
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openSettings) private var openSettings
    @State private var apiDetailsExpanded: Bool = false
    @State private var copiedPayload: Bool = false
    @State private var isNamingPreset: Bool = false
    @State private var presetNameInput: String = ""

    private var accent: Color {
        chatManager.currentTheme.accentColor(for: colorScheme)
    }

    /// Which provider this conversation targets
    private var providerId: String {
        let modelId = conversation.modelId.isEmpty ? chatManager.selectedModelId : conversation.modelId
        let parts = modelId.split(separator: ":", maxSplits: 1)
        return parts.count >= 1 ? String(parts[0]) : ""
    }

    private var providerName: String {
        chatManager.providers.providerInfo(
            for: conversation.modelId.isEmpty ? chatManager.selectedModelId : conversation.modelId
        ).providerName
    }

    private var supportedParams: [String] {
        ProviderManager.supportedParameters(for: providerId)
    }

    /// The effective system prompt (showing fallback chain)
    private var effectiveSystemPrompt: String {
        if !conversation.systemPrompt.isEmpty { return conversation.systemPrompt }
        return chatManager.providers.defaultSystemPrompt(for: providerId)
    }

    /// Whether this conversation has any custom overrides
    private var hasCustomSettings: Bool {
        !conversation.systemPrompt.isEmpty ||
        conversation.temperature != nil ||
        conversation.maxTokens != nil ||
        conversation.topP != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14))
                            .foregroundStyle(accent)
                        Text("Conversation Settings")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                    }
                    Text("These settings apply only to this conversation. They override your provider defaults from Settings.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                // MARK: - System Prompt Section
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 11))
                            .foregroundStyle(accent)
                        Text("System Prompt")
                            .font(.system(size: 12, weight: .semibold))
                    }

                    Text("Instructions sent before every message in this conversation. Tells the AI how to behave, what tone to use, or what role to play.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextEditor(text: Binding(
                        get: { conversation.systemPrompt },
                        set: { conversation.systemPrompt = $0 }
                    ))
                    .font(.system(size: 11))
                    .frame(height: 70)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color.gray.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.12), lineWidth: 1))

                    // Fallback info
                    if conversation.systemPrompt.isEmpty {
                        if !effectiveSystemPrompt.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.turn.down.right")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.orange)
                                Text("Using \(providerName) default:")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.orange)
                            }
                            Text("\"\(effectiveSystemPrompt.prefix(120))\(effectiveSystemPrompt.count > 120 ? "…" : "")\"")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .padding(6)
                                .background(Color.orange.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                Text("No system prompt set. The AI will use its default behavior.")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Quick templates — use exact PromptLibrary text so the header badge matches
                    HStack(spacing: 6) {
                        Text("Quick:")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        if let t = PromptLibrary.builtIn.first(where: { $0.name == "Concise" }) {
                            promptChip("Concise", t.systemPrompt)
                        }
                        if let t = PromptLibrary.builtIn.first(where: { $0.name == "Code Assistant" }) {
                            promptChip("Code", t.systemPrompt)
                        }
                        if let t = PromptLibrary.builtIn.first(where: { $0.name == "Creative Writer" }) {
                            promptChip("Creative", t.systemPrompt)
                        }
                        promptChip("Clear", "") // clears it
                    }

                    // Save / name this preset
                    if hasCustomSettings {
                        HStack(spacing: 6) {
                            if isNamingPreset {
                                TextField("Name", text: $presetNameInput)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 10))
                                    .frame(width: 120)
                                    .onChange(of: presetNameInput) { _, newVal in
                                        // Strip spaces (one word only) and enforce 16 char max
                                        let stripped = newVal.replacingOccurrences(of: " ", with: "")
                                        let limited = String(stripped.prefix(16))
                                        if limited != newVal {
                                            presetNameInput = limited
                                        }
                                    }
                                    .onSubmit {
                                        savePresetName()
                                    }

                                Button("Save") {
                                    savePresetName()
                                }
                                .font(.system(size: 9, weight: .medium))
                                .controlSize(.small)
                                .disabled(presetNameInput.isEmpty)

                                Button("Cancel") {
                                    isNamingPreset = false
                                    presetNameInput = ""
                                }
                                .font(.system(size: 9))
                                .controlSize(.small)
                            } else {
                                Button {
                                    // Pre-fill with existing name if one is saved
                                    presetNameInput = conversation.savedPresetName ?? ""
                                    isNamingPreset = true
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: conversation.savedPresetName != nil ? "pencil" : "tag")
                                            .font(.system(size: 8))
                                        Text(conversation.savedPresetName != nil ? "Rename Preset" : "Save As Preset")
                                            .font(.system(size: 9, weight: .medium))
                                    }
                                    .foregroundStyle(accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(accent.opacity(0.08), in: Capsule())
                                }
                                .buttonStyle(.plain)

                                if conversation.savedPresetName != nil {
                                    Button {
                                        conversation.savedPresetName = nil
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove preset name")
                                }
                            }
                            Spacer()
                        }
                    }
                }

                // MARK: - Parameters Section
                if !supportedParams.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "dial.low")
                                .font(.system(size: 11))
                                .foregroundStyle(accent)
                            Text("Model Parameters")
                                .font(.system(size: 12, weight: .semibold))
                        }

                        Text("Control how the AI generates responses. These values are sent directly in the API request. Leave unset to use your defaults from Settings.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        // Temperature
                        if supportedParams.contains("temperature") {
                            ParamCard(
                                name: "temperature",
                                description: "How creative vs. focused the responses are. Low (0.0) = deterministic and precise. High (2.0) = creative and varied.",
                                accent: accent
                            ) {
                                HStack(spacing: 8) {
                                    Text("Focused")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.secondary)
                                    Slider(
                                        value: Binding(
                                            get: { conversation.temperature ?? 1.0 },
                                            set: { conversation.temperature = $0 }
                                        ),
                                        in: 0...2,
                                        step: 0.1
                                    )
                                    .controlSize(.small)
                                    Text("Creative")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.secondary)
                                }
                            } valueDisplay: {
                                paramValueBadge(conversation.temperature.map { String(format: "%.1f", $0) })
                            } onClear: {
                                conversation.temperature = nil
                            }
                        }

                        // Max Tokens
                        if supportedParams.contains("maxTokens") {
                            ParamCard(
                                name: "max_tokens",
                                description: "Maximum length of the response in tokens (~4 characters each). Higher = longer responses allowed.",
                                accent: accent
                            ) {
                                TextField("e.g. 4096", value: Binding(
                                    get: { conversation.maxTokens },
                                    set: { conversation.maxTokens = $0 }
                                ), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 100)
                            } valueDisplay: {
                                paramValueBadge(conversation.maxTokens.map { "\($0)" })
                            } onClear: {
                                conversation.maxTokens = nil
                            }
                        }

                        // Top P
                        if supportedParams.contains("topP") {
                            ParamCard(
                                name: "top_p",
                                description: "Nucleus sampling — limits which tokens the AI considers. Lower values make output more focused. Usually leave this alone if you're adjusting temperature.",
                                accent: accent
                            ) {
                                HStack(spacing: 8) {
                                    Text("Narrow")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.secondary)
                                    Slider(
                                        value: Binding(
                                            get: { conversation.topP ?? 1.0 },
                                            set: { conversation.topP = $0 }
                                        ),
                                        in: 0...1,
                                        step: 0.05
                                    )
                                    .controlSize(.small)
                                    Text("Broad")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.secondary)
                                }
                            } valueDisplay: {
                                paramValueBadge(conversation.topP.map { String(format: "%.2f", $0) })
                            } onClear: {
                                conversation.topP = nil
                            }
                        }
                    }
                } else {
                    Divider()

                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Parameters not configurable")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text("\(providerName) is an on-device model with fixed behavior — no tuning knobs available.")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                // MARK: - API Transparency
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    // Expandable header
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            apiDetailsExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "eye")
                                .font(.system(size: 11))
                                .foregroundStyle(accent)
                            Text("What's being sent")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                            Spacer()

                            // Copy button
                            Button {
                                copyApiPayload()
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: copiedPayload ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 9))
                                    Text(copiedPayload ? "Copied" : "Copy")
                                        .font(.system(size: 9))
                                }
                                .foregroundStyle(copiedPayload ? .green : .secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.gray.opacity(0.08), in: Capsule())
                            }
                            .buttonStyle(.plain)

                            Image(systemName: apiDetailsExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    // Collapsed: one-line summary
                    if !apiDetailsExpanded {
                        let params = conversation.chatParameters.merging(
                            over: chatManager.providers.defaultParameters(for: providerId)
                        )
                        HStack(spacing: 8) {
                            apiPill("system", !effectiveSystemPrompt.isEmpty)
                            if supportedParams.contains("temperature") {
                                apiPill("temp \(params.temperature.map { String(format: "%.1f", $0) } ?? "default")", params.temperature != nil)
                            }
                            if supportedParams.contains("maxTokens") {
                                apiPill("max \(params.maxTokens.map { "\($0)" } ?? "default")", params.maxTokens != nil)
                            }
                            Spacer()
                        }
                        .font(.system(size: 9, design: .monospaced))
                    }

                    // Expanded: full API payload
                    if apiDetailsExpanded {
                        let params = conversation.chatParameters.merging(
                            over: chatManager.providers.defaultParameters(for: providerId)
                        )

                        Text("The actual values included in the API request for this conversation. Tap Copy to grab the full payload.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(buildPayloadString(params: params))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .lineSpacing(2)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.08), lineWidth: 1))
                    }
                }

                // MARK: - Navigate to Settings
                Divider()

                Button {
                    chatManager.settingsTab = "prompts"
                    openSettings()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Configure Provider Defaults")
                                .font(.system(size: 11, weight: .medium))
                            Text("Set default system prompts and parameters for all \(providerName) conversations in Settings → Prompts")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(accent.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .frame(width: 400)
        .frame(maxHeight: 600)
    }

    // MARK: - Helpers

    private func savePresetName() {
        let name = presetNameInput.replacingOccurrences(of: " ", with: "")
        guard !name.isEmpty else { return }
        conversation.savedPresetName = String(name.prefix(16))
        isNamingPreset = false
        presetNameInput = ""
    }

    private func promptChip(_ label: String, _ prompt: String) -> some View {
        Button {
            conversation.systemPrompt = prompt
            // Clear the saved preset name when switching to a known template
            conversation.savedPresetName = nil
        } label: {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    conversation.systemPrompt == prompt && !prompt.isEmpty
                    ? accent.opacity(0.12) : Color.gray.opacity(0.08),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private func apiRow(_ key: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(value.contains("default") || value == "none" ? .tertiary : .primary)
                .lineLimit(1)
        }
    }

    private func apiPill(_ text: String, _ isSet: Bool) -> some View {
        Text(text)
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(isSet ? .primary : .tertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                isSet ? accent.opacity(0.08) : Color.gray.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 4)
            )
    }

    private func buildPayloadString(params: ChatParameters) -> String {
        var lines: [String] = []
        lines.append("// \(providerName) API Request")
        lines.append("")
        if !effectiveSystemPrompt.isEmpty {
            lines.append("system: \"\(effectiveSystemPrompt)\"")
            lines.append("")
        }
        if let t = params.temperature { lines.append("temperature: \(String(format: "%.1f", t))") }
        if let m = params.maxTokens { lines.append("max_tokens: \(m)") }
        if let p = params.topP { lines.append("top_p: \(String(format: "%.2f", p))") }
        if let f = params.frequencyPenalty { lines.append("frequency_penalty: \(String(format: "%.1f", f))") }
        if let p = params.presencePenalty { lines.append("presence_penalty: \(String(format: "%.1f", p))") }

        // Show defaults for unset params
        if params.temperature == nil && supportedParams.contains("temperature") {
            lines.append("temperature: (provider default)")
        }
        if params.maxTokens == nil && supportedParams.contains("maxTokens") {
            lines.append("max_tokens: (provider default)")
        }
        if params.topP == nil && supportedParams.contains("topP") {
            lines.append("top_p: (provider default)")
        }

        return lines.joined(separator: "\n")
    }

    private func copyApiPayload() {
        let params = conversation.chatParameters.merging(
            over: chatManager.providers.defaultParameters(for: providerId)
        )
        let payload = buildPayloadString(params: params)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
        copiedPayload = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copiedPayload = false
        }
    }

    @ViewBuilder
    private func paramValueBadge(_ value: String?) -> some View {
        if let val = value {
            HStack(spacing: 3) {
                Text(val)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(accent)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(accent)
            }
        } else {
            Text("default")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Parameter Card

struct ParamCard<Control: View, ValueDisplay: View>: View {
    let name: String
    let description: String
    let accent: Color
    @ViewBuilder let control: Control
    @ViewBuilder let valueDisplay: ValueDisplay
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                Spacer()
                valueDisplay
                Button {
                    onClear()
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reset to provider default")
            }

            Text(description)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            control
        }
        .padding(10)
        .background(Color.gray.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.08), lineWidth: 1))
    }
}
