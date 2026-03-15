import SwiftUI
import SwiftData

// MARK: - Sidebar View
//
// Shows the conversation list, model picker, and settings/about links.

struct SidebarView: View {
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @Binding var isExpanded: Bool
    @State private var showingAboutPopover = false
    @State private var searchText = ""

    private var filteredConversations: [Conversation] {
        if searchText.isEmpty { return conversations }
        return conversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            if isExpanded {
                HStack {
                    Button {
                        chatManager.selectedConversationId = nil
                    } label: {
                        HStack(spacing: 6) {
                            Image("ChatHarborLogo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20)
                                .clipShape(RoundedRectangle(cornerRadius: 4))

                            Text("ChatHarbor")
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Home")

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Collapse sidebar")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Expand sidebar")
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
            }

            Divider()

            // MARK: - New Chat Button
            if isExpanded {
                Button {
                    let conversation = chatManager.createConversation(in: modelContext)
                    chatManager.selectedConversationId = conversation.id
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.bubble")
                            .font(.system(size: 13))
                        Text("New Chat")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("⌘N")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.quaternary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.top, 8)
            } else {
                Button {
                    let conversation = chatManager.createConversation(in: modelContext)
                    chatManager.selectedConversationId = conversation.id
                } label: {
                    Image(systemName: "plus.bubble")
                        .font(.system(size: 17))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("New Chat (⌘N)")
                .padding(.top, 8)
            }

            // MARK: - Search
            if isExpanded && conversations.count > 5 {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    TextField("Search…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 10)
                .padding(.top, 8)
            }

            // MARK: - Conversation List
            ScrollView {
                LazyVStack(spacing: 2) {
                    if isExpanded {
                        ForEach(groupedConversations, id: \.label) { group in
                            if !group.conversations.isEmpty {
                                HStack {
                                    Text(group.label.uppercased())
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.top, 12)
                                .padding(.bottom, 4)

                                ForEach(group.conversations) { conversation in
                                    ConversationRow(
                                        conversation: conversation,
                                        isSelected: chatManager.selectedConversationId == conversation.id
                                    ) {
                                        chatManager.selectedConversationId = conversation.id
                                    }
                                    .contextMenu {
                                        Button("Delete", role: .destructive) {
                                            chatManager.deleteConversation(conversation, in: modelContext)
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        ForEach(filteredConversations) { conversation in
                            CompactConversationRow(
                                conversation: conversation,
                                isSelected: chatManager.selectedConversationId == conversation.id
                            ) {
                                chatManager.selectedConversationId = conversation.id
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Spacer(minLength: 0)

            Divider()

            // MARK: - Footer
            VStack(spacing: 0) {
                if isExpanded {
                    // Model picker
                    ModelPickerRow()
                        .environmentObject(chatManager)

                    Divider()
                        .padding(.horizontal, 14)

                    SettingsLink {
                        HStack(spacing: 8) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 13))
                                .frame(width: 22, height: 22)
                                .foregroundStyle(.secondary)
                            Text("Settings")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .padding(.horizontal, 14)

                    Button {
                        showingAboutPopover.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            Image("ChatHarborLogo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 22, height: 22)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                            Text("About")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("v2.0.0")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingAboutPopover, arrowEdge: .trailing) {
                        AboutPopoverView()
                    }
                } else {
                    SettingsLink {
                        Image(systemName: "gearshape")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                }
            }
            .padding(.bottom, 4)
        }
        .frame(width: isExpanded ? 220 : 52)
        .background(chatManager.currentTheme.sidebarColor(for: colorScheme))
    }

    // MARK: - Grouped Conversations

    private struct ConversationGroup {
        let label: String
        let conversations: [Conversation]
    }

    private var groupedConversations: [ConversationGroup] {
        let now = Date()
        let calendar = Calendar.current

        var today: [Conversation] = []
        var yesterday: [Conversation] = []
        var thisWeek: [Conversation] = []
        var older: [Conversation] = []

        for conv in filteredConversations {
            if calendar.isDateInToday(conv.updatedAt) {
                today.append(conv)
            } else if calendar.isDateInYesterday(conv.updatedAt) {
                yesterday.append(conv)
            } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now),
                      conv.updatedAt > weekAgo {
                thisWeek.append(conv)
            } else {
                older.append(conv)
            }
        }

        return [
            ConversationGroup(label: "Today", conversations: today),
            ConversationGroup(label: "Yesterday", conversations: yesterday),
            ConversationGroup(label: "This Week", conversations: thisWeek),
            ConversationGroup(label: "Older", conversations: older),
        ]
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool
    let action: () -> Void
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color {
        chatManager.currentTheme.accentColor(for: colorScheme)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? accent : .secondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .font(.system(size: 13))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)

                    Text(conversation.updatedAt.formatted(.relative(presentation: .named)))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Text("\(conversation.messages.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isSelected
                    ? AnyShapeStyle(accent.opacity(0.15))
                    : AnyShapeStyle(.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }
}

// MARK: - Compact Conversation Row

struct CompactConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool
    let action: () -> Void
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color {
        chatManager.currentTheme.accentColor(for: colorScheme)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "bubble.left")
                .font(.system(size: 15))
                .frame(width: 36, height: 36)
                .foregroundStyle(isSelected ? accent : .secondary)
                .background(
                    isSelected
                        ? AnyShapeStyle(accent.opacity(0.15))
                        : AnyShapeStyle(.clear)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .help(conversation.title)
    }
}

// MARK: - Model Picker Row

struct ModelPickerRow: View {
    @EnvironmentObject var chatManager: ChatManager

    /// Models grouped by provider label for the menu
    private var groupedModels: [(provider: String, icon: String, models: [ProviderModel])] {
        let providers = chatManager.providers

        var groups: [(provider: String, icon: String, models: [ProviderModel])] = []

        let ollamaModels = providers.ollama.models
        if !ollamaModels.isEmpty {
            groups.append((provider: "Ollama (Local)", icon: "desktopcomputer", models: ollamaModels))
        }

        let openAIModels = providers.openAI.models
        if !openAIModels.isEmpty {
            groups.append((provider: "OpenAI", icon: "brain", models: openAIModels))
        }

        let anthropicModels = providers.anthropic.models
        if !anthropicModels.isEmpty {
            groups.append((provider: "Anthropic", icon: "sparkle", models: anthropicModels))
        }

        return groups
    }

    var body: some View {
        Menu {
            if chatManager.providers.allModels.isEmpty {
                Text("No models available")
                Divider()
                Button("Open Model Manager…") {
                    chatManager.showingModelManager = true
                }
            } else {
                ForEach(groupedModels, id: \.provider) { group in
                    Section(group.provider) {
                        ForEach(group.models) { model in
                            Button {
                                chatManager.selectModel(model.id)
                            } label: {
                                HStack {
                                    Image(systemName: model.isLocal ? "desktopcomputer" : "cloud")
                                    Text(model.displayName)
                                    if model.id == chatManager.selectedModelId {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
                Divider()
                Button("Manage Models…") {
                    chatManager.showingModelManager = true
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selectedIcon)
                    .font(.system(size: 13))
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Model")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(selectedDisplayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var selectedDisplayName: String {
        let qualifiedId = chatManager.selectedModelId
        if qualifiedId.isEmpty { return "None" }
        if let model = chatManager.providers.allModels.first(where: { $0.id == qualifiedId }) {
            return model.displayName
        }
        // Fallback: strip provider prefix or :latest suffix
        let parts = qualifiedId.split(separator: ":", maxSplits: 1)
        if parts.count == 2 { return String(parts[1]) }
        if qualifiedId.hasSuffix(":latest") { return String(qualifiedId.dropLast(7)) }
        return qualifiedId
    }

    private var selectedIcon: String {
        let qualifiedId = chatManager.selectedModelId
        if let model = chatManager.providers.allModels.first(where: { $0.id == qualifiedId }) {
            return model.isLocal ? "desktopcomputer" : "cloud"
        }
        return "cpu"
    }
}

// MARK: - About Popover

struct AboutPopoverView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image("ChatHarborLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 3, y: 2)

            Text("ChatHarbor")
                .font(.headline)

            Text("Version 2.0.0")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("One native macOS app for all your AI.\nOllama · OpenAI · Anthropic")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Link(destination: URL(string: "https://github.com/d-edgar/ChatHarbor")!) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.caption)
                }
                Link(destination: URL(string: "https://buymeacoffee.com/dedgar")!) {
                    Label("Support", systemImage: "cup.and.saucer")
                        .font(.caption)
                }
            }
            .padding(.top, 4)

            Text("MIT License · David Edgar")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 260)
    }
}
