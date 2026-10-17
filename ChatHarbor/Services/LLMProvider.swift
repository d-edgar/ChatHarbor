import Foundation
import CoreFoundation

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
    let usage: TokenUsage
    var tokenCount: Int? { usage.output }
    var inputTokenCount: Int? { usage.input }
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

// Shared across chat, brainstorm, and comparison so missing prices stay explicit.
enum UsageFormatting {
    static func cost(_ value: Double?) -> String {
        guard let value else { return "Cost unavailable" }
        return String(format: value < 0.01 ? "~$%.5f" : "~$%.2f", value)
    }
}

/// Input includes cached tokens; output includes reasoning tokens. Breakdowns are subsets, not extras.
struct TokenUsage: Codable, Equatable {
    var input: Int?
    var output: Int?
    var cachedInput: Int?
    var cacheWriteInput: Int?
    var reasoning: Int?
    var isEstimated = false

    var total: Int? { Self.sum([input, output]) }
    var encoded: Data? { try? JSONEncoder().encode(self) }
    var summary: String { "\(label(input)) in · \(label(output)) out" }
    var details: String {
        var parts = [isEstimated ? "Estimated tokens" : "Provider-reported tokens; — means unavailable"]
        if let cachedInput { parts.append("\(cachedInput) cached input (included)") }
        if let cacheWriteInput { parts.append("\(cacheWriteInput) cache-write input (included)") }
        if let reasoning { parts.append("\(reasoning) thinking output (included)") }
        return parts.joined(separator: " · ")
    }

    func label(_ count: Int?) -> String {
        count.map { "\(isEstimated ? "~" : "")\($0)" } ?? "—"
    }

    func speed(durationMs: Double?) -> String {
        guard let output, let durationMs, durationMs > 0 else { return "—" }
        return (isEstimated ? "~" : "") + String(format: "%.1f/s", Double(output) / (durationMs / 1000))
    }

    static func restore(_ data: Data?, input: Int?, output: Int?) -> TokenUsage {
        if let data, let usage = try? JSONDecoder().decode(Self.self, from: data) { return usage }
        // Older records did not distinguish estimates or missing usage from zero.
        return TokenUsage(input: input.flatMap { $0 > 0 ? $0 : nil },
                          output: output.flatMap { $0 > 0 ? $0 : nil },
                          isEstimated: (input ?? 0) > 0 || (output ?? 0) > 0)
    }

    static func count(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              let value = value as? Int, value >= 0 else { return nil }
        return value
    }

    static func sum(_ counts: [Int?]) -> Int? {
        var total = 0
        for count in counts {
            guard let count, count >= 0 else { return nil }
            let (next, overflow) = total.addingReportingOverflow(count)
            guard !overflow else { return nil }
            total = next
        }
        return total
    }

    static func combined(_ usages: [TokenUsage]) -> TokenUsage {
        TokenUsage(input: sum(usages.map(\.input)), output: sum(usages.map(\.output)),
                   cachedInput: sum(usages.map(\.cachedInput)), cacheWriteInput: sum(usages.map(\.cacheWriteInput)),
                   reasoning: sum(usages.map(\.reasoning)), isEstimated: usages.contains { $0.isEstimated })
    }

    static func openAI(_ usage: [String: Any]) -> TokenUsage {
        TokenUsage(input: count(usage["prompt_tokens"]), output: count(usage["completion_tokens"]),
                   cachedInput: count((usage["prompt_tokens_details"] as? [String: Any])?["cached_tokens"]),
                   reasoning: count((usage["completion_tokens_details"] as? [String: Any])?["reasoning_tokens"]))
    }

    static func anthropic(_ usage: [String: Any]) -> TokenUsage {
        let cached = count(usage["cache_read_input_tokens"])
        let written = count(usage["cache_creation_input_tokens"])
        return TokenUsage(input: sum([count(usage["input_tokens"]), count(usage["cache_read_input_tokens"] ?? 0), count(usage["cache_creation_input_tokens"] ?? 0)]),
                          output: count(usage["output_tokens"]), cachedInput: cached, cacheWriteInput: written)
    }

    static func gemini(_ usage: [String: Any]) -> TokenUsage {
        let thoughts = count(usage["thoughtsTokenCount"])
        return TokenUsage(input: count(usage["promptTokenCount"]),
                          output: sum([count(usage["candidatesTokenCount"]), count(usage["thoughtsTokenCount"] ?? 0)]),
                          cachedInput: count(usage["cachedContentTokenCount"]), reasoning: thoughts)
    }
}
