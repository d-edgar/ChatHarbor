import Foundation
import Combine
import SwiftUI
import SwiftData

// MARK: - Chat Manager
//
// Central state manager for ChatHarbor's LLM chat interface.
// Handles conversation lifecycle, model selection, multi-model compare,
// conversation forking, prompt templates, and export.

@MainActor
class ChatManager: ObservableObject {

    // MARK: - Published State

    @Published var selectedConversationId: UUID?
    @Published var selectedModelId: String = ""
    @Published var isGenerating: Bool = false
    @Published var streamingContent: String = ""
    @Published var isLaunching: Bool = true
    @Published var showingModelManager: Bool = false
    @Published var settingsTab: String = "general"
    @Published var showingPromptLibrary: Bool = false
    @Published var showingCompareView: Bool = false

    // Compare mode
    @Published var compareSlots: [CompareSlot] = []
    @Published var isComparing: Bool = false
    @Published var comparePrompt: String = ""

    // Prompt templates
    @Published var customTemplates: [PromptTemplate] = [] {
        didSet { persistTemplates() }
    }

    var allTemplates: [PromptTemplate] {
        PromptLibrary.builtIn + customTemplates
    }

    @Published var appearanceMode: AppearanceMode {
        didSet {
            persistAppearance()
            applyAppearance()
        }
    }

    @Published var selectedThemeId: String {
        didSet { persistTheme() }
    }

    @Published var ollamaBaseURL: String {
        didSet { persistOllamaURL() }
    }

    // General settings
    @Published var forkPrefix: String {
        didSet { UserDefaults.standard.set(forkPrefix, forKey: forkPrefixKey) }
    }

    @Published var streamResponses: Bool {
        didSet { UserDefaults.standard.set(streamResponses, forKey: streamResponsesKey) }
    }

    @Published var sendOnEnter: Bool {
        didSet { UserDefaults.standard.set(sendOnEnter, forKey: sendOnEnterKey) }
    }

    @Published var autoTitleConversations: Bool {
        didSet { UserDefaults.standard.set(autoTitleConversations, forKey: autoTitleKey) }
    }

    /// The resolved theme object
    var currentTheme: AppTheme {
        ThemeCatalog.theme(forId: selectedThemeId)
    }

    let ollama = OllamaService.shared
    let providers: ProviderManager

    // MARK: - Persistence Keys

    private let appearanceKey = "chatharbor.appearance"
    private let themeKey = "chatharbor.theme"
    private let selectedModelKey = "chatharbor.selectedModel"
    private let ollamaURLKey = "chatharbor.ollamaURL"
    private let templatesKey = "chatharbor.customTemplates"
    private let forkPrefixKey = "chatharbor.forkPrefix"
    private let streamResponsesKey = "chatharbor.streamResponses"
    private let sendOnEnterKey = "chatharbor.sendOnEnter"
    private let autoTitleKey = "chatharbor.autoTitle"

    private var streamTask: Task<Void, Never>?
    private var compareTasks: [Task<Void, Never>] = []
    private var nestedCancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        // Initialize provider manager
        self.providers = ProviderManager(ollama: OllamaService.shared)

        // Load appearance
        if let saved = UserDefaults.standard.string(forKey: appearanceKey),
           let mode = AppearanceMode(rawValue: saved) {
            self.appearanceMode = mode
        } else {
            self.appearanceMode = .auto
        }

        // Load theme
        if let savedTheme = UserDefaults.standard.string(forKey: themeKey) {
            self.selectedThemeId = savedTheme
        } else {
            self.selectedThemeId = ThemeCatalog.defaultTheme.id
        }

        // Load selected model
        if let savedModel = UserDefaults.standard.string(forKey: selectedModelKey) {
            self.selectedModelId = savedModel
        }

        // Load Ollama URL
        if let savedURL = UserDefaults.standard.string(forKey: ollamaURLKey) {
            self.ollamaBaseURL = savedURL
        } else {
            self.ollamaBaseURL = "http://localhost:11434"
        }

        // Load general settings
        if let savedPrefix = UserDefaults.standard.string(forKey: forkPrefixKey) {
            self.forkPrefix = savedPrefix
        } else {
            self.forkPrefix = "Fork:"
        }
        self.streamResponses = UserDefaults.standard.object(forKey: streamResponsesKey) as? Bool ?? true
        self.sendOnEnter = UserDefaults.standard.object(forKey: sendOnEnterKey) as? Bool ?? true
        self.autoTitleConversations = UserDefaults.standard.object(forKey: autoTitleKey) as? Bool ?? true

