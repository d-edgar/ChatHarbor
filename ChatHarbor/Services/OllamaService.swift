import Foundation
import Combine

// MARK: - Ollama Service
//
// Communicates with a local Ollama server (default: http://localhost:11434).
// Supports listing models, chatting with streaming, pulling, and deleting models.

@MainActor
final class OllamaService: ObservableObject {

    static let shared = OllamaService()

    @Published var baseURL: URL = URL(string: "http://localhost:11434")!
    @Published var isConnected: Bool = false
    @Published var availableModels: [LLMModel] = []
    @Published var pullProgress: PullProgress?

    private var streamTask: Task<Void, Never>?

    private init() {}

    // MARK: - Connection Check

    /// Ping the Ollama server to check if it's running
    func checkConnection() async {
        do {
            let url = baseURL.appendingPathComponent("api/tags")
            let (_, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                isConnected = true
                await refreshModels()
            } else {
                isConnected = false
            }
        } catch {
            isConnected = false
        }
    }

    // MARK: - List Models

    /// Fetch all locally available models from Ollama
    func refreshModels() async {
        do {
            let url = baseURL.appendingPathComponent("api/tags")
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)

            availableModels = response.models.map { model in
                LLMModel(
                    name: model.name,
                    size: model.size,
                    parameterSize: model.details?.parameterSize ?? "",
                    quantizationLevel: model.details?.quantizationLevel ?? "",
                    modifiedAt: Self.parseDate(model.modifiedAt) ?? Date(),
                    family: model.details?.family ?? "",
                    digest: model.digest ?? ""
                )
            }
            .sorted { $0.name < $1.name }
        } catch {
            print("Failed to refresh models: \(error.localizedDescription)")
        }
    }

    // MARK: - Chat (Streaming)

    /// Send a chat request and stream the response token by token.
    /// Calls `onToken` for each chunk of text received.
    /// Returns the full accumulated response when done.
    @discardableResult
    func chat(
        model: String,
        messages: [(role: String, content: String)],
        onToken: @escaping (String) -> Void
    ) async throws -> ChatCompletionResult {
        let url = baseURL.appendingPathComponent("api/chat")

        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": true
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OllamaError.serverError("Unexpected status code")
        }

        var fullContent = ""
        var totalTokens = 0
        var durationNs: Int64 = 0

        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? String {
                fullContent += content
                onToken(content)
            }

            if let done = json["done"] as? Bool, done {
                totalTokens = json["eval_count"] as? Int ?? 0
                durationNs = json["total_duration"] as? Int64 ?? 0
            }
        }

        return ChatCompletionResult(
            content: fullContent,
            tokenCount: totalTokens,
            durationMs: Double(durationNs) / 1_000_000.0
        )
    }

    /// Cancel any in-progress streaming
    func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
    }

    // MARK: - Pull Model

    /// Pull (download) a model from the Ollama registry.
    /// Updates `pullProgress` as chunks arrive.
    func pullModel(name: String) async throws {
        let url = baseURL.appendingPathComponent("api/pull")

        let body: [String: Any] = [
            "name": name,
            "stream": true
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        pullProgress = PullProgress(modelName: name, status: "Starting…", completed: 0, total: 0)

        let (bytes, _) = try await URLSession.shared.bytes(for: request)

        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let status = json["status"] as? String ?? ""
            let completed = json["completed"] as? Int64 ?? 0
            let total = json["total"] as? Int64 ?? 0

            pullProgress = PullProgress(
                modelName: name,
                status: status,
                completed: completed,
                total: total
            )
        }

        pullProgress = nil
        await refreshModels()
    }

    // MARK: - Delete Model

    /// Delete a locally cached model
    func deleteModel(name: String) async throws {
        let url = baseURL.appendingPathComponent("api/delete")

        let body = ["name": name]

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OllamaError.serverError("Failed to delete model")
        }

        await refreshModels()
    }

    // MARK: - Date Parsing

    private static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}

// MARK: - Response Types

struct ChatCompletionResult {
    let content: String
    let tokenCount: Int
    let durationMs: Double
}

private struct OllamaTagsResponse: Codable {
    let models: [OllamaModelEntry]
}

private struct OllamaModelEntry: Codable {
    let name: String
    let size: Int64
    let digest: String?
    let modifiedAt: String
    let details: OllamaModelDetails?

    enum CodingKeys: String, CodingKey {
        case name, size, digest, details
        case modifiedAt = "modified_at"
    }
}

private struct OllamaModelDetails: Codable {
    let family: String?
    let parameterSize: String?
    let quantizationLevel: String?

    enum CodingKeys: String, CodingKey {
        case family
        case parameterSize = "parameter_size"
        case quantizationLevel = "quantization_level"
    }
}

// MARK: - LLMProvider Conformance

extension OllamaService: LLMProvider {
    var providerId: String { "ollama" }
    var displayName: String { "Ollama" }
    var iconName: String { "desktopcomputer" }

    /// Bridge: convert LLMModel array to ProviderModel array
    var models: [ProviderModel] {
        availableModels.map { model in
            ProviderModel(
                providerId: "ollama",
                modelId: model.name,
                displayName: model.displayName,
                contextWindow: nil,
                isLocal: true
            )
        }
    }

    func connect() async {
        await checkConnection()
    }

    func chat(
        model: String,
        messages: [ChatMessage],
        onToken: @escaping (String) -> Void
    ) async throws -> ChatResult {
        let apiMessages = messages.map { (role: $0.role.rawValue, content: $0.content) }

        let result = try await chat(model: model, messages: apiMessages, onToken: onToken)

        return ChatResult(
            content: result.content,
            tokenCount: result.tokenCount,
            durationMs: result.durationMs,
            model: model,
            providerId: "ollama"
        )
    }
}

// MARK: - Errors

enum OllamaError: LocalizedError {
    case serverError(String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .serverError(let msg): return msg
        case .notConnected: return "Ollama is not running. Start it with `ollama serve`."
        }
    }
}
