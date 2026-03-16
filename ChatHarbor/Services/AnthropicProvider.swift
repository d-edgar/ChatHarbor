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
    let iconName = "sun.max.fill"  // Starburst — closest SF Symbol to Anthropic's logo

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
    // so we maintain the catalog here. The first entry is used for
    // connection tests, so keep it set to the most reliable/available model.
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

        // Verify key with a minimal request — try each model in the catalog
        // until one succeeds, since some models may not be available on all accounts.
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            isConnected = false
            connectionError = "Invalid API URL"
            return
        }

        // Models to try for the connection test, in order of preference
        let testModels = modelCatalog.map { $0.id }

        for (index, testModel) in testModels.enumerated() {
            do {
                let body: [String: Any] = [
                    "model": testModel,
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
                var apiErrorType: String?
                if http.statusCode != 200 && http.statusCode != 429 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let error = json["error"] as? [String: Any] {
                        apiErrorMessage = error["message"] as? String
                        apiErrorType = error["type"] as? String
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
                    return

                case 401:
                    isConnected = false
                    models = []
                    connectionError = "Invalid API key"
                    return

                case 400:
                    // Check if this is a model-not-found error — try the next model
                    let isModelError = apiErrorType == "not_found_error"
                        || (apiErrorMessage?.lowercased().contains("model") ?? false)
                    if isModelError && index < testModels.count - 1 {
                        continue // Try next model
                    }
                    // Not a model error, or we've exhausted all models
                    isConnected = false
                    models = []
                    connectionError = apiErrorMessage ?? "Bad request — check billing at console.anthropic.com"
                    return

                case 403:
                    isConnected = false
                    models = []
                    connectionError = apiErrorMessage ?? "Access denied — check API key permissions"
                    return

                case 404:
                    // Model not found — try the next model in the catalog
                    if index < testModels.count - 1 {
                        continue
                    }
                    isConnected = false
                    models = []
                    connectionError = "No models available for this API key"
                    return

                default:
                    isConnected = false
                    models = []
                    connectionError = apiErrorMessage ?? "Unexpected response (\(http.statusCode))"
                    return
                }
            } catch {
                isConnected = false
                models = []
                connectionError = error.localizedDescription
                return
            }
        }
    }

    // MARK: - Chat (Streaming)

    func chat(
        model: String,
        messages: [ChatMessage],
        parameters: ChatParameters = .empty,
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
            "max_tokens": parameters.maxTokens ?? 4096,
            "stream": true
        ]

        if let system = systemPrompt {
            body["system"] = system
        }

        // Transparent: only send parameters the user explicitly set
        if let temp = parameters.temperature { body["temperature"] = temp }
        if let topP = parameters.topP { body["top_p"] = topP }

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
        var inputTokens = 0
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
            case "message_start":
                // Initial usage contains input token count
                if let message = json["message"] as? [String: Any],
                   let usage = message["usage"] as? [String: Any] {
                    inputTokens = usage["input_tokens"] as? Int ?? 0
                }

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
            inputTokenCount: inputTokens,
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
