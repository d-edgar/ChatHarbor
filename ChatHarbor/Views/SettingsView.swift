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

            PromptsParametersSettingsView()
                .environmentObject(chatManager)
                .tabItem {
                    Label("Prompts", systemImage: "slider.horizontal.3")
                }
                .tag("prompts")

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
        .onDisappear {
            // Reset to General tab so next ⌘, opens cleanly
            // instead of staying stuck on Models (with Ollama field focused)
            chatManager.settingsTab = "general"
        }
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

    // Connection state for each cloud provider
    @State private var ollamaConnecting = false
    @State private var openAIConnecting = false
    @State private var openAIError: String?
    @State private var openAISuccess = false
    @State private var anthropicConnecting = false
    @State private var anthropicError: String?
    @State private var anthropicSuccess = false

    private var accent: Color {
        chatManager.currentTheme.accentColor(for: colorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MARK: - Apple Intelligence (Local, On-Device)
                ProviderSetupSection(
                    icon: chatManager.providers.apple.iconName,
                    name: "Apple Intelligence",
                    subtitle: "Free, on-device, private — built into macOS",
                    isConnected: chatManager.providers.apple.isConnected,
                    modelCount: chatManager.providers.apple.models.count,
                    providerId: "apple",
                    accent: accent
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        // On/off toggle
                        HStack {
                            Toggle(isOn: Binding(
                                get: { chatManager.providers.apple.isEnabled },
                                set: { chatManager.providers.apple.isEnabled = $0 }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Enable Apple Intelligence")
                                        .font(.system(size: 12, weight: .medium))
                                    Text("Uses Apple's on-device foundation model · No API key needed")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.switch)
                            .tint(accent)
                        }

                        // Status / availability detail
                        if chatManager.providers.apple.isEnabled {
                            HStack(spacing: 4) {
                                if chatManager.providers.apple.isConnected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.green)
                                    Text(chatManager.providers.apple.availabilityDetail)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.green)
                                } else {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.orange)
                                    Text(chatManager.providers.apple.availabilityDetail)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.orange)
                                        .lineLimit(3)
                                }
                            }
                        }

                        // Info badges
                        HStack(spacing: 8) {
                            InfoBadge(icon: "lock.shield", text: "On-device", color: .green)
                            InfoBadge(icon: "wifi.slash", text: "Works offline", color: .blue)
                            InfoBadge(icon: "dollarsign.circle", text: "Free", color: accent)
                            InfoBadge(icon: "memorychip", text: "4K context", color: .secondary)
                        }
                    }
                }

                // MARK: - Ollama (Local)
                ProviderSetupSection(
                    icon: "desktopcomputer",
                    name: "Ollama",
                    subtitle: "Free, local, private — runs on your Mac",
                    isConnected: chatManager.ollama.isConnected,
                    modelCount: chatManager.ollama.availableModels.count,
                    providerId: "ollama",
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

                        if ollamaConnecting {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 40)
                        } else {
                            Button("Test") {
                                ollamaConnecting = true
                                Task {
                                    if let url = URL(string: chatManager.ollamaBaseURL) {
                                        chatManager.ollama.baseURL = url
                                    }
                                    await chatManager.ollama.checkConnection()
                                    ollamaConnecting = false
                                }
                            }
                            .controlSize(.small)
                        }
                    }

                    // Pull model
                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("PULL A MODEL")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if !chatManager.ollama.isConnected {
                                Text("Connect to Ollama first")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.orange)
                            }
                        }

                        HStack(spacing: 8) {
                            TextField("e.g. llama3.2, mistral, codellama", text: $pullModelName)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                                .onSubmit { if chatManager.ollama.isConnected { pullModel() } }
                                .disabled(!chatManager.ollama.isConnected)

                            Button("Pull") { pullModel() }
                                .buttonStyle(.borderedProminent)
                                .tint(accent)
                                .controlSize(.small)
                                .disabled(!chatManager.ollama.isConnected || pullModelName.trimmingCharacters(in: .whitespaces).isEmpty)
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
                                            .fill(chatManager.ollama.isConnected ? accent.opacity(0.06) : Color.gray.opacity(0.04))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .stroke(chatManager.ollama.isConnected ? accent.opacity(0.15) : Color.gray.opacity(0.1), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(chatManager.ollama.isConnected ? accent : Color.gray.opacity(0.5))
                                .disabled(!chatManager.ollama.isConnected)
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
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(chatManager.ollama.availableModels.count) models")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
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
                    icon: "hexagon",
                    name: "OpenAI",
                    subtitle: "GPT-4o, o1, o3 — platform.openai.com/api-keys",
                    isConnected: chatManager.providers.openAI.isConnected,
                    modelCount: chatManager.providers.openAI.models.count,
                    providerId: "openai",
                    accent: accent
                ) {
                    // API Key
                    HStack(spacing: 6) {
                        Text("API Key")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .trailing)
                        SecureField("sk-...", text: Binding(
                            get: { chatManager.providers.openAI.apiKey },
                            set: { chatManager.providers.openAI.apiKey = $0; openAIError = nil; openAISuccess = false }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))

                        if openAIConnecting {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 60)
                        } else {
                            Button("Connect") {
                                openAIConnecting = true
                                openAIError = nil
                                openAISuccess = false
                                Task {
                                    await chatManager.providers.openAI.connect()
                                    openAIConnecting = false
                                    if chatManager.providers.openAI.isConnected {
                                        openAISuccess = true
                                    } else {
                                        openAIError = "Could not verify key"
                                    }
                                }
                            }
                            .controlSize(.small)
                            .disabled(chatManager.providers.openAI.apiKey.isEmpty)
                        }

                        // Clear key button
                        if !chatManager.providers.openAI.apiKey.isEmpty {
                            Button {
                                chatManager.providers.openAI.apiKey = ""
                                openAISuccess = false
                                openAIError = nil
                                Task { await chatManager.providers.openAI.connect() }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Clear API key")
                        }
                    }

                    // Status feedback
                    if chatManager.providers.openAI.isConnected {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.green)
                            Text("Connected — \(chatManager.providers.openAI.models.count) models available")
                                .font(.system(size: 10))
                                .foregroundStyle(.green)
                        }
                    } else if let error = chatManager.providers.openAI.connectionError {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                                .lineLimit(3)
                        }
                    }

                    // Models list
                    if !chatManager.providers.openAI.models.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("AVAILABLE")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(chatManager.providers.openAI.models.count) models")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
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
                    icon: "sun.max.fill",
                    name: "Anthropic",
                    subtitle: "Claude Sonnet, Opus, Haiku — console.anthropic.com",
                    isConnected: chatManager.providers.anthropic.isConnected,
                    modelCount: chatManager.providers.anthropic.models.count,
                    providerId: "anthropic",
                    accent: accent
                ) {
                    // API Key
                    HStack(spacing: 6) {
                        Text("API Key")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .trailing)
                        SecureField("sk-ant-...", text: Binding(
                            get: { chatManager.providers.anthropic.apiKey },
                            set: { chatManager.providers.anthropic.apiKey = $0; anthropicError = nil; anthropicSuccess = false }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))

                        if anthropicConnecting {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 60)
                        } else {
                            Button("Connect") {
                                anthropicConnecting = true
                                anthropicError = nil
                                anthropicSuccess = false
                                Task {
                                    await chatManager.providers.anthropic.connect()
                                    anthropicConnecting = false
                                    if chatManager.providers.anthropic.isConnected {
                                        anthropicSuccess = true
                                    } else {
                                        anthropicError = "Could not verify key — check your API key and billing"
                                    }
                                }
                            }
                            .controlSize(.small)
                            .disabled(chatManager.providers.anthropic.apiKey.isEmpty)
                        }

                        // Clear key button
                        if !chatManager.providers.anthropic.apiKey.isEmpty {
                            Button {
                                chatManager.providers.anthropic.apiKey = ""
                                anthropicSuccess = false
                                anthropicError = nil
                                Task { await chatManager.providers.anthropic.connect() }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Clear API key")
                        }
                    }

                    // Status feedback
                    if chatManager.providers.anthropic.isConnected {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.green)
                            Text("Connected — \(chatManager.providers.anthropic.models.count) models available")
                                .font(.system(size: 10))
                                .foregroundStyle(.green)
                        }
                    } else if let error = chatManager.providers.anthropic.connectionError {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                                .lineLimit(3)
                        }
                    }

                    // Models list
                    if !chatManager.providers.anthropic.models.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("AVAILABLE")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(chatManager.providers.anthropic.models.count) models")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
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
    var providerId: String? = nil  // For custom logo lookup
    let accent: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 10) {
                Group {
                    if let pid = providerId, ProviderIcon.hasCustomIcon(for: pid) {
                        ProviderIconView(providerId: pid, sfSymbolFallback: icon)
                            .frame(width: 18, height: 18)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 18))
                    }
                }
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
                        .foregroundStyle(.secondary)
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

