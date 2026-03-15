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
    func chat(
        model: String,
        messages: [ChatMessage],
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
        case "ollama": return "Ollama (Local)"
        case "openai": return "OpenAI"
        case "anthropic": return "Anthropic"
        case "google": return "Google"
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

/// Unified result from any provider
struct ChatResult {
    let content: String
    let tokenCount: Int
    let durationMs: Double
    let model: String
    let providerId: String
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