        // Load custom templates
        if let data = UserDefaults.standard.data(forKey: templatesKey),
           let decoded = try? JSONDecoder().decode([PromptTemplate].self, from: data) {
            self.customTemplates = decoded
        }

        // Apply appearance
        applyAppearance()

        // Forward objectWillChange from nested ObservableObjects so SwiftUI re-renders
        // (must be after all stored properties are initialized)
        providers.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &nestedCancellables)
        ollama.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &nestedCancellables)
        providers.openAI.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &nestedCancellables)
        providers.anthropic.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &nestedCancellables)
        providers.apple.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &nestedCancellables)

        // Connect all providers and dismiss splash
        Task {
            if let url = URL(string: ollamaBaseURL) {
                ollama.baseURL = url
            }
            await providers.connectAll()

            // Auto-select first model if none selected
            if selectedModelId.isEmpty || providers.allModels.first(where: { $0.id == selectedModelId }) == nil {
                if let first = providers.allModels.first {
                    selectedModelId = first.id
                    persistSelectedModel()
                }
            }

            try? await Task.sleep(for: .seconds(1))
            withAnimation(.easeInOut(duration: 0.3)) {
                isLaunching = false
            }
        }
    }

    // MARK: - Conversation Management

    func createConversation(in context: ModelContext, systemPrompt: String = "") -> Conversation {
        let conversation = Conversation(
            title: "New Conversation",
            modelId: selectedModelId,
            systemPrompt: systemPrompt
        )
        context.insert(conversation)
        try? context.save()
        selectedConversationId = conversation.id
        return conversation
    }

    func deleteConversation(_ conversation: Conversation, in context: ModelContext) {
        if selectedConversationId == conversation.id {
            selectedConversationId = nil
        }
        context.delete(conversation)
        try? context.save()
    }

    // MARK: - Conversation Forking

    /// Fork a conversation at a specific message, creating a new branch
    /// that includes all messages up to (and including) the fork point.
    func forkConversation(
        _ conversation: Conversation,
        atMessage message: Message,
        in context: ModelContext
    ) -> Conversation {
        let fork = Conversation(
            title: "\(forkPrefix) \(conversation.title)",
            modelId: conversation.modelId,
            systemPrompt: conversation.systemPrompt,
            forkedFromId: conversation.id,
            forkedAtMessageId: message.id
        )
        // Copy per-conversation parameter overrides
        fork.temperature = conversation.temperature
        fork.maxTokens = conversation.maxTokens
        fork.topP = conversation.topP
        fork.frequencyPenalty = conversation.frequencyPenalty
        fork.presencePenalty = conversation.presencePenalty
        fork.savedPresetName = conversation.savedPresetName
        context.insert(fork)

        // Copy messages up to and including the fork point
        let sorted = conversation.sortedMessages
        for msg in sorted {
            let copy = Message(
                role: msg.role,
                content: msg.content,
                modelUsed: msg.modelUsed
            )
            copy.tokenCount = msg.tokenCount
            copy.inputTokenCount = msg.inputTokenCount
            copy.durationMs = msg.durationMs
            fork.messages.append(copy)

            if msg.id == message.id { break }
        }

        try? context.save()
        selectedConversationId = fork.id
        return fork
    }

    // MARK: - Send Message

    func sendMessage(
        _ text: String,
        in conversation: Conversation,
        context: ModelContext
    ) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !isGenerating else { return }

        // Add user message
        let userMessage = Message(role: .user, content: text)
        conversation.messages.append(userMessage)
        conversation.updatedAt = Date()

        // Auto-title from first message
        if conversation.messages.filter({ $0.role == .user }).count == 1 {
            conversation.title = conversation.autoTitle
        }

        try? context.save()

        let modelToUse = conversation.modelId.isEmpty ? selectedModelId : conversation.modelId

        // Create placeholder assistant message
        let assistantMessage = Message(role: .assistant, content: "", isStreaming: true, modelUsed: modelToUse)
        conversation.messages.append(assistantMessage)
        try? context.save()

        // Build message history for the API
        var apiMessages: [ChatMessage] = []

        // System prompt: conversation-level → provider default → nothing
        let systemPrompt: String = {
            if !conversation.systemPrompt.isEmpty { return conversation.systemPrompt }
            let parts = modelToUse.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let provDefault = providers.defaultSystemPrompt(for: String(parts[0]))
                if !provDefault.isEmpty { return provDefault }
            }
            return ""
        }()

        if !systemPrompt.isEmpty {
            apiMessages.append(ChatMessage(role: .system, content: systemPrompt))
        }

        for msg in conversation.sortedMessages where !msg.isStreaming {
            let role = ChatMessageRole(rawValue: msg.role.rawValue) ?? .user
            apiMessages.append(ChatMessage(role: role, content: msg.content))
        }

        // Parameters: conversation-level overrides merge onto provider defaults
        let conversationParams = conversation.chatParameters

        isGenerating = true
        streamingContent = ""

        streamTask = Task {
            do {
                let result = try await providers.chat(
                    qualifiedModelId: modelToUse,
                    messages: apiMessages,
                    parameters: conversationParams
                ) { [weak self] token in
                    Task { @MainActor in
                        self?.streamingContent += token
                        assistantMessage.content += token
                    }
                }

                assistantMessage.isStreaming = false
                assistantMessage.tokenCount = result.tokenCount
                assistantMessage.inputTokenCount = result.inputTokenCount
                assistantMessage.durationMs = result.durationMs
                assistantMessage.modelUsed = modelToUse
                conversation.updatedAt = Date()
                try? context.save()
            } catch {
                if !Task.isCancelled {
                    assistantMessage.content = "Error: \(error.localizedDescription)"
                    assistantMessage.isStreaming = false
                    try? context.save()
                }
            }

            isGenerating = false
            streamingContent = ""
        }
    }

    /// Stop the current generation
    func stopGenerating() {
        streamTask?.cancel()
        streamTask = nil
        isGenerating = false
        streamingContent = ""
    }

    // MARK: - Multi-Model Compare

    /// Send the same prompt to multiple models simultaneously and stream all responses
    func startCompare(prompt: String, models: [String]) {
        guard !models.isEmpty else { return }

        isComparing = true
        comparePrompt = prompt
        compareSlots = models.map { CompareSlot(modelName: $0) }

        // Cancel any existing compare tasks
        compareTasks.forEach { $0.cancel() }
        compareTasks = []

        for (index, modelName) in models.enumerated() {
            let task = Task {
                do {
                    let apiMessages = [ChatMessage(role: .user, content: prompt)]

                    let result = try await providers.chat(
                        qualifiedModelId: modelName,
                        messages: apiMessages
                    ) { [weak self] token in
                        Task { @MainActor in
                            guard let self = self, index < self.compareSlots.count else { return }
                            self.compareSlots[index].content += token
                        }
                    }

                    compareSlots[index].isStreaming = false
                    compareSlots[index].tokenCount = result.tokenCount
                    compareSlots[index].durationMs = result.durationMs
                } catch {
                    if !Task.isCancelled {
                        compareSlots[index].isStreaming = false
                        compareSlots[index].error = error.localizedDescription
                    }
                }

                // Check if all slots are done
                if compareSlots.allSatisfy({ !$0.isStreaming }) {
                    isComparing = false
                }
            }
            compareTasks.append(task)
        }
    }

    func stopCompare() {
        compareTasks.forEach { $0.cancel() }
        compareTasks = []
        isComparing = false
        for i in compareSlots.indices {
            compareSlots[i].isStreaming = false
        }
    }

    /// Cross-provider compare: send the same prompt to models from any provider
    func startCrossProviderCompare(prompt: String, qualifiedModelIds: [String]) {
        guard !qualifiedModelIds.isEmpty else { return }

        isComparing = true
        comparePrompt = prompt

        // Build display names from provider info
        compareSlots = qualifiedModelIds.map { qid in
            let info = providers.providerInfo(for: qid)
            return CompareSlot(modelName: "\(info.modelName) (\(info.providerName))")
        }

        compareTasks.forEach { $0.cancel() }
        compareTasks = providers.compare(
            prompt: prompt,
            qualifiedModelIds: qualifiedModelIds,
            onSlotUpdate: { [weak self] index, token in
                guard let self = self, index < self.compareSlots.count else { return }
                self.compareSlots[index].content += token
            },
            onSlotComplete: { [weak self] index, result in
                guard let self = self, index < self.compareSlots.count else { return }
                self.compareSlots[index].isStreaming = false
                self.compareSlots[index].tokenCount = result.tokenCount
                self.compareSlots[index].durationMs = result.durationMs

                if self.compareSlots.allSatisfy({ !$0.isStreaming }) {
                    self.isComparing = false
                }
            },
            onSlotError: { [weak self] index, error in
                guard let self = self, index < self.compareSlots.count else { return }
                self.compareSlots[index].isStreaming = false
                self.compareSlots[index].error = error.localizedDescription

                if self.compareSlots.allSatisfy({ !$0.isStreaming }) {
                    self.isComparing = false
                }
            }
        )
    }

    // MARK: - Prompt Templates

    func addTemplate(_ template: PromptTemplate) {
        customTemplates.append(template)
    }

    func deleteTemplate(_ template: PromptTemplate) {
        guard !template.isBuiltIn else { return }
        customTemplates.removeAll { $0.id == template.id }
    }

    func updateTemplate(_ template: PromptTemplate) {
        if let index = customTemplates.firstIndex(where: { $0.id == template.id }) {
            customTemplates[index] = template
        }
    }

    // MARK: - Export

    /// Export a conversation to Markdown
    func exportToMarkdown(_ conversation: Conversation) -> String {
        var md = "# \(conversation.title)\n\n"
        md += "*Exported from ChatHarbor · \(conversation.createdAt.formatted(date: .long, time: .shortened))*\n\n"

        if !conversation.systemPrompt.isEmpty {
            md += "> **System Prompt:** \(conversation.systemPrompt)\n\n"
        }

        md += "**Model:** \(conversation.modelId.isEmpty ? "Default" : conversation.modelId)\n\n"
        md += "---\n\n"

        for message in conversation.sortedMessages {
            switch message.role {
            case .system:
                continue
            case .user:
                md += "### You\n\n\(message.content)\n\n"
            case .assistant:
                let model = message.modelUsed ?? conversation.modelId
                let modelLabel = model.isEmpty ? "Assistant" : model
                md += "### \(modelLabel)\n\n\(message.content)\n\n"

                if let tokens = message.tokenCount, let duration = message.durationMs {
                    let tps = duration > 0 ? String(format: "%.1f tok/s", Double(tokens) / (duration / 1000.0)) : ""
                    md += "*\(tokens) tokens · \(Self.formatDuration(duration))\(tps.isEmpty ? "" : " · \(tps)")*\n\n"
                }
            }
        }

        md += "---\n\n*\(conversation.messages.count) messages · \(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))*\n"
        return md
    }

    static func formatDuration(_ ms: Double) -> String {
        if ms < 1000 {
            return "\(Int(ms))ms"
        } else {
            return String(format: "%.1fs", ms / 1000.0)
        }
    }

    // MARK: - Model Selection

    func selectModel(_ modelId: String) {
        selectedModelId = modelId
        persistSelectedModel()
    }

    // MARK: - Appearance

    func applyAppearance() {
        switch appearanceMode {
        case .auto:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    // MARK: - Persistence

    private func persistAppearance() {
        UserDefaults.standard.set(appearanceMode.rawValue, forKey: appearanceKey)
    }

    private func persistTheme() {
        UserDefaults.standard.set(selectedThemeId, forKey: themeKey)
    }

    private func persistSelectedModel() {
        UserDefaults.standard.set(selectedModelId, forKey: selectedModelKey)
    }

    private func persistOllamaURL() {
        UserDefaults.standard.set(ollamaBaseURL, forKey: ollamaURLKey)
        if let url = URL(string: ollamaBaseURL) {
            ollama.baseURL = url
        }
    }

    private func persistTemplates() {
        if let data = try? JSONEncoder().encode(customTemplates) {
            UserDefaults.standard.set(data, forKey: templatesKey)
        }
    }
}

// MARK: - Appearance Mode

enum AppearanceMode: String, CaseIterable {
    case auto = "auto"
    case light = "light"
    case dark = "dark"

    var displayName: String {
        switch self {
        case .auto: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
