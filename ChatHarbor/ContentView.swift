import SwiftUI
import SwiftData
import AppKit

struct ContentView: View {
    @EnvironmentObject var chatManager: ChatManager
    @EnvironmentObject var brainstormManager: BrainstormManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openSettings) private var openSettingsFromContent
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var allConversations: [Conversation]
    @Query(sort: \BrainstormSession.updatedAt, order: .reverse) private var allBrainstormSessions: [BrainstormSession]
    @Query(sort: \Ship.updatedAt, order: .reverse) private var allShips: [Ship]
    private var conversations: [Conversation] { allConversations.filter { Harbor.contains($0.harborID, in: chatManager.selectedHarborID) } }
    private var brainstormSessions: [BrainstormSession] { allBrainstormSessions.filter { Harbor.contains($0.harborID, in: chatManager.selectedHarborID) } }
    private var ships: [Ship] { allShips.filter { Harbor.contains($0.harborID, in: chatManager.selectedHarborID) } }
    @AppStorage("hasDismissedGettingStarted") private var hasDismissedGettingStarted = false
    @State private var openModelsAfterTour = false
    @State private var sidebarExpanded: Bool = true
    @State private var sidebarWidth: CGFloat = 260

    /// The currently selected conversation, resolved from the ID
    private var selectedConversation: Conversation? {
        guard let id = chatManager.selectedConversationId else { return nil }
        return conversations.first(where: { $0.id == id })
    }

    /// The currently selected brainstorm session
    private var selectedBrainstorm: BrainstormSession? {
        guard let id = chatManager.selectedBrainstormId else { return nil }
        return brainstormSessions.first(where: { $0.id == id })
    }

    /// The currently selected Ship
    private var selectedShip: Ship? {
        guard let id = chatManager.selectedShipId else { return nil }
        return ships.first(where: { $0.id == id })
    }

    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Sidebar
            SidebarView(isExpanded: $sidebarExpanded, sidebarWidth: $sidebarWidth)
                .environmentObject(chatManager)
                .environmentObject(brainstormManager)

            // Resizable divider handle
            SidebarResizeHandle(sidebarWidth: $sidebarWidth, isExpanded: sidebarExpanded)

            // MARK: - Detail
            Group {
                if chatManager.isLaunching {
                    SplashView()
                } else if let brainstorm = selectedBrainstorm {
                    BrainstormView(session: brainstorm)
                        .id(brainstorm.id)
                        .environmentObject(brainstormManager)
                        .environmentObject(chatManager)
                } else if let ship = selectedShip {
                    ShipChatView(ship: ship)
                        .id(ship.id)
                        .environmentObject(chatManager)
                } else if let conversation = selectedConversation {
                    ChatView(conversation: conversation)
                        .id(conversation.id)
                } else {
                    WelcomeView()
                        .environmentObject(chatManager)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .tint(chatManager.currentTheme.accentColor(for: colorScheme))
        .onChange(of: chatManager.showingModelManager) { _, show in
            if show {
                chatManager.showingModelManager = false
                chatManager.settingsTab = "models"
                openSettingsFromContent()
            }
        }
        .onChange(of: chatManager.isLaunching, initial: true) { _, launching in
            if !launching && !hasDismissedGettingStarted {
                chatManager.showingGettingStarted = true
            }
        }
        .sheet(isPresented: $chatManager.showingGettingStarted, onDismiss: {
            hasDismissedGettingStarted = true
            if openModelsAfterTour {
                openModelsAfterTour = false
                chatManager.settingsTab = "models"
                openSettingsFromContent()
            }
        }) {
            GettingStartedView(canStartChat: !chatManager.providers.allModels.isEmpty, startChat: {
                if !chatManager.providers.allModels.contains(where: { $0.id == chatManager.selectedModelId }),
                   let model = chatManager.providers.allModels.first {
                    chatManager.selectModel(model.id)
                }
                chatManager.selectedBrainstormId = nil
                chatManager.selectedShipId = nil
                _ = chatManager.createConversation(in: modelContext)
                chatManager.showingGettingStarted = false
            }) { connectModel in
                openModelsAfterTour = connectModel
                chatManager.showingGettingStarted = false
            }
        }
        .sheet(isPresented: $chatManager.showingCompareView) {
            CompareView()
                .environmentObject(chatManager)
                .frame(minWidth: 700, minHeight: 500)
        }
        .sheet(isPresented: $chatManager.showingPromptLibrary) {
            PromptLibraryView()
                .environmentObject(chatManager)
                .frame(minWidth: 600, minHeight: 500)
        }
    }
}

// MARK: - Getting Started

private struct GettingStartedView: View {
    let canStartChat: Bool
    let startChat: () -> Void
    let finish: (Bool) -> Void
    @AppStorage("hasCompletedGettingStarted") private var hasCompletedGettingStarted = false
    @State private var step = 0

