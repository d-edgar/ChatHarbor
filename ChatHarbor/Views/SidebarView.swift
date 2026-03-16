import SwiftUI
import SwiftData

// MARK: - Sidebar View
//
// Shows the conversation list, model picker, and settings/about links.

struct SidebarView: View {
    @EnvironmentObject var chatManager: ChatManager
    @EnvironmentObject var brainstormManager: BrainstormManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @Query(sort: \BrainstormSession.updatedAt, order: .reverse) private var brainstormSessions: [BrainstormSession]
    @Binding var isExpanded: Bool
    @Binding var sidebarWidth: CGFloat
    @State private var showingAboutPopover = false
    @State private var searchText = ""
    @State private var collapsedForkParents: Set<UUID> = []
    @State private var brainstormsCollapsed: Bool = false

    private var filteredConversations: [Conversation] {
        if searchText.isEmpty { return conversations }
        return conversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// All conversations that are forks, keyed by ROOT ancestor ID.
    /// This ensures fork-of-forks nest under the original conversation,
    /// not under an intermediate fork that's itself nested.
    private var forksByParent: [UUID: [Conversation]] {
        let allConvs = filteredConversations
        let byId = Dictionary(uniqueKeysWithValues: allConvs.map { ($0.id, $0) })

        // Walk up the fork chain to find the root ancestor
        func rootAncestorId(of conv: Conversation) -> UUID {
            var current = conv
            while let parentId = current.forkedFromId,
                  let parent = byId[parentId] {
                current = parent
            }
            return current.id
        }

        return Dictionary(grouping: allConvs.filter { $0.isForked }) {
            rootAncestorId(of: $0)
        }
    }

    /// Top-level conversations (not forks)
    private var rootConversations: [Conversation] {
        filteredConversations.filter { !$0.isForked }
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

            // MARK: - New Chat / Brainstorm Buttons
            if isExpanded {
                HStack(spacing: 4) {
                    Button {
                        chatManager.selectedBrainstormId = nil
                        let conversation = chatManager.createConversation(in: modelContext)
                        chatManager.selectedConversationId = conversation.id
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.bubble")
                                .font(.system(size: 12))
                            Text("Chat")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Button {
                        chatManager.selectedConversationId = nil
                        let session = brainstormManager.createSession(
                            topic: "",
                            participants: [],
                            in: modelContext
                        )
                        chatManager.selectedBrainstormId = session.id
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 12))
                            Text("Brainstorm")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.horizontal, 4)
                .padding(.top, 8)
            } else {
                VStack(spacing: 4) {
                    Button {
                        chatManager.selectedBrainstormId = nil
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

                    Button {
                        chatManager.selectedConversationId = nil
                        let session = brainstormManager.createSession(
                            topic: "",
                            participants: [],
                            in: modelContext
                        )
                        chatManager.selectedBrainstormId = session.id
                    } label: {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 17))
                            .frame(width: 36, height: 36)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("New Brainstorm (⇧⌘B)")
                }
                .padding(.top, 8)
            }

            // MARK: - Search
            if isExpanded && conversations.count > 5 {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
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
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.top, 12)
                                .padding(.bottom, 4)

                                ForEach(group.conversations) { conversation in
                                    // Parent conversation row
                                    conversationRow(for: conversation)

                                    // Nested forks
                                    if let forks = forksByParent[conversation.id],
                                       !collapsedForkParents.contains(conversation.id) {
                                        ForEach(forks) { fork in
                                            ForkRow(
                                                conversation: fork,
                                                parentTitle: conversation.title,
                                                isSelected: chatManager.selectedConversationId == fork.id
                                            ) {
                                                chatManager.selectedConversationId = fork.id
                                            }
                                            .contextMenu {
                                                Button {
                                                    chatManager.selectedConversationId = conversation.id
                                                } label: {
                                                    Label("Go to Parent", systemImage: "arrow.turn.left.up")
                                                }

                                                Divider()

                                                Button("Delete Fork", role: .destructive) {
                                                    chatManager.deleteConversation(fork, in: modelContext)
                                                }
                                            }
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

                // MARK: - Brainstorm Sessions
                if isExpanded && !brainstormSessions.isEmpty {
                    Divider()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)

                    HStack {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                brainstormsCollapsed.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: brainstormsCollapsed ? "chevron.right" : "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 14, height: 14)

                                Image(systemName: "brain.head.profile")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)

                                Text("BRAINSTORMS")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Text("\(brainstormSessions.count)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 4)

                    if !brainstormsCollapsed {
                        ForEach(brainstormSessions) { session in
                            BrainstormSessionRow(
                                session: session,
                                isSelected: chatManager.selectedBrainstormId == session.id
                            ) {
                                chatManager.selectedConversationId = nil
                                chatManager.selectedBrainstormId = session.id
                            }
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    brainstormManager.deleteSession(session, in: modelContext)
                                }
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            Divider()

            // MARK: - Footer
            VStack(spacing: 0) {
                if isExpanded {
                    // Model picker — shows the conversation's model if one is selected
                    ModelPickerRow(
                        conversationModelId: conversations.first(where: { $0.id == chatManager.selectedConversationId })?.modelId
                    )
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
                                .foregroundStyle(.secondary)
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
        .frame(width: isExpanded ? sidebarWidth : 52)
        .background(chatManager.currentTheme.sidebarColor(for: colorScheme))
    }

    // MARK: - Conversation Row Builder

    @ViewBuilder
    private func conversationRow(for conversation: Conversation) -> some View {
        let hasForks = forksByParent[conversation.id] != nil
        let isCollapsed = collapsedForkParents.contains(conversation.id)
        let forkCount = forksByParent[conversation.id]?.count ?? 0

        ConversationRow(
            conversation: conversation,
            isSelected: chatManager.selectedConversationId == conversation.id,
            hasForks: hasForks,
            forksCollapsed: isCollapsed,
            forkCount: forkCount,
            onToggleForks: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if collapsedForkParents.contains(conversation.id) {
                        collapsedForkParents.remove(conversation.id)
                    } else {
                        collapsedForkParents.insert(conversation.id)
                    }
                }
            }
        ) {
            chatManager.selectedConversationId = conversation.id
        }
        .contextMenu {
            if hasForks {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if collapsedForkParents.contains(conversation.id) {
                            collapsedForkParents.remove(conversation.id)
                        } else {
                            collapsedForkParents.insert(conversation.id)
                        }
                    }
                } label: {
                    Label(
                        isCollapsed ? "Show \(forkCount) Fork\(forkCount == 1 ? "" : "s")" : "Hide Forks",
                        systemImage: isCollapsed ? "arrow.triangle.branch" : "eye.slash"
                    )
                }

                Divider()
            }

            Button("Delete", role: .destructive) {
                chatManager.deleteConversation(conversation, in: modelContext)
            }
        }
    }

    // MARK: - Grouped Conversations (roots only)

    private struct ConversationGroup {
        let label: String
        let conversations: [Conversation]
    }

    private var groupedConversations: [ConversationGroup] {
        let calendar = Calendar.current
        let now = Date()

        var today: [Conversation] = []
        var yesterday: [Conversation] = []
        var thisWeek: [Conversation] = []
        var older: [Conversation] = []

        for conv in rootConversations {
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
    var hasForks: Bool = false
    var forksCollapsed: Bool = false
    var forkCount: Int = 0
    var onToggleForks: (() -> Void)?
    let action: () -> Void
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color {
        chatManager.currentTheme.accentColor(for: colorScheme)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // Fork disclosure toggle
                if hasForks {
                    Button {
                        onToggleForks?()
                    } label: {
                        Image(systemName: forksCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer()
                        .frame(width: 14)
                }

                Image(systemName: "bubble.left")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? accent : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .font(.system(size: 12))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(conversation.updatedAt.formatted(.relative(presentation: .named)))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)

                        if hasForks {
                            Text("·")
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                            Text("\(forkCount)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                Text("\(conversation.messages.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
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

// MARK: - Fork Row (indented child)

struct ForkRow: View {
    let conversation: Conversation
    let parentTitle: String
    let isSelected: Bool
    let action: () -> Void
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color {
        chatManager.currentTheme.accentColor(for: colorScheme)
    }

    /// Friendly model name for this fork
    private var modelName: String {
        let id = conversation.modelId
        if id.isEmpty { return "" }
        return chatManager.providers.providerInfo(for: id).modelName
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                // Indent + branch line
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(.tertiary.opacity(0.3))
                        .frame(width: 1, height: 24)
                        .padding(.leading, 20)

                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 2)
                }

                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? accent : accent.opacity(0.5))

                VStack(alignment: .leading, spacing: 1) {
                    Text(forkDisplayTitle)
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        if !modelName.isEmpty {
                            Text(modelName)
                                .font(.system(size: 9))
                                .foregroundStyle(accent.opacity(0.7))
                        }
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text("\(conversation.messages.count) msgs")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                isSelected
                    ? AnyShapeStyle(accent.opacity(0.12))
                    : AnyShapeStyle(.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }

    /// Strip common fork prefixes to keep it clean
    private var forkDisplayTitle: String {
        var title = conversation.title
        // Strip "Fork: " or custom prefix
        let prefix = chatManager.forkPrefix
        if title.hasPrefix(prefix) {
            title = String(title.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        // If it starts with the parent title, just show what's different
        if title == parentTitle {
            return modelName.isEmpty ? "Fork" : modelName
        }
        return title
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
            Image(systemName: conversation.isForked ? "arrow.triangle.branch" : "bubble.left")
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
    /// The conversation-level model override, if any
    var conversationModelId: String? = nil

    /// The effective model for display and selection
    private var effectiveModelId: String {
        if let convModel = conversationModelId, !convModel.isEmpty {
            return convModel
        }
        return chatManager.selectedModelId
    }

    /// Models grouped by provider label for the menu
    private var groupedModels: [(provider: String, icon: String, models: [ProviderModel])] {
        let providers = chatManager.providers

        var groups: [(provider: String, icon: String, models: [ProviderModel])] = []

        // Apple Intelligence (on-device)
        let appleModels = providers.apple.models
        if !appleModels.isEmpty {
            groups.append((provider: "Apple Intelligence (On-Device)", icon: providers.apple.iconName, models: appleModels))
        }

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
                Button("Set Up Providers…") {
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
                                    if model.id == effectiveModelId {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
                Divider()
                Button("Models & Providers…") {
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
                        .foregroundStyle(.secondary)
                    Text(selectedDisplayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var selectedDisplayName: String {
        if effectiveModelId.isEmpty { return "None" }
        let info = chatManager.providers.providerInfo(for: effectiveModelId)
        return info.modelName
    }

    private var selectedIcon: String {
        if effectiveModelId.isEmpty { return "cpu" }
        let info = chatManager.providers.providerInfo(for: effectiveModelId)
        return info.icon
    }
}

// MARK: - Brainstorm Session Row

struct BrainstormSessionRow: View {
    let session: BrainstormSession
    let isSelected: Bool
    let action: () -> Void
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color {
        chatManager.currentTheme.accentColor(for: colorScheme)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: session.isComplete ? "brain.head.profile.fill" : "brain.head.profile")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? accent : .secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.title.isEmpty ? "New Brainstorm" : session.title)
                        .font(.system(size: 12))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(session.method.displayName)
                            .font(.system(size: 10))
                            .foregroundStyle(accent.opacity(0.7))

                        Text("·")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)

                        Text(session.phase.badgeName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(accent.opacity(0.7))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(accent.opacity(0.08), in: Capsule())
                    }
                }

                Spacer()

                // Entry count
                Text("\(session.entries.filter { !$0.isUserInput && $0.error == nil && !$0.content.isEmpty }.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
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
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 260)
    }
}
