import Foundation
import Combine

// MARK: - Custom Endpoint Provider
//
// Supports multiple user-defined OpenAI-compatible API endpoints.
// This covers LM Studio, LocalAI, Open WebUI, vLLM, text-generation-webui,
// Jan, and any other server exposing an OpenAI-compatible /v1/chat/completions.
// Each endpoint has its own name, base URL, and optional API key.
// Endpoint metadata lives in UserDefaults; credentials live in Keychain.

@MainActor
final class CustomEndpointProvider: ObservableObject, LLMProvider {

    // MARK: - LLMProvider

    let providerId = "custom"
    let displayName = "Custom Endpoints"
    let iconName = "server.rack"

    var isConnected: Bool { !endpoints.isEmpty && endpoints.contains(where: { $0.isConnected }) }
    var models: [ProviderModel] {
        endpoints.flatMap { $0.models }
    }

    // MARK: - Endpoints

    @Published var endpoints: [CustomEndpoint] = []

    @Published private(set) var persistenceError: String?
    private let defaults: UserDefaults
    private let readKey: @MainActor (String) -> String?
    private let saveKey: @MainActor (String, String) -> Bool
    private let deleteKey: @MainActor (String) -> Bool

    private let persistenceKey = "chatharbor.customEndpoints"

    // MARK: - Init

    init(defaults: UserDefaults = .standard,
         readKey: @escaping @MainActor (String) -> String? = KeychainHelper.load,
         saveKey: @escaping @MainActor (String, String) -> Bool = KeychainHelper.save,
         deleteKey: @escaping @MainActor (String) -> Bool = KeychainHelper.delete) {
        self.defaults = defaults
        self.readKey = readKey
        self.saveKey = saveKey
        self.deleteKey = deleteKey
        loadEndpoints()
    }

    // MARK: - Endpoint Management

    func addEndpoint(name: String, baseURL: String, apiKey: String = "", isLMStudio: Bool = false) throws -> CustomEndpoint {
        try checkMigration()
        let endpoint = CustomEndpoint(
            name: name,
            baseURL: normalizeURL(baseURL),
            apiKey: apiKey, isLMStudio: isLMStudio
        )
        try storeKey(apiKey, id: endpoint.id)
        endpoint.onConnectionChange = { [weak self] in self?.objectWillChange.send() }
        endpoints.append(endpoint)
        saveEndpoints()
        return endpoint
    }

    func removeEndpoint(id: UUID) throws {
        try checkMigration()
        try storeKey("", id: id)
        endpoints.removeAll { $0.id == id }
        saveEndpoints()
    }

    func updateEndpoint(id: UUID, name: String? = nil, baseURL: String? = nil, apiKey: String? = nil) throws {
        try checkMigration()
        guard let index = endpoints.firstIndex(where: { $0.id == id }) else { return }
        if let apiKey { try storeKey(apiKey, id: id) }
        if let name = name { endpoints[index].name = name }
        if let baseURL = baseURL { endpoints[index].baseURL = normalizeURL(baseURL) }
        if let apiKey = apiKey { endpoints[index].apiKey = apiKey }
        saveEndpoints()
    }

    // MARK: - Connect

    func connect() async {
        await withTaskGroup(of: Void.self) { group in
            for i in endpoints.indices {
                let endpoint = endpoints[i]
                group.addTask {
                    await endpoint.connect()
                }
            }
        }
    }

    func connectEndpoint(_ id: UUID) async {
        guard let endpoint = endpoints.first(where: { $0.id == id }) else { return }
        await endpoint.connect()
    }

    // MARK: - Chat

    func chat(
        model: String,
        messages: [ChatMessage],
        parameters: ChatParameters,
        onToken: @escaping (String) -> Void
    ) async throws -> ChatResult {
        let (endpoint, rawModel) = try resolve(model: model)
        return try await endpoint.chat(model: rawModel, messages: messages, parameters: parameters, onToken: onToken)
    }

    func resolve(model: String) throws -> (CustomEndpoint, String) {
        let parts = model.split(separator: ":", maxSplits: 1)
        if parts.count == 2, let id = UUID(uuidString: String(parts[0])) {
            guard let endpoint = endpoints.first(where: { $0.id == id }) else {
                throw LLMProviderError.modelNotFound(model)
            }
            return (endpoint, String(parts[1]))
        }
        // Old saved selections are safe only when exactly one endpoint offers the model.
        let matches = endpoints.filter { ep in ep.models.contains { $0.modelId == "\(ep.id.uuidString):\(model)" } }
        guard matches.count == 1, let endpoint = matches.first else {
            throw LLMProviderError.networkError("Select this model again in the model picker; its saved endpoint is missing or ambiguous.")
        }
        return (endpoint, model)
    }

    // MARK: - Persistence

    private func saveEndpoints() {
        let configs = endpoints.map { ep in
            EndpointConfig(
                id: ep.id,
                name: ep.name,
                baseURL: ep.baseURL,
                apiKey: nil,
                isLMStudio: ep.isLMStudio
            )
        }
        if let data = try? JSONEncoder().encode(configs) {
            defaults.set(data, forKey: persistenceKey)
        }
    }

