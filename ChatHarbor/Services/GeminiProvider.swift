import Foundation

// MARK: - Google Gemini Provider
//
// Connects to Google's Gemini API (generativelanguage.googleapis.com).
// Supports streaming chat with the Gemini model family.
// API key stored in macOS Keychain.

@MainActor
final class GeminiProvider: LLMProvider {

    // MARK: - LLMProvider

    let providerId = "google"
    let displayName = "Google Gemini"
    let iconName = "diamond"

    var isConnected: Bool = false
    var models: [ProviderModel] = []
    var connectionError: String?

    // MARK: - Config

    var apiKey: String {
        didSet { persistAPIKey() }
    }

    private let keychainKey = "chatharbor.gemini.apiKey"
    private let legacyUserDefaultsKey = "geminiApiKey"
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta"

    // MARK: - Static Model Catalog
    //
    // Gemini's /models endpoint returns many non-chat variants.
    // Using a curated catalog ensures we show only the relevant ones.

    private let modelCatalog: [(id: String, name: String, context: Int)] = [
        // Latest generation
        ("gemini-2.5-pro",          "Gemini 2.5 Pro",           1_048_576),
        ("gemini-2.5-flash",        "Gemini 2.5 Flash",         1_048_576),
        // Previous generation
        ("gemini-2.0-flash",        "Gemini 2.0 Flash",         1_048_576),
        ("gemini-2.0-flash-lite",   "Gemini 2.0 Flash Lite",    1_048_576),
    ]

    // MARK: - Init

    init() {
        // Load from Keychain (migrate from UserDefaults if needed)
        KeychainHelper.migrateFromUserDefaults(
            userDefaultsKey: legacyUserDefaultsKey,
            keychainKey: keychainKey
        )
        self.apiKey = KeychainHelper.load(forKey: keychainKey) ?? ""
    }

    // MARK: - Connect

    func connect() async {
        guard !apiKey.isEmpty else {
            isConnected = false
            models = []
            connectionError = nil
            return
        }

        // Test connection with a minimal request to the first catalog model
        let testModel = modelCatalog[0].id
        let url = URL(string: "\(baseURL)/models/\(testModel):generateContent?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": "hi"]]]
            ],
            "generationConfig": ["maxOutputTokens": 1]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                connectionError = "Invalid response from Gemini"
                return
            }

            switch http.statusCode {
            case 200:
                // Success — populate models from catalog
                self.models = modelCatalog.map { entry in
                    ProviderModel(
                        providerId: providerId,
                        modelId: entry.id,
                        displayName: entry.name,
                        contextWindow: entry.context,
                        isLocal: false
                    )
                }
                isConnected = true
                connectionError = nil

            case 400:
                // API key valid but request issue — still connected
                let errorMsg = parseErrorMessage(from: data)
                if errorMsg.contains("API_KEY_INVALID") || errorMsg.contains("API key not valid") {
                    connectionError = "Invalid API key"
                    isConnected = false
                } else {
                    // Key works, request format issue is fine for a test
                    self.models = modelCatalog.map { entry in
                        ProviderModel(
                            providerId: providerId,
                            modelId: entry.id,
                            displayName: entry.name,
                            contextWindow: entry.context,
                            isLocal: false
                        )
                    }
                    isConnected = true
                    connectionError = nil
                }

            case 401, 403:
                connectionError = "Invalid or unauthorized API key"
                isConnected = false

            case 429:
                // Rate limited but key is valid
                self.models = modelCatalog.map { entry in
                    ProviderModel(
                        providerId: providerId,
                        modelId: entry.id,
                        displayName: entry.name,
                        contextWindow: entry.context,
                        isLocal: false
                    )
                }
                isConnected = true
                connectionError = nil

            default:
                connectionError = "Gemini returned HTTP \(http.statusCode)"
                isConnected = false
            }
        } catch {
            connectionError = "Connection failed: \(error.localizedDescription)"
            isConnected = false
        }
    }

    // MARK: - Chat (Streaming)

    func chat(
        model: String,
        messages: [ChatMessage],
        parameters: ChatParameters,
        onToken: @escaping (String) -> Void
    ) async throws -> ChatResult {
        guard isConnected else { throw LLMProviderError.notConnected }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Build Gemini message format
        var contents: [[String: Any]] = []
        var systemInstruction: [String: Any]? = nil

        for message in messages {
            switch message.role {
            case .system:
                // Gemini uses a separate systemInstruction field
                systemInstruction = [
                    "parts": [["text": message.content]]
                ]

            case .user:
                contents.append([
                    "role": "user",
                    "parts": [["text": message.content]]
                ])

            case .assistant:
                contents.append([
                    "role": "model",
                    "parts": [["text": message.content]]
                ])
            }
        }

        // Build generation config
        var genConfig: [String: Any] = [:]
        if let temp = parameters.temperature { genConfig["temperature"] = temp }
        if let maxTokens = parameters.maxTokens { genConfig["maxOutputTokens"] = maxTokens }
        if let topP = parameters.topP { genConfig["topP"] = topP }

        // Build request body
        var body: [String: Any] = ["contents": contents]
        if let sys = systemInstruction { body["systemInstruction"] = sys }
        if !genConfig.isEmpty { body["generationConfig"] = genConfig }

        // Use streaming endpoint
        let url = URL(string: "\(baseURL)/models/\(model):streamGenerateContent?alt=sse&key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw LLMProviderError.networkError("Invalid response")
        }

        guard http.statusCode == 200 else {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
            }
            let errorMsg = parseErrorMessage(from: errorBody.data(using: .utf8) ?? Data())

            switch http.statusCode {
            case 401, 403: throw LLMProviderError.invalidAPIKey
            case 429: throw LLMProviderError.rateLimited
            case 404: throw LLMProviderError.modelNotFound(model)
            default: throw LLMProviderError.serverError(http.statusCode, errorMsg)
            }
        }

        // Parse SSE stream
        var fullContent = ""
        var inputTokens = 0
        var outputTokens = 0

        for try await line in bytes.lines {
            // Gemini SSE: "data: {...}" lines
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))

            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            // Extract text from candidates
            if let candidates = json["candidates"] as? [[String: Any]],
               let content = candidates.first?["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]] {
                for part in parts {
                    if let text = part["text"] as? String {
                        fullContent += text
                        onToken(text)
                    }
                }
            }

            // Extract usage metadata
            if let usageMetadata = json["usageMetadata"] as? [String: Any] {
                if let promptTokens = usageMetadata["promptTokenCount"] as? Int {
                    inputTokens = promptTokens
                }
                if let candidateTokens = usageMetadata["candidatesTokenCount"] as? Int {
                    outputTokens = candidateTokens
                }
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

    // MARK: - Private

    private func persistAPIKey() {
        if apiKey.isEmpty {
            KeychainHelper.delete(forKey: keychainKey)
        } else {
            KeychainHelper.save(apiKey, forKey: keychainKey)
        }
    }

    private func parseErrorMessage(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return String(data: data, encoding: .utf8) ?? "Unknown error"
    }
}
