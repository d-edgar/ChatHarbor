import SwiftUI
import SwiftData

// MARK: - Ship Chat View
//
// The main interface when a Ship is selected. Shows the Ship's identity,
// its conversations, and the active chat. All conversations within a Ship
// automatically inherit its model, parameters, system prompt, and cargo.

struct ShipChatView: View {
    @Bindable var ship: Ship
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @State private var inputText: String = ""
    @State private var isStreaming: Bool = false
    @State private var streamingContent: String = ""
    @State private var showingEditor: Bool = false
    @FocusState private var inputFocused: Bool

    private var accent: Color {
        Color(hex: ship.colorHex) ?? .blue
    }

    private var isDark: Bool { colorScheme == .dark }

    /// The active conversation (most recent, or the one selected via ChatManager)
    private var activeConversation: ShipConversation? {
        if let selectedId = chatManager.selectedShipConversationId {
            return ship.conversations.first(where: { $0.id == selectedId })
        }
        return ship.sortedConversations.first
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Ship Header
            shipHeader

            Divider()

            if ship.modelId.isEmpty {
                // Ship not configured yet — show setup prompt
                unconfiguredState
            } else if let conversation = activeConversation {
                // Active conversation
                conversationView(conversation)
            } else {
                // No conversations yet — show welcome
                emptyState
            }
        }
    }

    // MARK: - Ship Header

    private var shipHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: ship.icon)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(accent, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(ship.name)
                    .font(.system(size: 14, weight: .semibold))
                if !ship.tagline.isEmpty {
                    Text(ship.tagline)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Model badge
            if !ship.modelId.isEmpty {
                let info = chatManager.providers.providerInfo(for: ship.modelId)
                HStack(spacing: 4) {
                    Image(systemName: info.icon)
                        .font(.system(size: 9))
                    Text(info.modelName)
                        .font(.system(size: 10))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary.opacity(0.3), in: Capsule())
            }

            // Cargo indicator
            let cargoCount = ship.cargoItems.count + (ship.knowledgeText.isEmpty ? 0 : 1)
            if cargoCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 9))
                    Text("\(cargoCount)")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.quaternary.opacity(0.3), in: Capsule())
                .help("Cargo: \(cargoCount) knowledge sources loaded")
            }

            // Conversation count & new
            HStack(spacing: 6) {
                if ship.conversations.count > 1 {
                    Menu {
                        ForEach(ship.sortedConversations) { conv in
                            Button {
                                chatManager.selectedShipConversationId = conv.id
                            } label: {
                                Text(conv.title == "New Conversation" ? conv.autoTitle : conv.title)
                            }
                        }

                        Divider()

                        Button {
                            startNewConversation()
                        } label: {
                            Label("New Conversation", systemImage: "plus")
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 9))
                            Text("\(ship.conversations.count)")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.3), in: Capsule())
                    }
                }

                Button {
                    startNewConversation()
                } label: {
                    Image(systemName: "plus.bubble")
                        .font(.system(size: 12))
                        .foregroundStyle(accent)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New conversation in this Ship")
            }

            // Edit ship
            Button {
                showingEditor = true
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit Ship settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .sheet(isPresented: $showingEditor) {
            ShipBuilderView(
                ship: ship,
                isNew: false,
                onSave: {
                    try? modelContext.save()
                    showingEditor = false
                },
                onCancel: {
                    showingEditor = false
                }
            )
            .environmentObject(chatManager)
            .frame(minWidth: 600, minHeight: 500)
        }
    }

    // MARK: - Conversation View

    private func conversationView(_ conversation: ShipConversation) -> some View {
        VStack(spacing: 0) {
            // Message list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(conversation.sortedMessages) { message in
                            shipMessageBubble(message)
                                .id(message.id)
                        }

                        // Streaming indicator
                        if isStreaming {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: ship.icon)
                                    .font(.system(size: 11))
                                    .foregroundStyle(accent)
                                    .frame(width: 26, height: 26)
                                    .background(accent.opacity(0.1), in: Circle())

                                VStack(alignment: .leading, spacing: 3) {
                                    if streamingContent.isEmpty {
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
                                    } else {
                                        MarkdownText(content: streamingContent)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 16)
                                                    .fill(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                                            )
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 6)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: conversation.messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: streamingContent) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onAppear {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }

            Divider()

            // Input bar
            HStack(spacing: 10) {
                TextField("Message \(ship.name)…", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...8)
                    .focused($inputFocused)
                    .onSubmit {
                        if !inputText.isEmpty && !isStreaming {
                            sendMessage()
                        }
                    }

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(isStreaming ? .red : accent)
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Message Bubble

    private func shipMessageBubble(_ message: ShipMessage) -> some View {
        let isUser = message.role == .user

        return HStack(alignment: .top, spacing: 10) {
            if !isUser {
                Image(systemName: ship.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(accent)
                    .frame(width: 26, height: 26)
                    .background(accent.opacity(0.1), in: Circle())
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
                if isUser {
                    Text(message.content)
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
            }
            .frame(maxWidth: 520, alignment: isUser ? .trailing : .leading)
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    // MARK: - Empty / Unconfigured States

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: ship.icon)
                .font(.system(size: 40))
                .foregroundStyle(accent.opacity(0.5))

            Text("Start a conversation with \(ship.name)")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            if !ship.tagline.isEmpty {
                Text(ship.tagline)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }

            // Show cargo summary
            let cargoCount = ship.cargoItems.count + (ship.knowledgeText.isEmpty ? 0 : 1)
            if cargoCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 10))
                    Text("\(cargoCount) knowledge sources loaded · ~\(formatTokens(ship.estimatedContextTokens)) context tokens")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Input bar at bottom
            Divider()

            HStack(spacing: 10) {
                TextField("Message \(ship.name)…", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...8)
                    .focused($inputFocused)
                    .onSubmit { sendMessage() }

                Button { sendMessage() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(accent)
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var unconfiguredState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.5))

            Text("This Ship needs a model")
                .font(.system(size: 14, weight: .medium))

            Text("Open the Ship editor to choose a base model and configure its personality.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Button("Edit Ship") {
                showingEditor = true
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)

            Spacer()
        }
    }

    // MARK: - Actions

    private func startNewConversation() {
        let conversation = ShipConversation(title: "New Conversation")
        ship.conversations.append(conversation)
        chatManager.selectedShipConversationId = conversation.id
        try? modelContext.save()
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming, !ship.modelId.isEmpty else { return }

        // Ensure we have a conversation
        let conversation: ShipConversation
        if let active = activeConversation {
            conversation = active
        } else {
            conversation = ShipConversation(title: "New Conversation")
            ship.conversations.append(conversation)
            chatManager.selectedShipConversationId = conversation.id
        }

        // Add user message
        let userMessage = ShipMessage(role: .user, content: text)
        conversation.messages.append(userMessage)
        conversation.updatedAt = Date()

        // Auto-title
        if conversation.title == "New Conversation" {
            conversation.title = conversation.autoTitle
        }

        inputText = ""
        isStreaming = true
        streamingContent = ""

        // Build messages for the API
        var apiMessages: [ChatMessage] = []

        // System prompt (Ship's resolved prompt with cargo)
        let systemPrompt = ship.resolvedSystemPrompt
        if !systemPrompt.isEmpty {
            apiMessages.append(ChatMessage(role: .system, content: systemPrompt))
        }

        // Conversation history
        for msg in conversation.sortedMessages {
            let role: ChatMessageRole = msg.role == .user ? .user : .assistant
            apiMessages.append(ChatMessage(role: role, content: msg.content))
        }

        // Stream response
        Task {
            do {
                let result = try await chatManager.providers.chat(
                    qualifiedModelId: ship.modelId,
                    messages: apiMessages,
                    parameters: ship.chatParameters
                ) { token in
                    streamingContent += token
                }

                // Save assistant message
                let assistantMessage = ShipMessage(
                    role: .assistant,
                    content: result.content,
                    modelUsed: ship.modelId
                )
                assistantMessage.tokenCount = result.tokenCount
                assistantMessage.inputTokenCount = result.inputTokenCount
                assistantMessage.durationMs = result.durationMs
                conversation.messages.append(assistantMessage)
                conversation.updatedAt = Date()
                ship.updatedAt = Date()
                try? modelContext.save()
            } catch {
                let errorMessage = ShipMessage(
                    role: .assistant,
                    content: "Error: \(error.localizedDescription)"
                )
                conversation.messages.append(errorMessage)
            }

            isStreaming = false
            streamingContent = ""
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        }
        return "\(count)"
    }
}
