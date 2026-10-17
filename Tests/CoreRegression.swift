import Foundation

@main
struct CoreRegression {
    @MainActor static func main() async throws {
        let suite = "ChatHarborTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let storageKey = "chatharbor.customEndpoints"
        let firstID = UUID()
        let secondID = UUID()
        let legacy = try JSONSerialization.data(withJSONObject: [
            ["id": firstID.uuidString, "name": "Local", "baseURL": "http://localhost:1234/v1", "apiKey": "test-secret"],
            ["id": secondID.uuidString, "name": "Remote", "baseURL": "https://example.invalid/v1", "apiKey": ""]
        ])
        defaults.set(legacy, forKey: storageKey)
        var secrets: [String: String] = [:]
        let failed = CustomEndpointProvider(defaults: defaults, readKey: { secrets[$0] },
                                            saveKey: { _, _ in false }, deleteKey: { _ in false })
        precondition(failed.persistenceError != nil)
        precondition(defaults.data(forKey: storageKey) == legacy, "Failed migration must retain recoverable credentials")
        do {
            _ = try failed.addEndpoint(name: "Blocked", baseURL: "http://localhost:1234", apiKey: "new-key")
            preconditionFailure("Mutation must not overwrite a failed migration")
        } catch {}

        let provider = CustomEndpointProvider(defaults: defaults, readKey: { secrets[$0] },
            saveKey: { value, key in secrets[key] = value; return true },
            deleteKey: { secrets.removeValue(forKey: $0); return true })
        precondition(provider.persistenceError == nil)
        precondition(secrets[CustomEndpointProvider.keychainKey(firstID)] == "test-secret")
        let saved = try JSONSerialization.jsonObject(with: defaults.data(forKey: storageKey)!) as! [[String: Any]]
        precondition(saved.allSatisfy { $0["apiKey"] == nil }, "Metadata must never contain credentials")
        for endpoint in provider.endpoints {
            endpoint.models = [ProviderModel(providerId: "custom", modelId: "\(endpoint.id.uuidString):shared:model",
                displayName: "Shared", contextWindow: nil, isLocal: false)]
        }
        let (chosen, raw) = try provider.resolve(model: "\(secondID.uuidString):shared:model")
        precondition(chosen.id == secondID && raw == "shared:model")
        do {
            _ = try provider.resolve(model: "shared:model")
            preconditionFailure("Ambiguous legacy models must not route to the first endpoint")
        } catch {}
        try provider.removeEndpoint(id: secondID)
        let legacyEndpoint = try provider.resolve(model: "shared:model").0
        precondition(legacyEndpoint.id == firstID)
        let added = try provider.addEndpoint(name: "New", baseURL: "http://localhost:4567/", apiKey: "new-secret")
        precondition(secrets[CustomEndpointProvider.keychainKey(added.id)] == "new-secret")
        try provider.updateEndpoint(id: added.id, apiKey: "replacement")
        precondition(secrets[CustomEndpointProvider.keychainKey(added.id)] == "replacement")
        try provider.removeEndpoint(id: added.id)
        precondition(secrets[CustomEndpointProvider.keychainKey(added.id)] == nil)

        let studio = try provider.addEndpoint(name: "My local models", baseURL: "http://localhost:1234", isLMStudio: true)
        let reloaded = CustomEndpointProvider(defaults: defaults, readKey: { secrets[$0] },
            saveKey: { value, key in secrets[key] = value; return true }, deleteKey: { _ in true })
        precondition(reloaded.endpoints.first { $0.id == studio.id }?.isLMStudio == true,
                     "LM Studio identity must survive renaming and reload")
        precondition(reloaded.endpoints.first { $0.id == firstID }?.isLMStudio == false,
                     "A localhost port alone must not identify LM Studio")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EndpointResponseStub.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        for failure in ["unauthorized", "malformed"] {
            studio.baseURL = "https://endpoint.invalid/success"
            await studio.connect(session: session)
            precondition(studio.isConnected && studio.models.count == 1)
            studio.baseURL = "https://endpoint.invalid/\(failure)"
            await studio.connect(session: session)
            precondition(!studio.isConnected && studio.models.isEmpty,
                         "Failed discovery must clear previously available models")
            precondition(studio.connectionError != nil)
            precondition(!provider.models.contains { $0.modelId.hasPrefix(studio.id.uuidString) })
        }
        print("PASS: HTTP and malformed-response failures clear stale endpoint models")

        let markup = "<script>alert(1)</script>\n<img src='https://example.invalid/track'>\n# A & B"
        let html = BrainstormReport.html(markup, title: "</title><script>bad()</script>")
        precondition(!html.contains("<script>") && !html.contains("<img"))
        precondition(html.contains("&lt;script&gt;") && html.contains("<h1>A &amp; B</h1>"))
        precondition(html.contains("default-src 'none'"))
        precondition(UsageFormatting.cost(nil) == "Cost unavailable")
        precondition(UsageFormatting.cost(0).contains("$0"))
        precondition(UsageFormatting.cost(0.00123).contains("0.00123"))
        let openAI = TokenUsage.openAI([
            "prompt_tokens": 100, "completion_tokens": 40,
            "prompt_tokens_details": ["cached_tokens": 60],
            "completion_tokens_details": ["reasoning_tokens": 25]
        ])
        precondition(openAI.total == 140 && openAI.reasoning == 25 && openAI.cachedInput == 60)
        let claude = TokenUsage.anthropic(["input_tokens": 10, "output_tokens": 20,
            "cache_read_input_tokens": 100, "cache_creation_input_tokens": 30])
        precondition(claude.input == 140 && claude.total == 160)
        let gemini = TokenUsage.gemini(["promptTokenCount": 100, "candidatesTokenCount": 20,
            "thoughtsTokenCount": 40, "cachedContentTokenCount": 80])
        precondition(gemini.output == 60 && gemini.total == 160 && gemini.cachedInput == 80)
        let zero = TokenUsage.openAI(["prompt_tokens": 0, "completion_tokens": 0])
        precondition(zero.total == 0 && zero.label(zero.output) == "0")
        let missing = TokenUsage.openAI([:])
        precondition(missing.total == nil && missing.summary == "— in · — out")
        precondition(TokenUsage.count(-1) == nil && TokenUsage.count(true) == nil && TokenUsage.count(1.5) == nil)
        precondition(TokenUsage.sum([Int.max, 1]) == nil)
        precondition(TokenUsage.combined([openAI, missing]).total == nil, "Missing usage must not become free tokens")
        let estimate = TokenUsage(input: 10, output: 4, isEstimated: true)
        precondition(estimate.summary == "~10 in · ~4 out")
        precondition(TokenUsage.combined([zero, estimate]).isEstimated)
        precondition(TokenUsage.restore(estimate.encoded, input: nil, output: nil) == estimate)
        precondition(TokenUsage.restore(nil, input: 0, output: 4).input == nil)
        precondition(TokenUsage.restore(nil, input: 3, output: 4).isEstimated)
        print("PASS: usage parsing, cache/thinking totals, missing/zero/estimated counts, and safe aggregation")
        print("PASS: credential migration, endpoint routing, credential lifecycle, HTML escaping, and cost labels")
    }
}

private final class EndpointResponseStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let status = url.path.contains("unauthorized") ? 401 : 200
        let body = url.path.contains("malformed") ? "invalid json" : #"{"data":[{"id":"test-model"}]}"#
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status,
            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
