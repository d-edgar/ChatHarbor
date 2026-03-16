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
    @Published var connectionError: String?
    @Published var apiKey: String = "" {
        didSet { persistAPIKey() }
    }

    private let apiKeyKey = "chatharbor.anthropic.apiKey"
    private let apiVersion = "2023-06-01"
    private let betaFeatures = "max-tokens-3-5-sonnet-2024-07-15"

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
        connectionError = nil

        guard !apiKey.isEmpty else {
            isConnected = false
            models = []
            return
        }

        // Verify key with a minimal request
        do {
            guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
                isConnected = false
                connectionError = "Invalid API URL"
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

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                isConnected = false
                connectionError = "Invalid response"
                return
            }

            // Parse error body for non-success responses
            var apiErrorMessage: String?
            if http.statusCode != 200 && http.statusCode != 429 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    apiErrorMessage = message
                }
            }

            switch http.statusCode {
            case 200, 429:
                // 200 = works, 429 = key valid but rate-limited
                isConnected = true
                connectionError = nil
                models = modelCatalog.map { entry in
                    ProviderModel(
                        providerId: providerId,
                        modelId: entry.id,
                        displayName: entry.name,
                        contextWindow: entry.context,
                        isLocal: false
                    )
                }
            case 401:
                isConnected = false
                models = []
                connectionError = "Invalid API key"
            case 400:
                // 400 often means billing issue
                isConnected = false
                models = []
                connectionError = apiErrorMessage ?? "Bad request — check billing at console.anthropic.com"
            case 403:
                isConnected = false
                models = []
                connectionError = apiErrorMessage ?? "Access denied — check API key permissions"
            default:
                // Other status codes — try to show the error
                isConnected = false
                models = []
                connectionError = apiErrorMessage ?? "Unexpected response (\(http.statusCode))"
            }
        } catch {
            isConnected = false
            models = []
            connectionError = error.localizedDescription
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

        // Use data request first to check for errors, then switch to streaming
        // For non-200 responses, we need the full body to get the error message
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            // Collect the error body
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
            }

            // Try to parse Anthropic's error format
            var errorMessage = "Anthropic returned \(http.statusCode)"
            if let data = errorBody.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                errorMessage = message
            }

            switch http.statusCode {
            case 401: throw LLMProviderError.invalidAPIKey
            case 429: throw LLMProviderError.rateLimited
            default:
                throw LLMProviderError.serverError(http.statusCode, errorMessage)
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
