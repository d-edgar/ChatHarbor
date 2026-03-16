import Foundation
import Combine
import SwiftUI

// MARK: - Provider Manager
//
// Coordinates all LLM providers (Ollama, OpenAI, Anthropic).
// Provides a unified model list, handles cross-provider compare,
// and enables "fork to different model" across providers.

@MainActor
class ProviderManager: ObservableObject {

    // MARK: - Providers

    let ollama: OllamaService
    let openAI: OpenAIProvider
    let anthropic: AnthropicProvider

    /// All registered providers
    var allProviders: [any LLMProvider] {
        [ollama, openAI, anthropic]
    }

    /// All connected providers
    var connectedProviders: [any LLMProvider] {
        allProviders.filter { $0.isConnected }
    }

    // MARK: - Unified Model List (computed — always up-to-date)

    /// All available models across all connected providers
    var allModels: [ProviderModel] {
        var models: [ProviderModel] = []
        models.append(contentsOf: ollama.models)
        models.append(contentsOf: openAI.models)
        models.append(contentsOf: anthropic.models)
        return models
    }

    // MARK: - Init

    init(ollama: OllamaService) {
        self.ollama = ollama
        self.openAI = OpenAIProvider()
        self.anthropic = AnthropicProvider()
    }

    // MARK: - Connect All

    /// Connect to all providers that have credentials configured
    func connectAll() async {
        // Run all connections in parallel
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.ollama.connect() }
            group.addTask { await self.openAI.connect() }
            group.addTask { await self.anthropic.connect() }
        }
        // Notify observers that models may have changed
        objectWillChange.send()
    }

    /// Refresh a single provider
    func reconnect(_ providerId: String) async {
        switch providerId {
        case "ollama": await ollama.connect()
        case "openai": await openAI.connect()
        case "anthropic": await anthropic.connect()
        default: break
        }
        objectWillChange.send()
    }

    // MARK: - Model Lookup

    /// Find the provider for a given model ID (format: "providerId:modelId")
    func provider(for qualifiedModelId: String) -> (any LLMProvider)? {
        let parts = qualifiedModelId.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else {
            // Legacy: unqualified ID, assume Ollama
            return ollama
        }
        let pid = String(parts[0])
        return allProviders.first { $0.providerId == pid }
    }

    /// Extract the raw model ID from a qualified ID
    func rawModelId(from qualifiedId: String) -> String {
        let parts = qualifiedId.split(separator: ":", maxSplits: 1)
        if parts.count == 2 {
            return String(parts[1])
        }
        return qualifiedId
    }

    /// Get provider display info for a qualified model ID
    func providerInfo(for qualifiedId: String) -> (providerName: String, modelName: String, icon: String) {
        if let model = allModels.first(where: { $0.id == qualifiedId }) {
            let prov = allProviders.first { $0.providerId == model.providerId }
            return (
                providerName: prov?.displayName ?? model.providerId,
                modelName: model.displayName,
                icon: prov?.iconName ?? "cpu"
            )
        }

        // Fallback: parse the qualified ID to get a friendly name
        let parts = qualifiedId.split(separator: ":", maxSplits: 1)
        if parts.count == 2 {
            let provId = String(parts[0])
            let modelId = String(parts[1])
            let provName = allProviders.first { $0.providerId == provId }?.displayName ?? provId.capitalized
            return (providerName: provName, modelName: friendlyModelName(modelId), icon: providerIcon(provId))
        }

        return (providerName: "Ollama", modelName: qualifiedId, icon: "desktopcomputer")
    }

    /// Turn a raw model ID like "claude-sonnet-4-20250514" into "Claude Sonnet 4"
    func friendlyModelName(_ rawId: String) -> String {
        // Strip date suffixes like -20250514 or -20241022
        var name = rawId
        if let range = name.range(of: #"-\d{8}$"#, options: .regularExpression) {
            name = String(name[name.startIndex..<range.lowerBound])
        }
        // Strip :latest suffix
        if name.hasSuffix(":latest") {
            name = String(name.dropLast(7))
        }
        // Capitalize words and clean up
        return name
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { word in
                let w = String(word)
                // Keep version numbers and known abbreviations as-is
                if w.allSatisfy({ $0.isNumber || $0 == "." }) { return w }
                if ["gpt", "o1", "o3"].contains(w.lowercased()) { return w.uppercased() }
                return w.prefix(1).uppercased() + w.dropFirst()
            }
            .joined(separator: " ")
    }

    private func providerIcon(_ providerId: String) -> String {
        switch providerId {
        case "ollama": return "desktopcomputer"
        case "openai": return "brain"
        case "anthropic": return "sparkle"
        default: return "cpu"
        }
    }

    // MARK: - Chat

    /// Send a chat message through the appropriate provider
    func chat(
        qualifiedModelId: String,
        messages: [ChatMessage],
        onToken: @escaping (String) -> Void
    ) async throws -> ChatResult {
        guard let prov = provider(for: qualifiedModelId) else {
            throw LLMProviderError.notConnected
        }
        let rawId = rawModelId(from: qualifiedModelId)
        return try await prov.chat(model: rawId, messages: messages, onToken: onToken)
    }

    // MARK: - Cross-Provider Compare

    /// Run the same prompt across multiple models (potentially different providers)
    func compare(
        prompt: String,
        systemPrompt: String? = nil,
        qualifiedModelIds: [String],
        onSlotUpdate: @escaping @MainActor (Int, String) -> Void,
        onSlotComplete: @escaping @MainActor (Int, ChatResult) -> Void,
        onSlotError: @escaping @MainActor (Int, Error) -> Void
    ) -> [Task<Void, Never>] {
        var messages: [ChatMessage] = []
        if let system = systemPrompt, !system.isEmpty {
            messages.append(ChatMessage(role: .system, content: system))
        }
        messages.append(ChatMessage(role: .user, content: prompt))

        var tasks: [Task<Void, Never>] = []

        for (index, qualifiedId) in qualifiedModelIds.enumerated() {
            let task = Task {
                do {
                    let result = try await self.chat(
                        qualifiedModelId: qualifiedId,
                        messages: messages
                    ) { token in
                        Task { @MainActor in
                            onSlotUpdate(index, token)
                        }
                    }
                    onSlotComplete(index, result)
                } catch {
                    if !Task.isCancelled {
                        onSlotError(index, error)
                    }
                }
            }
            tasks.append(task)
        }

        return tasks
    }
}
