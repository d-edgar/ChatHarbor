import Foundation
import Combine

// MARK: - Anthropic Provider
//
// Connects to Anthropic's /v1/messages endpoint with streaming.
// Anthropic uses a slightly different API shape than OpenAI — system
// prompt is a top-level field, not a message role, and streaming uses
// server-sent events with content_block_delta events.

@MainActor
final class AnthropicProvider: ObservableObject, LLMProvider {

    let providerId = "anthropic"
    let displayName = "Anthropic"
    let iconName = "sparkle"

    @Published var isConnected: Bool = false
    @Published var models: [ProviderModel] = []
    @Published var apiKey: String = "" {
        didSet { persistAPIKey() }
    }

    private let apiKeyKey = "chatharbor.anthropic.apiKey"
    private let apiVersion = "2023-06-01"

    // Claude models — Anthropic doesn't have a list endpoint,
    // so we maintain the catalog here.
    private let modelCatalog: [(id: String, name: String, context: Int)] = [
        ("claude-sonnet-4-20250514", "Claude Sonnet 4", 200_000),
        ("claude-opus-4-20250514", "Claude Opus 4", 200_000),
        ("claude-haiku-4-20250514", "Claude Haiku 4", 200_000),
        ("claude-3-5-sonnet-20241022", "Claude 3.5 Sonnet", 200_000),
        ("claude-3-5-haiku-20241022", "Claude 3.5 Haiku", 200_000),
        ("claude-3-opus-20240229", "Claude 3 Opus", 200_000),
    ]

    init() {
        if let saved = UserDefaults.standard.string(forKey: apiKeyKey) {
            self.apiKey = saved
        }
    }

    // MARK: - Connect

    func connect() async {
        guard !apiKey.isEmpty else {
            isConnected = false
            models = []
            return
        }

        // Verify key with a minimal request
        do {
            guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
                isConnected = false
                return
            }

            // Send a tiny request to verify the key works
            let body: [String: Any] = [
                "model": "claude-3-5-haiku-20241022",
                "max_tokens": 1,
                "messages": [["role": "user", "content": "hi"]]
            ]

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (_, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse,
               http.statusCode == 200 || http.statusCode == 429 {
                // 429 means the key is valid but rate-limited — still connected
                isConnected = true
                models = modelCatalog.map { entry in
                    ProviderModel(
                        providerId: providerId,
                        modelId: entry.id,
                        displayName: entry.name,
                        contextWindow: entry.context,
                        isLocal: false
                    )
                }
            } else if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                isConnected = false
                models = []
            } else {
                // Some other status — assume key works, populate models
                isConnected = true
                models = modelCatalog.map { entry in
                    ProviderModel(
                        providerId: providerId,
                        modelId: entry.id,
                        displayName: entry.name,
                        contextWindow: entry.context,
                        isLocal: false
                    )
                }
            }
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

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw LLMProviderError.networkError("Invalid URL")
        }

        // Anthropic: system prompt is top-level, not in messages
        var systemPrompt: String?
        var apiMessages: [[String: String]] = []

        for msg in messages {
            if msg.role == .system {
                systemPrompt = msg.content
            } else {
                apiMessages.append([
                    "role": msg.role.rawValue,
                    "content": msg.content
                ])
            }
        }

        var body: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "max_tokens": 4096,
            "stream": true
        ]

        if let system = systemPrompt {
            body["system"] = system
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
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
                throw LLMProviderError.serverError(http.statusCode, "Anthropic returned \(http.statusCode)")
            }
        }

        var fullContent = ""
        var outputTokens = 0

        for try await line in bytes.lines {
            // Anthropic SSE: "event: content_block_delta" then "data: {...}"
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))

            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let eventType = json["type"] as? String ?? ""

            switch eventType {
            case "content_block_delta":
                if let delta = json["delta"] as? [String: Any],
                   let text = delta["text"] as? String {
                    fullContent += text
                    onToken(text)
                }

            case "message_delta":
                // Final usage stats
                if let usage = json["usage"] as? [String: Any] {
                    outputTokens = usage["output_tokens"] as? Int ?? 0
                }

            case "error":
                let errorMsg = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
                throw LLMProviderError.streamingError(errorMsg)

            default:
                break
            }
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

        return ChatResult(
            content: fullContent,
            tokenCount: outputTokens,
            durationMs: elapsed,
            model: model,
            providerId: providerId
        )
    }

    // MARK: - Persistence

    private func persistAPIKey() {
        UserDefaults.standard.set(apiKey, forKey: apiKeyKey)
    }
}
