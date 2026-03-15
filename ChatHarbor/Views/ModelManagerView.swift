import SwiftUI

// MARK: - Model Manager View
//
// Shows ALL providers — Ollama (local), OpenAI, Anthropic — with their
// models, connection status, and management controls. Ollama models can
// be pulled and deleted; cloud models appear automatically when connected.

struct ModelManagerView: View {
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettingsAction
    @State private var pullModelName: String = ""
    @State private var showingDeleteConfirm: String?
    @State private var errorMessage: String?
    @State private var selectedTab: ProviderTab = .all

    private var accent: Color {
        chatManager.currentTheme.accentColor(for: colorScheme)
    }

    enum ProviderTab: String, CaseIterable {
        case all = "All"
        case ollama = "Ollama"
        case openai = "OpenAI"
        case anthropic = "Anthropic"
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            HStack {
                Text("Model Manager")
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                // Provider summary
                let connected = chatManager.providers.connectedProviders.count
                let total = chatManager.providers.allProviders.count
                Text("\(connected)/\(total) providers")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text("·")
                    .foregroundStyle(.quaternary)

                Text("\(chatManager.providers.allModels.count) models")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Button {
                    Task { await chatManager.providers.connectAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Refresh all providers")

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close (Esc)")
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(20)

            Divider()

            // MARK: - Tab bar
            HStack(spacing: 2) {
                ForEach(ProviderTab.allCases, id: \.self) { tab in
                    ManagerTabButton(
                        label: tab.rawValue,
                        icon: iconForTab(tab),
                        isSelected: selectedTab == tab,
                        badge: badgeForTab(tab),
                        accent: accent
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // MARK: - Content
            ScrollView {
                LazyVStack(spacing: 16) {
                    switch selectedTab {
                    case .all:
                        allProvidersSection
                    case .ollama:
                        ollamaSection
                    case .openai:
                        cloudProviderSection(
                            provider: chatManager.providers.openAI,
                            hint: "Add your OpenAI API key in Settings → Providers to see GPT-4o, o1, o3 and more."
                        )
                    case .anthropic:
                        cloudProviderSection(
                            provider: chatManager.providers.anthropic,
                            hint: "Add your Anthropic API key in Settings → Providers to use Claude Sonnet, Opus, and Haiku."
                        )
                    }
                }
                .padding(16)
            }

            // Error message
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Dismiss") { errorMessage = nil }
                        .font(.caption)
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .frame(width: 620, height: 580)
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
            Text("Are you sure you want to delete \(showingDeleteConfirm ?? "")? This will free up disk space but you'll need to pull it again to use it.")
        }
    }

    // MARK: - All Providers Section

    @ViewBuilder
    private var allProvidersSection: some View {
        // Ollama group
        ProviderGroupHeader(
            icon: "desktopcomputer",
            name: "Ollama (Local)",
            isConnected: chatManager.ollama.isConnected,
            modelCount: chatManager.ollama.availableModels.count,
            accent: accent
        )

        if chatManager.ollama.isConnected {
            if chatManager.ollama.availableModels.isEmpty {
                emptyProviderHint(text: "No local models yet. Pull one in the Ollama tab.", icon: "arrow.down.circle")
            } else {
                ForEach(chatManager.ollama.availableModels) { model in
                    UnifiedModelRow(
                        name: model.displayName,
                        detail: [model.parameterSize, model.quantizationLevel, model.formattedSize].filter { !$0.isEmpty }.joined(separator: " · "),
                        qualifiedId: "ollama:\(model.name)",
                        isLocal: true,
                        isSelected: "ollama:\(model.name)" == chatManager.selectedModelId,
                        canDelete: true,
                        onSelect: { chatManager.selectModel("ollama:\(model.name)") },
                        onDelete: { showingDeleteConfirm = model.name },
                        accent: accent
                    )
                }
            }
        } else {
            emptyProviderHint(text: "Ollama not running. Open the app or run `ollama serve`.", icon: "desktopcomputer")
        }

        // OpenAI group
        ProviderGroupHeader(
            icon: "brain",
            name: "OpenAI",
            isConnected: chatManager.providers.openAI.isConnected,
            modelCount: chatManager.providers.openAI.models.count,
            accent: accent
        )
        .padding(.top, 8)

        if chatManager.providers.openAI.isConnected {
            ForEach(chatManager.providers.openAI.models) { model in
                UnifiedModelRow(
                    name: model.displayName,
                    detail: model.contextWindow.map { "\($0 / 1000)K context" } ?? "",
                    qualifiedId: model.id,
                    isLocal: false,
                    isSelected: model.id == chatManager.selectedModelId,
                    canDelete: false,
                    onSelect: { chatManager.selectModel(model.id) },
                    onDelete: {},
                    accent: accent
                )
            }
        } else {
            emptyProviderHint(
                text: chatManager.providers.openAI.apiKey.isEmpty
                    ? "Add your API key in Settings → Providers"
                    : "Could not connect — check your API key",
                icon: "key"
            )
        }

        // Anthropic group
        ProviderGroupHeader(
            icon: "sparkle",
            name: "Anthropic",
            isConnected: chatManager.providers.anthropic.isConnected,
            modelCount: chatManager.providers.anthropic.models.count,
            accent: accent
        )
        .padding(.top, 8)

        if chatManager.providers.anthropic.isConnected {
            ForEach(chatManager.providers.anthropic.models) { model in
                UnifiedModelRow(
                    name: model.displayName,
                    detail: model.contextWindow.map { "\($0 / 1000)K context" } ?? "",
                    qualifiedId: model.id,
                    isLocal: false,
                    isSelected: model.id == chatManager.selectedModelId,
                    canDelete: false,
                    onSelect: { chatManager.selectModel(model.id) },
                    onDelete: {},
                    accent: accent
                )
            }
        } else {
            emptyProviderHint(
                text: chatManager.providers.anthropic.apiKey.isEmpty
                    ? "Add your API key in Settings → Providers"
                    : "Could not connect — check your API key",
                icon: "key"
            )
        }
    }

    // MARK: - Ollama Section (with Pull)

    @ViewBuilder
    private var ollamaSection: some View {
        // Connection status
        HStack(spacing: 8) {
            Circle()
                .fill(chatManager.ollama.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(chatManager.ollama.isConnected ? "Ollama is running" : "Ollama not detected")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                Task { await chatManager.ollama.checkConnection() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }

        // Pull new model
        VStack(alignment: .leading, spacing: 8) {
            Text("PULL A MODEL")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("Model name (e.g. llama3.2, mistral, codellama)", text: $pullModelName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .onSubmit { pullModel() }

                Button("Pull") { pullModel() }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .disabled(pullModelName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .disabled(chatManager.ollama.pullProgress != nil)
            }

            // Pull progress
            if let progress = chatManager.ollama.pullProgress {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Pulling \(progress.modelName)")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        if progress.total > 0 {
                            Text("\(Int(progress.fraction * 100))%")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(accent)
                        }
                    }

                    HStack(spacing: 6) {
                        Image(systemName: statusIcon(for: progress.status))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(progress.status.isEmpty ? "Connecting…" : progress.status.capitalized)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: progress.fraction)
                        .tint(accent)

                    if progress.total > 0 {
                        HStack {
                            Text(formatBytes(progress.completed))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text("of")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            Text(formatBytes(progress.total))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accent.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(accent.opacity(0.15), lineWidth: 1)
                )
            }

            // Quick-pull buttons
            VStack(alignment: .leading, spacing: 6) {
                Text("QUICK PULL")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)

                FlowLayout(spacing: 6) {
                    ForEach(popularModels, id: \.name) { model in
                        Button {
                            pullModelName = model.name
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 10))
                                Text(model.name)
                                    .font(.system(size: 11, weight: .medium))
                                Text(model.size)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(accent.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(accent.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(accent)
                    }
                }
            }
        }

        Divider()

        // Installed models
        HStack {
            Text("INSTALLED MODELS")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(chatManager.ollama.availableModels.count) models")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }

        if chatManager.ollama.availableModels.isEmpty {
            emptyProviderHint(
                text: chatManager.ollama.isConnected
                    ? "No models installed yet. Pull one above to get started."
                    : "Can't connect to Ollama. Make sure it's running.",
                icon: "cpu"
            )
        } else {
            ForEach(chatManager.ollama.availableModels) { model in
                UnifiedModelRow(
                    name: model.displayName,
                    detail: [model.parameterSize, model.quantizationLevel, model.formattedSize, model.family].filter { !$0.isEmpty }.joined(separator: " · "),
                    qualifiedId: "ollama:\(model.name)",
                    isLocal: true,
                    isSelected: "ollama:\(model.name)" == chatManager.selectedModelId,
                    canDelete: true,
                    onSelect: { chatManager.selectModel("ollama:\(model.name)") },
                    onDelete: { showingDeleteConfirm = model.name },
                    accent: accent
                )
            }
        }
    }

    // MARK: - Cloud Provider Section

    @ViewBuilder
    private func cloudProviderSection(provider: some LLMProvider, hint: String) -> some View {
        // Connection status
        HStack(spacing: 8) {
            Circle()
                .fill(provider.isConnected ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 8, height: 8)
            Text(provider.isConnected ? "\(provider.displayName) connected" : "\(provider.displayName) not connected")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()

            Button {
                Task { await provider.connect() }
            } label: {
                Label("Reconnect", systemImage: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                openSettingsAction()
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }

        if provider.isConnected {
            HStack {
                Text("AVAILABLE MODELS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(provider.models.count) models")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            ForEach(provider.models) { model in
                UnifiedModelRow(
                    name: model.displayName,
                    detail: model.contextWindow.map { "\($0 / 1000)K context" } ?? "",
                    qualifiedId: model.id,
                    isLocal: false,
                    isSelected: model.id == chatManager.selectedModelId,
                    canDelete: false,
                    onSelect: { chatManager.selectModel(model.id) },
                    onDelete: {},
                    accent: accent
                )
            }
        } else {
            emptyProviderHint(text: hint, icon: "key")
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func emptyProviderHint(text: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.gray.opacity(0.4))
                .frame(width: 28)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.04))
        )
    }

    private func iconForTab(_ tab: ProviderTab) -> String {
        switch tab {
        case .all: return "square.grid.2x2"
        case .ollama: return "desktopcomputer"
        case .openai: return "brain"
        case .anthropic: return "sparkle"
        }
    }

    private func badgeForTab(_ tab: ProviderTab) -> Int {
        switch tab {
        case .all: return chatManager.providers.allModels.count
        case .ollama: return chatManager.ollama.availableModels.count
        case .openai: return chatManager.providers.openAI.models.count
        case .anthropic: return chatManager.providers.anthropic.models.count
        }
    }

    private struct PopularModel {
        let name: String
        let size: String
    }

    private var popularModels: [PopularModel] {
        [
            PopularModel(name: "llama3.2", size: "2B"),
            PopularModel(name: "llama3.2:3b", size: "3B"),
            PopularModel(name: "mistral", size: "7B"),
            PopularModel(name: "codellama", size: "7B"),
            PopularModel(name: "gemma2", size: "9B"),
            PopularModel(name: "phi3", size: "3.8B"),
            PopularModel(name: "qwen2.5", size: "7B"),
        ]
    }

    private func statusIcon(for status: String) -> String {
        let lower = status.lowercased()
        if lower.contains("pulling") || lower.contains("download") { return "arrow.down.circle" }
        if lower.contains("verifying") { return "checkmark.shield" }
        if lower.contains("writing") { return "doc.badge.arrow.up" }
        if lower.contains("success") { return "checkmark.circle.fill" }
        return "hourglass"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
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

// MARK: - Manager Tab Button

struct ManagerTabButton: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let badge: Int
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(isSelected ? accent : .secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(isSelected ? accent.opacity(0.12) : Color.gray.opacity(0.1))
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? accent : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? accent.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Provider Group Header

struct ProviderGroupHeader: View {
    let icon: String
    let name: String
    let isConnected: Bool
    let modelCount: Int
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(isConnected ? accent : Color.gray.opacity(0.5))

            Text(name.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)

            Circle()
                .fill(isConnected ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 6, height: 6)

            Spacer()

            Text("\(modelCount) models")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Unified Model Row

struct UnifiedModelRow: View {
    let name: String
    let detail: String
    let qualifiedId: String
    let isLocal: Bool
    let isSelected: Bool
    let canDelete: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let accent: Color

    @State private var isHovering: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Selection indicator
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundStyle(isSelected ? accent : Color.gray.opacity(0.3))

            // Local/Cloud badge
            Image(systemName: isLocal ? "desktopcomputer" : "cloud")
                .font(.system(size: 10))
                .foregroundStyle(isLocal ? .orange : .blue)
                .frame(width: 18)

            // Model info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(.primary)

                    if isSelected {
                        Text("ACTIVE")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(accent.opacity(0.12), in: Capsule())
                    }
                }

                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if isHovering && !isSelected {
                Text("Click to select")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            if canDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete model")
                .opacity(isHovering ? 1 : 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? accent.opacity(0.07) : isHovering ? Color.gray.opacity(0.05) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? accent.opacity(0.2) : isHovering ? Color.gray.opacity(0.12) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Flow Layout (wrapping horizontal layout)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(width: maxWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