// MARK: - Info Badge (small tag for provider features)

struct InfoBadge: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(text)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(color.opacity(0.15), lineWidth: 0.5)
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
                    .foregroundStyle(.secondary)
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

// MARK: - Prompts & Parameters Settings
//
// Full transparency: see and control every system prompt and parameter
// that gets sent to each provider's API. No hidden magic.

struct PromptsParametersSettingsView: View {
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color {
        chatManager.currentTheme.accentColor(for: colorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Intro
                HStack(spacing: 8) {
                    Image(systemName: "eye")
                        .font(.system(size: 14))
                        .foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Full Transparency")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Every setting here maps directly to what's sent to the API. No hidden prompts, no secret parameters.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.12), lineWidth: 1))

                // Per-provider sections
                let providerData: [(id: String, name: String, icon: String, connected: Bool)] = chatManager.providers.allProviders.map {
                    (id: $0.providerId, name: $0.displayName, icon: $0.iconName, connected: $0.isConnected)
                }
                ForEach(providerData, id: \.id) { prov in
                    ProviderPromptsSection(
                        providerId: prov.id,
                        providerName: prov.name,
                        icon: prov.icon,
                        isConnected: prov.connected,
                        accent: accent
                    )
                    .environmentObject(chatManager)
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Per-Provider Prompts & Parameters Section

struct ProviderPromptsSection: View {
    let providerId: String
    let providerName: String
    let icon: String
    let isConnected: Bool
    let accent: Color
    @EnvironmentObject var chatManager: ChatManager

    @State private var systemPrompt: String = ""
    @State private var temperature: Double? = nil
    @State private var maxTokens: Int? = nil
    @State private var topP: Double? = nil
    @State private var frequencyPenalty: Double? = nil
    @State private var presencePenalty: Double? = nil
    @State private var isExpanded: Bool = true

    private var supportedParams: [String] {
        ProviderManager.supportedParameters(for: providerId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (clickable to expand/collapse)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(isConnected ? accent : .gray)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isConnected ? accent.opacity(0.1) : Color.gray.opacity(0.05))
                        )

                    Text(providerName)
                        .font(.system(size: 13, weight: .semibold))

                    if !isConnected {
                        Text("Not connected")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(12)

            if isExpanded {
                Divider().padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 14) {
                    // System Prompt
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Default System Prompt", systemImage: "text.bubble")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if !systemPrompt.isEmpty {
                                Text("\(systemPrompt.count) chars")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        TextEditor(text: $systemPrompt)
                            .font(.system(size: 11))
                            .frame(minHeight: 60, maxHeight: 120)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background(Color.gray.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                            .onChange(of: systemPrompt) { _, newValue in
                                chatManager.providers.setDefaultSystemPrompt(newValue, for: providerId)
                            }

                        Text("Sent as the system message for every new conversation using this provider, unless overridden per-conversation.")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }

                    // Parameters
                    if !supportedParams.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            Label("API Parameters", systemImage: "slider.horizontal.3")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)

                            Text("These values are sent directly in the API request body. Leave blank for provider defaults.")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }

                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ], spacing: 10) {
                            if supportedParams.contains("temperature") {
                                ParameterSliderField(
                                    label: "temperature",
                                    apiKey: "temperature",
                                    value: $temperature,
                                    range: 0...2,
                                    step: 0.1,
                                    description: "Higher = more creative, lower = more focused",
                                    providerId: providerId
                                )
                                .environmentObject(chatManager)
                            }

                            if supportedParams.contains("maxTokens") {
                                ParameterIntField(
                                    label: "max_tokens",
                                    apiKey: "maxTokens",
                                    value: $maxTokens,
                                    placeholder: providerId == "anthropic" ? "4096" : "default",
                                    description: "Maximum response length in tokens",
                                    providerId: providerId
                                )
                                .environmentObject(chatManager)
                            }

                            if supportedParams.contains("topP") {
                                ParameterSliderField(
                                    label: "top_p",
                                    apiKey: "topP",
                                    value: $topP,
                                    range: 0...1,
                                    step: 0.05,
                                    description: "Nucleus sampling threshold",
                                    providerId: providerId
                                )
                                .environmentObject(chatManager)
                            }

                            if supportedParams.contains("frequencyPenalty") {
                                ParameterSliderField(
                                    label: "frequency_penalty",
                                    apiKey: "frequencyPenalty",
                                    value: $frequencyPenalty,
                                    range: -2...2,
                                    step: 0.1,
                                    description: "Reduce repetition of frequent tokens",
                                    providerId: providerId
                                )
                                .environmentObject(chatManager)
                            }

                            if supportedParams.contains("presencePenalty") {
                                ParameterSliderField(
                                    label: "presence_penalty",
                                    apiKey: "presencePenalty",
                                    value: $presencePenalty,
                                    range: -2...2,
                                    step: 0.1,
                                    description: "Encourage talking about new topics",
                                    providerId: providerId
                                )
                                .environmentObject(chatManager)
                            }
                        }
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text("This provider's parameters are fixed (on-device model).")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isConnected ? accent.opacity(0.02) : Color.gray.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isConnected ? accent.opacity(0.12) : Color.gray.opacity(0.08), lineWidth: 1)
        )
        .onAppear { loadDefaults() }
    }

