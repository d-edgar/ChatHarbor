import SwiftUI

// MARK: - Settings Window

struct SettingsView: View {
    @EnvironmentObject var chatManager: ChatManager

    var body: some View {
        TabView(selection: $chatManager.settingsTab) {
            GeneralSettingsView()
                .environmentObject(chatManager)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag("general")

            ModelsProvidersSettingsView()
                .environmentObject(chatManager)
                .tabItem {
                    Label("Models", systemImage: "cpu")
                }
                .tag("models")

            AppearanceSettingsView()
                .environmentObject(chatManager)
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
                .tag("appearance")

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag("about")
        }
        .frame(width: 620, height: 600)
    }
}

// MARK: - Models & Providers Settings
//
// Unified tab that combines the Model Manager and Provider setup.
// This is the one-stop shop for connecting providers, managing API keys,
// browsing models, and pulling local models.

struct ModelsProvidersSettingsView: View {
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var pullModelName: String = ""
    @State private var showingDeleteConfirm: String?
    @State private var errorMessage: String?

    private var accent: Color {
        chatManager.currentTheme.accentColor(for: colorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MARK: - Ollama (Local)
                ProviderSetupSection(
                    icon: "desktopcomputer",
                    name: "Ollama",
                    subtitle: "Free, local, private — runs on your Mac",
                    isConnected: chatManager.ollama.isConnected,
                    modelCount: chatManager.ollama.availableModels.count,
                    accent: accent
                ) {
                    // Server URL
                    HStack {
                        Text("Server")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .trailing)
                        TextField("http://localhost:11434", text: $chatManager.ollamaBaseURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                        Button("Test") {
                            Task {
                                if let url = URL(string: chatManager.ollamaBaseURL) {
                                    chatManager.ollama.baseURL = url
                                }
                                await chatManager.ollama.checkConnection()
                            }
                        }
                        .controlSize(.small)
                    }

                    // Pull model
                    if chatManager.ollama.isConnected {
                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            Text("PULL A MODEL")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.tertiary)

                            HStack(spacing: 8) {
                                TextField("e.g. llama3.2, mistral, codellama", text: $pullModelName)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12))
                                    .onSubmit { pullModel() }

                                Button("Pull") { pullModel() }
                                    .buttonStyle(.borderedProminent)
                                    .tint(accent)
                                    .controlSize(.small)
                                    .disabled(pullModelName.trimmingCharacters(in: .whitespaces).isEmpty)
                                    .disabled(chatManager.ollama.pullProgress != nil)
                            }

                            // Pull progress
                            if let progress = chatManager.ollama.pullProgress {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                    Text("Pulling \(progress.modelName)")
                                        .font(.system(size: 11, weight: .medium))
                                    Spacer()
                                    if progress.total > 0 {
                                        Text("\(Int(progress.fraction * 100))%")
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundStyle(accent)
                                    }
                                }
                                ProgressView(value: progress.fraction)
                                    .tint(accent)
                            }

