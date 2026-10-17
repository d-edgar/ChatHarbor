import Foundation

@main
struct CoreRegression {
    @MainActor static func main() throws {
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

        let markup = "<script>alert(1)</script>\n<img src='https://example.invalid/track'>\n# A & B"
        let html = BrainstormReport.html(markup, title: "</title><script>bad()</script>")
        precondition(!html.contains("<script>") && !html.contains("<img"))
        precondition(html.contains("&lt;script&gt;") && html.contains("<h1>A &amp; B</h1>"))
        precondition(html.contains("default-src 'none'"))
        precondition(UsageFormatting.cost(nil) == "Cost unavailable")
        precondition(UsageFormatting.cost(0).contains("$0"))
        precondition(UsageFormatting.cost(0.00123).contains("0.00123"))
        print("PASS: credential migration, endpoint routing, credential lifecycle, HTML escaping, and cost labels")
    }
}