    private func loadDefaults() {
        systemPrompt = chatManager.providers.defaultSystemPrompt(for: providerId)
        let params = chatManager.providers.defaultParameters(for: providerId)
        temperature = params.temperature
        maxTokens = params.maxTokens
        topP = params.topP
        frequencyPenalty = params.frequencyPenalty
        presencePenalty = params.presencePenalty
    }
}

// MARK: - Parameter Slider Field

struct ParameterSliderField: View {
    let label: String          // API key name shown to user
    let apiKey: String         // Internal storage key
    @Binding var value: Double?
    let range: ClosedRange<Double>
    let step: Double
    let description: String
    let providerId: String
    @EnvironmentObject var chatManager: ChatManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                if let val = value {
                    Text(String(format: step < 0.1 ? "%.2f" : "%.1f", val))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.primary)
                    Button {
                        value = nil
                        chatManager.providers.setDefaultParameter(apiKey, value: nil, for: providerId)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Reset to provider default")
                } else {
                    Text("default")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Slider(
                value: Binding(
                    get: { value ?? (range.lowerBound + range.upperBound) / 2 },
                    set: { newVal in
                        value = newVal
                        chatManager.providers.setDefaultParameter(apiKey, value: newVal, for: providerId)
                    }
                ),
                in: range,
                step: step
            )
            .controlSize(.small)

            Text(description)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.gray.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Parameter Int Field

struct ParameterIntField: View {
    let label: String
    let apiKey: String
    @Binding var value: Int?
    let placeholder: String
    let description: String
    let providerId: String
    @EnvironmentObject var chatManager: ChatManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                if value != nil {
                    Button {
                        value = nil
                        chatManager.providers.setDefaultParameter(apiKey, value: nil, for: providerId)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Reset to provider default")
                }
            }

            TextField(placeholder, value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .onChange(of: value) { _, newVal in
                    chatManager.providers.setDefaultParameter(apiKey, value: newVal, for: providerId)
                }

            Text(description)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.gray.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
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
                        let appleModels = chatManager.providers.apple.models
                        if !appleModels.isEmpty {
                            Section("Apple Intelligence (On-Device)") {
                                ForEach(appleModels) { model in
                                    Label(model.displayName, systemImage: chatManager.providers.apple.iconName)
                                        .tag(model.id)
                                }
                            }
                        }
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
                        .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
                .help("Copy path")
                Button {
                    let expanded = NSString(string: path).expandingTildeInPath
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: expanded)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Show in Finder")
            }
            Text(description)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
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

                Text("One native macOS app for all your AI.\nChat with Apple Intelligence, Ollama, OpenAI, and Anthropic\nside by side. Compare responses, fork conversations\nacross providers, and keep everything in one place.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)

                Divider()
                    .frame(width: 200)

                VStack(spacing: 8) {
                    Text("POWERED BY")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 16) {
                        AboutProviderLink(
                            name: "Apple",
                            detail: "On-device AI",
                            url: "https://developer.apple.com/apple-intelligence/",
                            icon: "apple.logo"
                        )
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
                    .foregroundStyle(.secondary)

                Text("Copyright © 2026 David Edgar")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
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
