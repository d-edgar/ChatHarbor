import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openSettings) private var openSettingsFromContent
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @State private var sidebarExpanded: Bool = true

    /// The currently selected conversation, resolved from the ID
    private var selectedConversation: Conversation? {
        guard let id = chatManager.selectedConversationId else { return nil }
        return conversations.first(where: { $0.id == id })
    }

    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Sidebar
            SidebarView(isExpanded: $sidebarExpanded)
                .environmentObject(chatManager)

            Divider()

            // MARK: - Detail
            Group {
                if chatManager.isLaunching {
                    SplashView()
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

// MARK: - Splash Screen

struct SplashView: View {
    @State private var opacity: Double = 0
    @State private var scale: Double = 0.8

    var body: some View {
        VStack(spacing: 20) {
            Image("ChatHarborLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

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

    private var hasAnyProvider: Bool {
        chatManager.providers.connectedProviders.count > 0
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
                Image("ChatHarborLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: .black.opacity(0.1), radius: 6, y: 3)

                VStack(spacing: 6) {
                    Text("Welcome to ChatHarbor")
                        .font(.largeTitle)
                        .fontWeight(.semibold)

                    Text("One native macOS app for all your AI.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

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
                }
                .frame(maxWidth: 420)

                // Summary bar
                HStack(spacing: 16) {
                    let connected = chatManager.providers.connectedProviders.count
                    let total = chatManager.providers.allProviders.count
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
                    if hasAnyProvider {
                        Button {
                            let conversation = chatManager.createConversation(in: modelContext)
                            chatManager.selectedConversationId = conversation.id
                        } label: {
                            Label("New Chat", systemImage: "plus.bubble")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .controlSize(.large)
                    }

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
                    KeyboardHint(key: "⇧⌘K", label: "Compare")
                    KeyboardHint(key: "⇧⌘P", label: "Prompts")
                    KeyboardHint(key: "⌘,", label: "Settings")
                }
                .padding(.top, 8)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 32)
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