                            // Quick pull chips
                            FlowLayout(spacing: 5) {
                                ForEach([
                                    ("llama3.2", "2B"), ("mistral", "7B"), ("codellama", "7B"),
                                    ("gemma2", "9B"), ("phi3", "3.8B"), ("qwen2.5", "7B")
                                ], id: \.0) { name, size in
                                    Button {
                                        pullModelName = name
                                    } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: "arrow.down.circle")
                                                .font(.system(size: 9))
                                            Text(name)
                                                .font(.system(size: 10, weight: .medium))
                                            Text(size)
                                                .font(.system(size: 8))
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 5)
                                                .fill(accent.opacity(0.06))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 5)
                                                .stroke(accent.opacity(0.15), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(accent)
                                }
                            }
                        }
                    }

                    // Installed models
                    if !chatManager.ollama.availableModels.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("INSTALLED")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Text("\(chatManager.ollama.availableModels.count) models")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }

                            ForEach(chatManager.ollama.availableModels) { model in
                                SettingsModelRow(
                                    name: model.displayName,
                                    detail: [model.parameterSize, model.quantizationLevel, model.formattedSize].filter { !$0.isEmpty }.joined(separator: " · "),
                                    qualifiedId: "ollama:\(model.name)",
                                    isLocal: true,
                                    isSelected: "ollama:\(model.name)" == chatManager.selectedModelId,
                                    onSelect: { chatManager.selectModel("ollama:\(model.name)") },
                                    onDelete: { showingDeleteConfirm = model.name },
                                    accent: accent
                                )
                            }
                        }
                    }
                }

                // MARK: - OpenAI
                ProviderSetupSection(
                    icon: "brain",
                    name: "OpenAI",
                    subtitle: "GPT-4o, o1, o3 — platform.openai.com/api-keys",
                    isConnected: chatManager.providers.openAI.isConnected,
                    modelCount: chatManager.providers.openAI.models.count,
                    accent: accent
                ) {
                    // API Key
                    HStack {
                        Text("API Key")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .trailing)
                        SecureField("sk-...", text: Binding(
                            get: { chatManager.providers.openAI.apiKey },
                            set: { chatManager.providers.openAI.apiKey = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        Button("Connect") {
                            Task { await chatManager.providers.openAI.connect() }
                        }
                        .controlSize(.small)
                        .disabled(chatManager.providers.openAI.apiKey.isEmpty)
                    }

                    // Models list
                    if !chatManager.providers.openAI.models.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("AVAILABLE")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Text("\(chatManager.providers.openAI.models.count) models")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }

                            ForEach(chatManager.providers.openAI.models) { model in
                                SettingsModelRow(
                                    name: model.displayName,
                                    detail: model.contextWindow.map { "\($0 / 1000)K context" } ?? "",
                                    qualifiedId: model.id,
                                    isLocal: false,
                                    isSelected: model.id == chatManager.selectedModelId,
                                    onSelect: { chatManager.selectModel(model.id) },
                                    onDelete: nil,
                                    accent: accent
                                )
                            }
                        }
                    }
                }

                // MARK: - Anthropic
                ProviderSetupSection(
                    icon: "sparkle",
                    name: "Anthropic",
                    subtitle: "Claude Sonnet, Opus, Haiku — console.anthropic.com",
                    isConnected: chatManager.providers.anthropic.isConnected,
                    modelCount: chatManager.providers.anthropic.models.count,
                    accent: accent
                ) {
                    // API Key
                    HStack {
                        Text("API Key")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .trailing)
                        SecureField("sk-ant-...", text: Binding(
                            get: { chatManager.providers.anthropic.apiKey },
                            set: { chatManager.providers.anthropic.apiKey = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        Button("Connect") {
                            Task { await chatManager.providers.anthropic.connect() }
                        }
                        .controlSize(.small)
                        .disabled(chatManager.providers.anthropic.apiKey.isEmpty)
                    }

                    // Models list
                    if !chatManager.providers.anthropic.models.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("AVAILABLE")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Text("\(chatManager.providers.anthropic.models.count) models")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }

                            ForEach(chatManager.providers.anthropic.models) { model in
                                SettingsModelRow(
                                    name: model.displayName,
                                    detail: model.contextWindow.map { "\($0 / 1000)K context" } ?? "",
                                    qualifiedId: model.id,
                                    isLocal: false,
                                    isSelected: model.id == chatManager.selectedModelId,
                                    onSelect: { chatManager.selectModel(model.id) },
                                    onDelete: nil,
                                    accent: accent
                                )
                            }
                        }
                    }
                }

                // Summary
                HStack(spacing: 16) {
                    let connected = chatManager.providers.connectedProviders.count
                    let total = chatManager.providers.allProviders.count
                    let modelCount = chatManager.providers.allModels.count

                    Label("\(connected)/\(total) providers", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Label("\(modelCount) models", systemImage: "cpu")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Reconnect All") {
                        Task { await chatManager.providers.connectAll() }
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 4)
            }
            .padding(20)
        }
        .alert("Delete Model", isPresented: Binding(
            get: { showingDeleteConfirm != nil },
            set: { if !$0 { showingDeleteConfirm = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let name = showingDeleteConfirm {
                    Task {
                        do {
                            try await chatManager.ollama.deleteModel(name: name)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete \(showingDeleteConfirm ?? "")? You'll need to pull it again to use it.")
        }
    }

    private func pullModel() {
        let name = pullModelName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        pullModelName = ""
        Task {
            do {
                try await chatManager.ollama.pullModel(name: name)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Provider Setup Section

struct ProviderSetupSection<Content: View>: View {
    let icon: String
    let name: String
    let subtitle: String
    let isConnected: Bool
    let modelCount: Int
    let accent: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(isConnected ? accent : Color.gray.opacity(0.5))
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(isConnected ? accent.opacity(0.1) : Color.gray.opacity(0.05))
                    )

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(name)
                            .font(.system(size: 14, weight: .semibold))

                        Circle()
                            .fill(isConnected ? Color.green : Color.gray.opacity(0.4))
                            .frame(width: 7, height: 7)

                        if isConnected {
                            Text("\(modelCount) models")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }

            // Content
            content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isConnected ? accent.opacity(0.02) : Color.gray.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isConnected ? accent.opacity(0.12) : Color.gray.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Settings Model Row (compact)

struct SettingsModelRow: View {
    let name: String
    let detail: String
    let qualifiedId: String
    let isLocal: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: (() -> Void)?
    let accent: Color

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? accent : Color.gray.opacity(0.3))

            Image(systemName: isLocal ? "desktopcomputer" : "cloud")
                .font(.system(size: 9))
                .foregroundStyle(isLocal ? .orange : .blue)

            Text(name)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))

            if isSelected {
                Text("ACTIVE")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(accent.opacity(0.12), in: Capsule())
            }

            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if let onDelete = onDelete, isHovering {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? accent.opacity(0.06) : isHovering ? Color.gray.opacity(0.04) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { h in withAnimation(.easeInOut(duration: 0.1)) { isHovering = h } }
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color {
        chatManager.currentTheme.accentColor(for: colorScheme)
    }

    /// SwiftData store location
    private var dataStorePath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return appSupport?.appendingPathComponent("ChatHarbor").path ?? "~/Library/Application Support/ChatHarbor"
    }

    /// Default Ollama models location
    private var ollamaModelsPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.ollama/models"
    }

    var body: some View {
        Form {
            // Default Model
            Section("Default Model") {
                if chatManager.providers.allModels.isEmpty {
                    Text("No models available — set up a provider in the Models tab")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Model", selection: $chatManager.selectedModelId) {
                        let ollamaModels = chatManager.providers.ollama.models
                        if !ollamaModels.isEmpty {
                            Section("Ollama (Local)") {
                                ForEach(ollamaModels) { model in
                                    Label(model.displayName, systemImage: "desktopcomputer")
                                        .tag(model.id)
                                }
                            }
                        }
                        let openAIModels = chatManager.providers.openAI.models
                        if !openAIModels.isEmpty {
                            Section("OpenAI") {
                                ForEach(openAIModels) { model in
                                    Label(model.displayName, systemImage: "cloud")
                                        .tag(model.id)
                                }
                            }
                        }
                        let anthropicModels = chatManager.providers.anthropic.models
                        if !anthropicModels.isEmpty {
                            Section("Anthropic") {
                                ForEach(anthropicModels) { model in
                                    Label(model.displayName, systemImage: "cloud")
                                        .tag(model.id)
                                }
                            }
                        }
                    }
                }
            }

            // Chat Behavior
            Section("Chat") {
                Toggle("Stream responses in real-time", isOn: $chatManager.streamResponses)
                Toggle("Send message on Enter", isOn: $chatManager.sendOnEnter)
                HStack {
                    Text("When off, use Shift+Enter to send.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                Toggle("Auto-title new conversations", isOn: $chatManager.autoTitleConversations)
            }

            // Forking
            Section("Forking") {
                HStack {
                    Text("Fork title prefix")
                        .font(.system(size: 13))
                    Spacer()
                    TextField("Prefix", text: $chatManager.forkPrefix)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                        .font(.system(size: 12))
                }
                Text("When you fork a conversation, the new chat is titled \"\(chatManager.forkPrefix) Original Title\".")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Data & Storage
            Section("Data & Storage") {
                VStack(alignment: .leading, spacing: 8) {
                    SettingsPathRow(
                        label: "Conversations",
                        path: dataStorePath,
                        description: "SwiftData store for all your chats and messages"
                    )
                    Divider()
                    SettingsPathRow(
                        label: "Ollama Models",
                        path: ollamaModelsPath,
                        description: "Where Ollama stores downloaded model files"
                    )
                }
                Text("All data stays on your Mac. API keys stored in UserDefaults (Keychain migration planned).")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Settings Path Row

struct SettingsPathRow: View {
    let label: String
    let path: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text(path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(path, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("Copy path")
                Button {
                    let expanded = NSString(string: path).expandingTildeInPath
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: expanded)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("Show in Finder")
            }
            Text(description)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Form {
            Section("Mode") {
                Picker("Appearance", selection: $chatManager.appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Theme") {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ], spacing: 10) {
                    ForEach(ThemeCatalog.standardThemes) { theme in
                        ThemeCard(
                            theme: theme,
                            isSelected: chatManager.selectedThemeId == theme.id
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                chatManager.selectedThemeId = theme.id
                            }
                        }
                    }
                }
            }

            Section("Seasonal") {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ], spacing: 10) {
                    ForEach(ThemeCatalog.seasonalThemes) { theme in
                        ThemeCard(
                            theme: theme,
                            isSelected: chatManager.selectedThemeId == theme.id
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                chatManager.selectedThemeId = theme.id
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Provider Status Badge

struct ProviderStatusBadge: View {
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isConnected ? .green : Color.gray.opacity(0.4))
                .frame(width: 7, height: 7)
            Text(isConnected ? "Connected" : "Not connected")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - About Settings

struct AboutSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image("ChatHarborLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: .black.opacity(0.1), radius: 6, y: 3)

                Text("ChatHarbor")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Version 2.0.0")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("One native macOS app for all your AI.\nChat with Ollama, OpenAI, and Anthropic models side by side.\nCompare responses, fork conversations across providers,\nand keep everything in one place.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)

                Divider()
                    .frame(width: 200)

                VStack(spacing: 8) {
                    Text("POWERED BY")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)

                    HStack(spacing: 20) {
                        AboutProviderLink(
                            name: "Ollama",
                            detail: "Local inference",
                            url: "https://ollama.com",
                            icon: "desktopcomputer"
                        )
                        AboutProviderLink(
                            name: "OpenAI",
                            detail: "GPT API",
                            url: "https://platform.openai.com/docs",
                            icon: "brain"
                        )
                        AboutProviderLink(
                            name: "Anthropic",
                            detail: "Claude API",
                            url: "https://docs.anthropic.com",
                            icon: "sparkle"
                        )
                    }
                }

                Divider()
                    .frame(width: 200)

                VStack(spacing: 10) {
                    Link(destination: URL(string: "https://github.com/d-edgar/ChatHarbor")!) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .font(.system(size: 11))
                            Text("Source Code on GitHub")
                                .font(.system(size: 12))
                        }
                    }

                    Link(destination: URL(string: "https://buymeacoffee.com/dedgar")!) {
                        HStack(spacing: 6) {
                            Image(systemName: "cup.and.saucer")
                                .font(.system(size: 11))
                            Text("Buy Me a Coffee")
                                .font(.system(size: 12))
                        }
                    }
                }

                Text("Built with SwiftUI · SwiftData · MIT License")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Text("Copyright © 2026 David Edgar")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }
}

// MARK: - About Provider Link

struct AboutProviderLink: View {
    let name: String
    let detail: String
    let url: String
    let icon: String

    var body: some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 80)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Theme Card

struct ThemeCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Circle()
                    .fill(theme.accentColor(for: colorScheme))
                    .frame(width: 24, height: 24)
                    .overlay(
                        isSelected
                            ? Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                            : nil
                    )

                Text(theme.name)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? theme.accentColor(for: colorScheme).opacity(0.1) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? theme.accentColor(for: colorScheme) : Color.gray.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
