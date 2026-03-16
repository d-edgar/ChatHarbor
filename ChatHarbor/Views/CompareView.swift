import SwiftUI

// MARK: - Compare View
//
// Side-by-side multi-model comparison. Send the same prompt to
// 2-4 models simultaneously and watch them respond in parallel.

struct CompareView: View {
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var promptText: String = ""
    @State private var selectedModels: Set<String> = []
    @FocusState private var promptFocused: Bool

    private var accent: Color {
        chatManager.currentTheme.accentColor(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            HStack {
                Image(systemName: "square.split.2x1")
                    .font(.system(size: 16))
                    .foregroundStyle(accent)
                Text("Model Compare")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()

                if chatManager.isComparing {
                    Button {
                        chatManager.stopCompare()
                    } label: {
                        Label("Stop All", systemImage: "stop.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                }

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
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            if chatManager.compareSlots.isEmpty {
                // MARK: - Setup State
                setupView
            } else {
                // MARK: - Results
                resultsView
            }

            Divider()

            // MARK: - Input
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Enter a prompt to compare across models…", text: $promptText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($promptFocused)
                    .onSubmit {
                        if !NSEvent.modifierFlags.contains(.shift) {
                            startComparison()
                        }
                    }
                    .font(.body)
                    .padding(.vertical, 8)

                Button {
                    startComparison()
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(canStart ? accent : Color.gray.opacity(0.3))
                }
                .buttonStyle(.plain)
                .disabled(!canStart)
                .help("Run comparison")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .onAppear {
            promptFocused = true
            // Pre-select first two models from any provider
            let models = chatManager.providers.allModels
            if selectedModels.isEmpty && models.count >= 2 {
                selectedModels = Set(models.prefix(2).map(\.id))
            } else if selectedModels.isEmpty, let first = models.first {
                selectedModels = [first.id]
            }
        }
    }

    private var canStart: Bool {
        !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedModels.count >= 2
            && !chatManager.isComparing
    }

    // MARK: - Setup View

    private var setupView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "square.split.2x1")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Compare Models Side by Side")
                .font(.headline)

            Text("Select 2–4 models below, type a prompt, and see how they respond to the same input.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            // Model selection grid
            modelSelectionGrid
                .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Model Selection Grid

    /// Models grouped by provider
    private var groupedModels: [(provider: String, models: [ProviderModel])] {
        let all = chatManager.providers.allModels
        let grouped = Dictionary(grouping: all, by: { $0.providerLabel })
        return grouped
            .sorted { $0.key < $1.key }
            .map { (provider: $0.key, models: $0.value) }
    }

    private var modelSelectionGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SELECT MODELS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(selectedModels.count) of 4 selected")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if groupedModels.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("No providers connected. Add API keys in Settings (⌘,) or start Ollama.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }

            ForEach(groupedModels, id: \.provider) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.provider.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 2)

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                    ], spacing: 6) {
                        ForEach(group.models) { model in
                            let isSelected = selectedModels.contains(model.id)
                            Button {
                                if isSelected {
                                    selectedModels.remove(model.id)
                                } else if selectedModels.count < 4 {
                                    selectedModels.insert(model.id)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isSelected ? accent : Color.gray.opacity(0.3))
                                    Text(model.displayName)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(isSelected ? .primary : .secondary)
                                        .lineLimit(1)
                                    Spacer()
                                    if model.isLocal {
                                        Image(systemName: "desktopcomputer")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Image(systemName: "cloud")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isSelected ? accent.opacity(0.08) : Color.gray.opacity(0.06))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isSelected ? accent.opacity(0.3) : Color.clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Results View

    private var resultsView: some View {
        ScrollView {
            // Prompt banner
            HStack(spacing: 8) {
                Image(systemName: "person.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(chatManager.comparePrompt)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // Side-by-side columns
            HStack(alignment: .top, spacing: 1) {
                ForEach(chatManager.compareSlots) { slot in
                    CompareColumn(slot: slot)
                        .environmentObject(chatManager)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Model selection for re-run
            modelSelectionGrid
                .padding(.top, 8)
                .padding(.bottom, 16)
        }
    }

    private func startComparison() {
        let prompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, selectedModels.count >= 2 else { return }
        let qualifiedIds = Array(selectedModels).sorted()
        chatManager.startCrossProviderCompare(prompt: prompt, qualifiedModelIds: qualifiedIds)
    }
}

// MARK: - Compare Column

struct CompareColumn: View {
    let slot: CompareSlot
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color {
        chatManager.currentTheme.accentColor(for: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Model header
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.system(size: 10))
                Text(slot.displayName)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if slot.isStreaming {
                    ProgressView()
                        .scaleEffect(0.5)
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))

            // Content
            if let error = slot.error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
            } else if slot.content.isEmpty && slot.isStreaming {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Thinking…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
            } else {
                Text(LocalizedStringKey(slot.content))
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(10)
            }

            // Stats
            if !slot.isStreaming, slot.error == nil {
                HStack(spacing: 6) {
                    if let tokens = slot.tokenCount {
                        Text("\(tokens) tok")
                    }
                    if let tps = slot.tokensPerSecond {
                        Text("·")
                        Text(String(format: "%.1f tok/s", tps))
                    }
                    if let ms = slot.durationMs {
                        Text("·")
                        Text(ChatManager.formatDuration(ms))
                    }
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}
