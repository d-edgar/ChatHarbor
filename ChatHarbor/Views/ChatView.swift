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
    @FocusState private var inputFocused: Bool

    private var accent: Color {
        chatManager.currentTheme.accentColor(for: colorScheme)
    }

    private var isDark: Bool { colorScheme == .dark }

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

                if !conversation.systemPrompt.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "text.book.closed")
                            .font(.system(size: 10))
                        Text("System prompt active")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary.opacity(0.3), in: Capsule())
                    .help(conversation.systemPrompt)
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

                                    // Fork
                                    Button {
                                        let _ = chatManager.forkConversation(
                                            conversation,
                                            atMessage: message,
                                            in: modelContext
                                        )
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
                        // Model icon hint
                        let info = chatManager.providers.providerInfo(for: chatManager.selectedModelId)
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

    private var isUser: Bool { message.role == .user }
    private var isDark: Bool { colorScheme == .dark }

    private var accent: Color {
        chatManager.currentTheme.accentColor(for: colorScheme)
    }

    /// Friendly name for the model powering this message
    private var modelInfo: (providerName: String, modelName: String, icon: String) {
        let qualifiedId = message.conversation?.modelId ?? chatManager.selectedModelId
        return chatManager.providers.providerInfo(for: qualifiedId)
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
                } else {
                    Text(LocalizedStringKey(message.content))
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .lineSpacing(3)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    isUser
                                        ? accent.opacity(isDark ? 0.25 : 0.15)
                                        : (isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                                )
                        )
                }

                // Metadata (tokens, duration)
                if let tokens = message.tokenCount, let duration = message.durationMs, !isUser {
                    HStack(spacing: 6) {
                        Text("\(tokens) tokens")
                        if duration > 0 {
                            Text("·")
                            Text(formatDuration(duration))
                        }
                        if tokens > 0 && duration > 0 {
                            Text("·")
                            Text("\(String(format: "%.1f", Double(tokens) / (duration / 1000.0))) tok/s")
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
                    .padding(.leading, 4)
                }
            }
            .frame(maxWidth: 520, alignment: isUser ? .trailing : .leading)
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    private func formatDuration(_ ms: Double) -> String {
        if ms < 1000 {
            return "\(Int(ms))ms"
        } else {
            return String(format: "%.1fs", ms / 1000.0)
        }
    }
}
