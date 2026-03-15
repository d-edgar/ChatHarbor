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
    @State private var showingExportAlert: Bool = false
    @State private var exportedMarkdown: String = ""
    @FocusState private var inputFocused: Bool
    @Namespace private var bottomAnchor

    private var accent: Color {
        chatManager.currentTheme.accentColor(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Chat Header
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    if conversation.isForked {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 9))
                            Text("Forked conversation")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.tertiary)
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
                    LazyVStack(spacing: 0) {
                        ForEach(conversation.sortedMessages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                                .contextMenu {
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(message.content, forType: .string)
                                    } label: {
                                        Label("Copy Text", systemImage: "doc.on.doc")
                                    }

                                    Divider()

                                    Button {
                                        let _ = chatManager.forkConversation(
                                            conversation,
                                            atMessage: message,
                                            in: modelContext
                                        )
                                    } label: {
                                        Label("Fork Here (Same Model)", systemImage: "arrow.triangle.branch")
                                    }

                                    // Fork to different provider/model
                                    Menu("Fork to Model…") {
                                        ForEach(chatManager.providers.allModels) { model in
                                            Button {
                                                let fork = chatManager.forkConversation(
                                                    conversation,
                                                    atMessage: message,
                                                    in: modelContext
                                                )
                                                fork.modelId = model.id
                                                fork.title = "Fork → \(model.displayName)"
                                                try? modelContext.save()
                                            } label: {
                                                Label(
                                                    "\(model.displayName)",
                                                    systemImage: model.isLocal ? "desktopcomputer" : "cloud"
                                                )
                                            }
                                        }
                                    }

                                    Divider()

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
                    .padding(.vertical, 16)
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

            Divider()

            // MARK: - Input Area
            HStack(alignment: .bottom, spacing: 12) {
                // Model indicator
                if !chatManager.selectedModelId.isEmpty {
                    ModelBadge(modelName: chatManager.selectedModelId)
                }

                // Text input
                TextField("Message…", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...10)
                    .focused($inputFocused)
                    .onSubmit {
                        if !NSEvent.modifierFlags.contains(.shift) {
                            send()
                        }
                    }
                    .font(.body)
                    .padding(.vertical, 8)

                // Send / Stop button
                if chatManager.isGenerating {
                    Button {
                        chatManager.stopGenerating()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Stop generating")
                } else {
                    Button {
                        send()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)
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

// MARK: - Model Badge

struct ModelBadge: View {
    let modelName: String

    private var displayName: String {
        if modelName.hasSuffix(":latest") {
            return String(modelName.dropLast(7))
        }
        return modelName
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "cpu")
                .font(.system(size: 9))
            Text(displayName)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.5), in: Capsule())
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: Message
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.colorScheme) private var colorScheme

    private var isUser: Bool { message.role == .user }
    private var accent: Color {
        chatManager.currentTheme.accentColor(for: colorScheme)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                // Role label
                HStack(spacing: 4) {
                    Image(systemName: isUser ? "person.fill" : "cpu")
                        .font(.system(size: 10))
                    Text(isUser ? "You" : modelDisplayName)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.secondary)

                // Message content
                if message.isStreaming && message.content.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Thinking…")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.quaternary.opacity(0.3))
                    )
                } else {
                    Text(LocalizedStringKey(message.content))
                        .font(.body)
                        .textSelection(.enabled)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isUser ? accent.opacity(0.12) : Color.gray.opacity(0.15))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    isUser ? accent.opacity(0.2) : Color.clear,
                                    lineWidth: 1
                                )
                        )
                }

                // Metadata (tokens, duration)
                if let tokens = message.tokenCount, let duration = message.durationMs, !isUser {
                    HStack(spacing: 8) {
                        Text("\(tokens) tokens")
                        Text("·")
                        Text(formatDuration(duration))
                        if tokens > 0 && duration > 0 {
                            Text("·")
                            Text("\(String(format: "%.1f", Double(tokens) / (duration / 1000.0))) tok/s")
                        }
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.quaternary)
                }
            }

            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
    }

    private var modelDisplayName: String {
        let name = message.conversation?.modelId ?? chatManager.selectedModelId
        if name.hasSuffix(":latest") {
            return String(name.dropLast(7))
        }
        return name.isEmpty ? "Assistant" : name
    }

    private func formatDuration(_ ms: Double) -> String {
        if ms < 1000 {
            return "\(Int(ms))ms"
        } else {
            return String(format: "%.1fs", ms / 1000.0)
        }
    }
}