    private let pages: [(title: String, icon: String, text: String)] = [
        ("Connect your AI", "desktopcomputer",
         "Start with one model and one question. Connect a cloud provider with your API key, or use a downloaded model through Ollama or LM Studio. You do not need to create a harbor or build a Ship to chat."),
        ("Organize with Harbors", "building.2.crop.circle",
         "Harbors are workspaces. Start in Personal, and add Work or another area when you need it. Each harbor holds its own chats, ships, and brainstorms. Use the sidebar harbor menu to switch or create one. Right-click an item to move it. Model connections stay shared."),
        ("Build a Ship", "sailboat",
         "A Ship is a reusable assistant with its own instructions, model, and reference material. Ships are optional. For example: Work harbor → Writing Coach ship → a separate conversation for each writing task. Choose Build your first Ship when you want to reuse instructions."),
        ("Delete with confidence", "trash",
         "Right-click a chat, Ship, or brainstorm to delete it. Chat confirmations offer an optional five-minute skip; other deletions still ask. Deleting a Ship also removes its conversations and cargo.\n\nFor a fresh start, open Settings → General → Data & Storage → Delete all ChatHarbor data. Type DELETE, choose Delete & Quit, then reopen the app to finish. This resets every harbor, settings, and saved API keys.\n\nReset is not secure SSD erasure. Exports, backups, original files, provider copies, and local models remain."),
        ("Start your first chat", "bubble.left.and.bubble.right",
         "Choose a model, type a question, and send it. Try: Help me plan my week—ask me what I need to get done. After connecting a model, return to the welcome screen and choose Start a chat. You can explore Compare Models and Brainstorm later.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Getting Started").font(.headline)
                Spacer()
                Text("Step \(step + 1) of \(pages.count)").foregroundStyle(.secondary)
            }
            Label(pages[step].title, systemImage: pages[step].icon)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text(pages[step].text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            if step == 0 {
                Button(canStartChat ? "Start a chat" : "Connect a model") {
                    if canStartChat {
                        hasCompletedGettingStarted = true
                        startChat()
                    } else {
                        finish(true)
                    }
                }
            }
            Text("You can always reopen this tour from Help → Getting Started.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                Button("Skip") { finish(false) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Back") { step -= 1 }
                    .disabled(step == 0)
                if step < pages.count - 1 {
                    Button("Next") { step += 1 }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(canStartChat ? "Start a chat" : "Connect a model") {
                        hasCompletedGettingStarted = true
                        if canStartChat { startChat() } else { finish(true) }
                    }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
        .frame(width: 500)
    }
}

// MARK: - Splash Screen

struct SplashView: View {
    @State private var opacity: Double = 0
    @State private var scale: Double = 0.8

