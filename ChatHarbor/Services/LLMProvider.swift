import Foundation

// MARK: - LLM Provider Protocol
//
// The unified interface every AI backend conforms to — Ollama, OpenAI,
// Anthropic, Google, or any OpenAI-compatible endpoint. This is what
// makes ChatHarbor the one app where all your AI lives.

@MainActor
protocol LLMProvider: AnyObject {
    /// Unique identifier for this provider (e.g. "ollama", "openai", "anthropic")
    var providerId: String { get }

    /// Human-readable name (e.g. "Ollama", "OpenAI", "Anthropic")
    var displayName: String { get }

    /// SF Symbol name for the provider icon
    var iconName: String { get }

    /// Whether this provider is currently reachable / authenticated
    var isConnected: Bool { get }

    /// Available models from this provider
    var models: [ProviderModel] { get }

    /// Check connectivity / auth and refresh available models
    func connect() async

    /// Stream a chat completion. Calls `onToken` for each chunk.
    /// Returns the final result with token count and duration.
    /// `parameters` are fully transparent — exactly what gets sent to the API.
    func chat(
        model: String,
        messages: [ChatMessage],
        parameters: ChatParameters,
        onToken: @escaping (String) -> Void
    ) async throws -> ChatResult
}

// MARK: - Shared Types

/// A model available from any provider
struct ProviderModel: Identifiable, Hashable {
    var id: String { "\(providerId):\(modelId)" }
    let providerId: String
    let modelId: String
    let displayName: String
    let contextWindow: Int?
    let isLocal: Bool

    /// For display in picker: "Claude 3.5 Sonnet" or "llama3.2"
    var label: String { displayName }

    /// For grouping: "Anthropic" or "Ollama"
    var providerLabel: String {
        switch providerId {
        case "apple": return "Apple Intelligence (On-Device)"
        case "ollama": return "Ollama (Local)"
        case "openai": return "OpenAI"
        case "anthropic": return "Anthropic"
        case "google": return "Google"
        case "custom": return "Custom"
        default: return providerId.capitalized
        }
    }
}

/// Unified message format for all providers
struct ChatMessage {
    let role: ChatMessageRole
    let content: String
}

enum ChatMessageRole: String {
    case system
    case user
    case assistant
}

/// Parameters that control model behavior — fully transparent to the user.
/// Every value here maps 1:1 to what's sent to the API.
struct ChatParameters: Sendable {
    var temperature: Double?      // 0.0–2.0, nil = provider default
    var maxTokens: Int?           // nil = provider default (e.g. 4096)
    var topP: Double?             // 0.0–1.0, nil = provider default
    var frequencyPenalty: Double?  // OpenAI only, -2.0 to 2.0
    var presencePenalty: Double?   // OpenAI only, -2.0 to 2.0

    /// Merge: conversation-level overrides provider defaults
    func merging(over defaults: ChatParameters) -> ChatParameters {
        ChatParameters(
            temperature: temperature ?? defaults.temperature,
            maxTokens: maxTokens ?? defaults.maxTokens,
            topP: topP ?? defaults.topP,
            frequencyPenalty: frequencyPenalty ?? defaults.frequencyPenalty,
            presencePenalty: presencePenalty ?? defaults.presencePenalty
        )
    }

    nonisolated static let empty = ChatParameters()
}

/// Unified result from any provider
struct ChatResult {
    let content: String
    let tokenCount: Int          // output tokens
    let inputTokenCount: Int     // input (prompt) tokens
    let durationMs: Double
    let model: String
    let providerId: String
}

// MARK: - Provider Icon Mapping
//
// Maps provider IDs to custom asset catalog images.
// Falls back to SF Symbols when no custom asset exists.

enum ProviderIcon {
    /// Custom asset names (from Assets.xcassets) keyed by provider ID
    private static let customAssets: [String: String] = [
        "anthropic": "AnthropicIcon",
        "openai": "OpenAIIcon",
        "ollama": "OllamaIcon",
    ]

    /// Returns true if this provider has a custom image asset
    static func hasCustomIcon(for providerId: String) -> Bool {
        customAssets[providerId] != nil
    }

    /// The custom asset name, or nil if none exists
    static func customAssetName(for providerId: String) -> String? {
        customAssets[providerId]
    }
}

// MARK: - Provider Errors

enum LLMProviderError: LocalizedError {
    case notConnected
    case invalidAPIKey
    case rateLimited
    case modelNotFound(String)
    case serverError(Int, String)
    case networkError(String)
    case streamingError(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Provider is not connected. Check your connection or API key."
        case .invalidAPIKey:
            return "Invalid API key. Check your settings."
        case .rateLimited:
            return "Rate limited. Try again in a moment."
        case .modelNotFound(let model):
            return "Model '\(model)' not found."
        case .serverError(let code, let msg):
            return "Server error (\(code)): \(msg)"
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .streamingError(let msg):
            return "Streaming error: \(msg)"
        }
    }
}
