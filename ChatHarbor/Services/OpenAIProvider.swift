import Foundation
import Combine

// MARK: - OpenAI Provider
//
// Connects to OpenAI's /v1/chat/completions endpoint with streaming.
// Also works with any OpenAI-compatible API (Groq, Together, Perplexity, etc.)
// by changing the base URL.

@MainActor
final class OpenAIProvider: ObservableObject, LLMProvider {

    let providerId = "openai"
    let displayName = "OpenAI"
    let iconName = "brain"

    @Published var isConnected: Bool = false
    @Published var models: [ProviderModel] = []
    @Published var apiKey: String = "" {
        didSet { persistAPIKey() }
    }
    @Published var baseURL: String = "https://api.openai.com/v1" {
        didSet { UserDefaults.standard.set(baseURL, forKey: "chatharbor.openai.baseURL") }
    }

    private let apiKeyKey = "chatharbor.openai.apiKey"
    private let baseURLKey = "chatharbor.openai.baseURL"

    init() {
        if let saved = UserDefaults.standard.string(forKey: apiKeyKey) {
            self.apiKey = saved
        }
        if let saved = UserDefaults.standard.string(forKey: baseURLKey), !saved.isEmpty {
            self.baseURL = saved
        }
    }

    // MARK: - Connect

    func connect() async {
        guard !apiKey.isEmpty else {
            isConnected = false
            models = []
            return
        }

        do {
            // Try listing models to verify key
            guard let url = URL(string: "\(baseURL)/models") else {
                isConnected = false
                return
            }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                isConnected = false
                models = []
                return
            }

            // Parse model list
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let modelEntries = json["data"] as? [[String: Any]] {
                let chatModels = modelEntries
                    .compactMap { $0["id"] as? String }
                    .filter { id in
                        // Only show chat-capable models
                        id.contains("gpt") || id.contains("o1") || id.contains("o3") || id.contains("o4")
                    }
                    .sorted()

                self.models = chatModels.map { modelId in
                    ProviderModel(
                        providerId: providerId,
                        modelId: modelId,
                        displayName: Self.friendlyName(for: modelId),
                        contextWindow: Self.contextWindow(for: modelId),
                        isLocal: false
                    )
                }
            }

            isConnected = true
        } catch {
            isConnected = false
            models = []
        }
    }

    // MARK: - Chat (Streaming)

    func chat(
        model: String,
        messages: [ChatMessage],
        onToken: @escaping (String) -> Void
    ) async throws -> ChatResult {
        guard !apiKey.isEmpty else { throw LLMProviderError.invalidAPIKey }

        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw LLMProviderError.networkError("Invalid base URL")
        }

        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "stream": true,
            "stream_options": ["include_usage": true]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let startTime = CFAbsoluteTimeGetCurrent()
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200: break
            case 401: throw LLMProviderError.invalidAPIKey
            case 429: throw LLMProviderError.rateLimited
            default:
                throw LLMProviderError.serverError(http.statusCode, "OpenAI returned \(http.statusCode)")
            }
        }

        var fullContent = ""
        var totalTokens = 0

        for try await line in bytes.lines {
            // SSE format: "data: {...}" or "data: [DONE]"
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }

            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            // Extract streaming delta
            if let choices = json["choices"] as? [[String: Any]],
               let delta = choices.first?["delta"] as? [String: Any],
               let content = delta["content"] as? String {
                fullContent += content
                onToken(content)
            }

            // Extract usage from final chunk (stream_options.include_usage)
            if let usage = json["usage"] as? [String: Any] {
                totalTokens = usage["completion_tokens"] as? Int ?? 0
            }
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

        return ChatResult(
            content: fullContent,
            tokenCount: totalTokens,
            durationMs: elapsed,
            model: model,
            providerId: providerId
        )
    }

    // MARK: - Persistence

    private func persistAPIKey() {
        UserDefaults.standard.set(apiKey, forKey: apiKeyKey)
    }

    // MARK: - Friendly Names

    private static func friendlyName(for modelId: String) -> String {
        let map: [String: String] = [
            "gpt-4o": "GPT-4o",
            "gpt-4o-mini": "GPT-4o Mini",
            "gpt-4-turbo": "GPT-4 Turbo",
            "gpt-4": "GPT-4",
            "gpt-3.5-turbo": "GPT-3.5 Turbo",
            "o1": "o1",
            "o1-mini": "o1 Mini",
            "o1-preview": "o1 Preview",
            "o3-mini": "o3 Mini",
        ]
        return map[modelId] ?? modelId
    }

    private static func contextWindow(for modelId: String) -> Int {
        if modelId.contains("gpt-4o") { return 128_000 }
        if modelId.contains("gpt-4-turbo") { return 128_000 }
        if modelId.contains("gpt-4") { return 8_192 }
        if modelId.contains("gpt-3.5") { return 16_385 }
        if modelId.contains("o1") || modelId.contains("o3") { return 128_000 }
        return 4_096
    }
}