    var body: some View {
        VStack(spacing: 20) {
            ChatHarborMark()
                .frame(width: 120, height: 120)

            Text("ChatHarbor")
                .font(.system(size: 36, weight: .bold, design: .rounded))

            Text("One app for all your AI.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ProgressView()
                .scaleEffect(0.8)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(opacity)
        .scaleEffect(scale)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                opacity = 1.0
                scale = 1.0
            }
        }
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color {
        chatManager.currentTheme.accentColor(for: colorScheme)
    }

    @Environment(\.openSettings) private var openSettingsAction
    @State private var retryingProvider: String?
    @State private var retryError: String?

    private func openSettings() {
        openSettingsAction()
    }

    private func openModelsSettings() {
        chatManager.settingsTab = "models"
        openSettingsAction()
    }

    private func retryProvider(_ name: String, action: @escaping () async -> Void) {
        retryingProvider = name
        retryError = nil
        Task {
            await action()
            // Check if it actually connected
            try? await Task.sleep(for: .milliseconds(300))
            retryingProvider = nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 20)

                // Logo & tagline
                ChatHarborMark()
                    .frame(width: 80, height: 80)

                VStack(spacing: 6) {
                    Text("Welcome to ChatHarbor")
                        .font(.largeTitle)
                        .fontWeight(.semibold)

                    Text("One native macOS app for all your AI.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 10) {
                    Text("Start with one model and one question. Ships are optional reusable assistants; harbors organize your work.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button(chatManager.providers.allModels.isEmpty ? "Connect a model" : "Start a chat") {
                        if let first = chatManager.providers.allModels.first {
                            if !chatManager.providers.allModels.contains(where: { $0.id == chatManager.selectedModelId }) {
                                chatManager.selectModel(first.id)
                            }
                            _ = chatManager.createConversation(in: modelContext)
                        } else {
                            openModelsSettings()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .frame(maxWidth: 520)

                // Provider status cards
                VStack(spacing: 10) {
                    Text("YOUR PROVIDERS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Apple Intelligence (on-device)
                    ProviderCard(
                        icon: chatManager.providers.apple.iconName,
                        name: "Apple Intelligence",
                        subtitle: "On-device, private, free",
                        isConnected: chatManager.providers.apple.isConnected,
                        modelCount: chatManager.providers.apple.models.count,
                        statusText: chatManager.providers.apple.isConnected
                            ? "On-device model ready"
                            : chatManager.providers.apple.isEnabled
                                ? chatManager.providers.apple.availabilityDetail
                                : "Enable in Settings → Models",
                        isLoading: retryingProvider == "Apple",
                        actionLabel: chatManager.providers.apple.isConnected
                            ? nil
                            : chatManager.providers.apple.isEnabled ? "Retry" : "Set Up",
                        action: {
                            if !chatManager.providers.apple.isEnabled {
                                openModelsSettings()
                            } else {
                                retryProvider("Apple") {
                                    await chatManager.providers.apple.connect()
                                }
                            }
                        },
                        accent: accent
                    )

                    // Ollama (local)
                    ProviderCard(
                        icon: "desktopcomputer",
                        name: "Ollama",
                        subtitle: "Local models on your Mac",
                        isConnected: chatManager.ollama.isConnected,
                        modelCount: chatManager.ollama.availableModels.count,
                        statusText: chatManager.ollama.isConnected
                            ? "\(chatManager.ollama.availableModels.count) models ready"
                            : "Not running — open Ollama or run `ollama serve`",
                        isLoading: retryingProvider == "Ollama",
                        actionLabel: chatManager.ollama.isConnected ? nil : "Retry",
                        action: {
                            retryProvider("Ollama") {
                                await chatManager.ollama.checkConnection()
                            }
                        },
                        accent: accent
                    )

                    ProviderCard(
                        icon: "brain",
                        name: "OpenAI",
                        subtitle: "GPT-4o, o1, o3 and more",
                        isConnected: chatManager.providers.openAI.isConnected,
                        modelCount: chatManager.providers.openAI.models.count,
                        statusText: chatManager.providers.openAI.isConnected
                            ? "\(chatManager.providers.openAI.models.count) models available"
                            : chatManager.providers.openAI.apiKey.isEmpty
                                ? "Add your API key in Settings → Models"
                                : "Could not connect — check your API key",
                        isLoading: retryingProvider == "OpenAI",
                        actionLabel: chatManager.providers.openAI.isConnected
                            ? nil
                            : chatManager.providers.openAI.apiKey.isEmpty ? "Set Up" : "Retry",
                        action: {
                            if chatManager.providers.openAI.apiKey.isEmpty {
                                openModelsSettings()
                            } else {
                                retryProvider("OpenAI") {
                                    await chatManager.providers.openAI.connect()
                                }
                            }
                        },
                        accent: accent
                    )

                    ProviderCard(
                        icon: "sparkle",
                        name: "Anthropic",
                        subtitle: "Claude Sonnet, Opus, Haiku",
                        isConnected: chatManager.providers.anthropic.isConnected,
                        modelCount: chatManager.providers.anthropic.models.count,
                        statusText: chatManager.providers.anthropic.isConnected
                            ? "\(chatManager.providers.anthropic.models.count) models available"
                            : chatManager.providers.anthropic.apiKey.isEmpty
                                ? "Add your API key in Settings → Models"
                                : "Could not connect — check your API key",
                        isLoading: retryingProvider == "Anthropic",
                        actionLabel: chatManager.providers.anthropic.isConnected
                            ? nil
                            : chatManager.providers.anthropic.apiKey.isEmpty ? "Set Up" : "Retry",
                        action: {
                            if chatManager.providers.anthropic.apiKey.isEmpty {
                                openModelsSettings()
                            } else {
                                retryProvider("Anthropic") {
                                    await chatManager.providers.anthropic.connect()
                                }
                            }
                        },
                        accent: accent
                    )

                    // Google Gemini
                    ProviderCard(
                        icon: "diamond",
                        name: "Google Gemini",
                        subtitle: "Gemini 2.5 Pro, Flash",
                        isConnected: chatManager.providers.gemini.isConnected,
                        modelCount: chatManager.providers.gemini.models.count,
                        statusText: chatManager.providers.gemini.isConnected
                            ? "\(chatManager.providers.gemini.models.count) models available"
                            : chatManager.providers.gemini.apiKey.isEmpty
                                ? "Add your API key in Settings → Models"
                                : chatManager.providers.gemini.connectionError ?? "Could not connect",
                        isLoading: retryingProvider == "Gemini",
                        actionLabel: chatManager.providers.gemini.isConnected
                            ? nil
                            : chatManager.providers.gemini.apiKey.isEmpty ? "Set Up" : "Retry",
                        action: {
                            if chatManager.providers.gemini.apiKey.isEmpty {
                                openModelsSettings()
                            } else {
                                retryProvider("Gemini") {
                                    await chatManager.providers.gemini.connect()
                                }
                            }
                        },
                        accent: accent
                    )

                    // Keep LM Studio visible even before an endpoint is configured.
                    ForEach([true, false], id: \.self) { isLMStudio in
                        let endpoints = chatManager.providers.custom.endpoints.filter { $0.isLMStudio == isLMStudio }
                        let connected = endpoints.contains { $0.isConnected }
                        let modelCount = endpoints.filter { $0.isConnected }.reduce(0) { $0 + $1.models.count }
                        let name = isLMStudio ? "LM Studio" : "Other Servers"
                        ProviderCard(
                            icon: isLMStudio ? "desktopcomputer" : "server.rack",
                            name: name,
                            subtitle: isLMStudio ? "Local models through LM Studio" : "OpenAI compatible servers",
                            isConnected: connected,
                            modelCount: modelCount,
                            statusText: connected
                                ? "Connected · \(modelCount) models available"
                                : endpoints.isEmpty
                                    ? "Not connected — set up in Settings → Models"
                                    : endpoints.first?.connectionError ?? "Not connected — start your server, then Retry",
                            isLoading: retryingProvider == name,
                            actionLabel: endpoints.isEmpty ? "Set Up" : (connected ? nil : "Retry"),
                            action: {
                                if endpoints.isEmpty {
                                    openModelsSettings()
                                } else {
                                    retryProvider(name) {
                                        for endpoint in endpoints { await endpoint.connect() }
                                    }
                                }
                            },
                            accent: accent
                        )
                    }
                }
                .frame(maxWidth: .infinity)

                // Summary bar
                HStack(spacing: 16) {
                    let connected = chatManager.providers.connectedGroupCount
                    let total = chatManager.providers.connectionGroupCount
                    let modelCount = chatManager.providers.allModels.count

                    Label("\(connected)/\(total) providers connected", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Text("·")
                        .foregroundStyle(.secondary)

                    Label("\(modelCount) models available", systemImage: "cpu")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)

                // Actions
                HStack(spacing: 12) {
                    Button {
                        openModelsSettings()
                    } label: {
                        Label("Models & Providers", systemImage: "cpu")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        Task { await chatManager.providers.connectAll() }
                    } label: {
                        Label("Refresh All", systemImage: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                // Keyboard hints
                HStack(spacing: 16) {
                    KeyboardHint(key: "⌘N", label: "New chat")
                    KeyboardHint(key: "⌘M", label: "Models")
                    KeyboardHint(key: "⇧⌘B", label: "Brainstorm")
                    KeyboardHint(key: "⇧⌘K", label: "Compare")
                    KeyboardHint(key: "⇧⌘P", label: "Prompts")
                    KeyboardHint(key: "⌘,", label: "Settings")
                }
                .padding(.top, 8)

                Spacer(minLength: 20)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Provider Card

struct ProviderCard: View {
    let icon: String
    let name: String
    let subtitle: String
    let isConnected: Bool
    let modelCount: Int
    let statusText: String
    var isLoading: Bool = false
    let actionLabel: String?
    let action: () -> Void
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            // Provider icon
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(isConnected ? accent : Color.gray.opacity(0.5))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isConnected ? accent.opacity(0.1) : Color.gray.opacity(0.06))
                )

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 13, weight: .semibold))

                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                    } else {
                        Circle()
                            .fill(isConnected ? Color.green : Color.gray.opacity(0.4))
                            .frame(width: 7, height: 7)
                    }

                    if isConnected && !isLoading {
                        Text("CONNECTED")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.1), in: Capsule())
                    }
                }

                Text(isLoading ? "Connecting…" : statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Action button (only when not connected and not loading)
            if let label = actionLabel, !isLoading {
                Button(label, action: action)
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isConnected ? accent.opacity(0.03) : Color.gray.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isConnected ? accent.opacity(0.15) : Color.gray.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Keyboard Hint Chip

struct KeyboardHint: View {
    let key: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Sidebar Resize Handle

/// A thin draggable divider that lets the user resize the sidebar.
struct SidebarResizeHandle: View {
    @Binding var sidebarWidth: CGFloat
    var isExpanded: Bool
    @State private var isDragging = false
    @State private var dragStartWidth: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.accentColor.opacity(0.3) : Color.clear)
            .frame(width: 5)
            .contentShape(Rectangle())
            .overlay(
                Rectangle()
                    .fill(.separator)
                    .frame(width: 1)
            )
            .onHover { hovering in
                if isExpanded {
                    if hovering {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if isExpanded {
                            if !isDragging {
                                isDragging = true
                                dragStartWidth = sidebarWidth
                            }
                            let newWidth = dragStartWidth + value.translation.width
                            sidebarWidth = min(max(newWidth, 200), 400)
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
    }
}