    private func loadEndpoints() {
        guard let data = defaults.data(forKey: persistenceKey),
              let configs = try? JSONDecoder().decode([EndpointConfig].self, from: data) else {
            return
        }
        endpoints = configs.map { config in
            let key = Self.keychainKey(config.id)
            if let legacy = config.apiKey, !legacy.isEmpty, readKey(key) == nil {
                if !saveKey(legacy, key) {
                    persistenceError = "Could not move endpoint credentials to Keychain. Unlock Keychain and restart ChatHarbor. Existing settings have been retained."
                }
            }
            let endpoint = CustomEndpoint(id: config.id, name: config.name, baseURL: config.baseURL,
                                  apiKey: readKey(key) ?? config.apiKey ?? "",
                                  isLMStudio: config.isLMStudio ?? (config.name == "LM Studio"))
            endpoint.onConnectionChange = { [weak self] in self?.objectWillChange.send() }
            return endpoint
        }
        if persistenceError == nil { saveEndpoints() }
    }

    static func keychainKey(_ id: UUID) -> String { "chatharbor.custom.\(id.uuidString).apiKey" }

    private func checkMigration() throws {
        if let persistenceError { throw LLMProviderError.networkError(persistenceError) }
    }

    private func storeKey(_ value: String, id: UUID) throws {
        let key = Self.keychainKey(id)
        let success = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? deleteKey(key) : saveKey(value, key)
        guard success else { throw LLMProviderError.networkError("Could not save endpoint credentials in Keychain. Your endpoint settings were not changed.") }
    }

    private func normalizeURL(_ url: String) -> String {
        var trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove trailing slash
        while trimmed.hasSuffix("/") { trimmed = String(trimmed.dropLast()) }
        // Ensure /v1 suffix if not present
        if !trimmed.hasSuffix("/v1") && !trimmed.contains("/v1/") {
            trimmed += "/v1"
        }
        return trimmed
    }
}

// MARK: - Endpoint Config (Codable for persistence)

private struct EndpointConfig: Codable {
    let id: UUID
    let name: String
    let baseURL: String
    var apiKey: String?
    var isLMStudio: Bool?
}

// MARK: - Custom Endpoint

/// Represents a single OpenAI-compatible API endpoint.
/// Each endpoint discovers its own models and handles its own streaming.
@MainActor
final class CustomEndpoint: Identifiable {
    let id: UUID
    let isLMStudio: Bool
    var onConnectionChange: (() -> Void)?
    var name: String
    var baseURL: String
    var apiKey: String
    var isConnected: Bool = false
    var models: [ProviderModel] = []
    var connectionError: String?

    init(id: UUID = UUID(), name: String, baseURL: String, apiKey: String = "", isLMStudio: Bool = false) {
        self.isLMStudio = isLMStudio
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    // MARK: - Connect (discover models)

    func connect() async {
        defer { onConnectionChange?() }
        let urlString = "\(baseURL)/models"
        guard let url = URL(string: urlString) else {
            connectionError = "Invalid URL: \(urlString)"
            isConnected = false
            models = []
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                connectionError = "Invalid response"
                isConnected = false
                return
            }

            guard http.statusCode == 200 else {
                connectionError = "HTTP \(http.statusCode)"
                isConnected = false
                return
            }

            // Parse OpenAI-format model list
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let modelEntries = json["data"] as? [[String: Any]] {
                let modelIds = modelEntries
                    .compactMap { $0["id"] as? String }
                    .sorted()

                self.models = modelIds.map { modelId in
                    ProviderModel(
                        providerId: "custom",
                        modelId: "\(id.uuidString):\(modelId)",
                        displayName: "\(modelId) (\(name))",
                        contextWindow: nil,
                        isLocal: baseURL.contains("localhost") || baseURL.contains("127.0.0.1")
                    )
                }

                isConnected = true
                connectionError = nil
            } else {
                connectionError = "Could not parse model list"
                isConnected = false
            }
        } catch let error as URLError where error.code == .cannotConnectToHost || error.code == .timedOut {
            connectionError = "Cannot reach \(baseURL)"
            isConnected = false
            models = []
        } catch {
            connectionError = error.localizedDescription
            isConnected = false
            models = []
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

        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw LLMProviderError.networkError("Invalid endpoint URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        // Build message array
        let apiMessages = messages.map { msg -> [String: String] in
            ["role": msg.role.rawValue, "content": msg.content]
        }

        var body: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "stream": true,
            "stream_options": ["include_usage": true]
        ]

        // Optional parameters
        if let temp = parameters.temperature { body["temperature"] = temp }
        if let maxTokens = parameters.maxTokens { body["max_tokens"] = maxTokens }
        if let topP = parameters.topP { body["top_p"] = topP }
        if let freqPenalty = parameters.frequencyPenalty { body["frequency_penalty"] = freqPenalty }
        if let presPenalty = parameters.presencePenalty { body["presence_penalty"] = presPenalty }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw LLMProviderError.networkError("Invalid response from \(name)")
        }

        guard http.statusCode == 200 else {
            var errorBody = ""
            for try await line in bytes.lines { errorBody += line }
            throw LLMProviderError.serverError(http.statusCode, errorBody)
        }

        // Parse SSE stream (OpenAI format)
        var fullContent = ""
        var tokenUsage = TokenUsage()

        for try await line in bytes.lines {
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

            // Extract usage from final chunk
            if let usage = json["usage"] as? [String: Any] {
                tokenUsage = TokenUsage.openAI(usage)
            }
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

        return ChatResult(
            content: fullContent,
            usage: tokenUsage,
            durationMs: elapsed,
            model: model,
            providerId: "custom"
        )
    }
}
