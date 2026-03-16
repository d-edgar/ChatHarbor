import Foundation
import Combine

// MARK: - Apple Intelligence Provider
//
// Uses Apple's on-device Foundation Models framework (macOS 26+).
// Completely local, private, and free — no API key, no network,
// no billing. Runs on Apple Silicon via the Neural Engine.
//
// The entire provider is gated behind #available(macOS 26, *)
// so ChatHarbor still compiles and runs on Sonoma/Sequoia —
// Apple Intelligence just won't appear in the model list.

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class AppleIntelligenceProvider: ObservableObject, LLMProvider {

    let providerId = "apple"
    let displayName = "Apple Intelligence"
    // "apple.intelligence" SF Symbol exists on macOS 26+;
    // fall back to "apple.logo" on older systems
    var iconName: String {
        if #available(macOS 26, *) {
            return "apple.intelligence"
        }
        return "apple.logo"
    }

    @Published var isConnected: Bool = false
    @Published var models: [ProviderModel] = []
    @Published var availabilityDetail: String = ""
    @Published var isEnabled: Bool = UserDefaults.standard.bool(forKey: "chatharbor.apple.enabled") {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "chatharbor.apple.enabled")
            if isEnabled {
                Task { await connect() }
            } else {
                isConnected = false
                models = []
            }
        }
    }

    // MARK: - Connect

    func connect() async {
        guard isEnabled else {
            isConnected = false
            models = []
            return
        }

        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let systemModel = SystemLanguageModel.default
            switch systemModel.availability {
            case .available:
                isConnected = true
                availabilityDetail = "On-device model ready"
                models = [
                    ProviderModel(
                        providerId: providerId,
                        modelId: "apple-intelligence",
                        displayName: "Apple Intelligence",
                        contextWindow: 4096,
                        isLocal: true
                    )
                ]
            case .unavailable(let reason):
                isConnected = false
                models = []
                switch reason {
                case .deviceNotEligible:
                    availabilityDetail = "This Mac doesn't support Apple Intelligence (requires Apple Silicon)"
                case .appleIntelligenceNotEnabled:
                    availabilityDetail = "Enable Apple Intelligence in System Settings → Apple Intelligence & Siri"
                case .modelNotReady:
                    availabilityDetail = "Model is downloading or loading — try again shortly"
                @unknown default:
                    availabilityDetail = "Apple Intelligence is not available"
                }
            @unknown default:
                isConnected = false
                models = []
                availabilityDetail = "Could not determine availability"
            }
        } else {
            isConnected = false
            models = []
            availabilityDetail = "Requires macOS 26 (Tahoe) or later"
        }
        #else
        isConnected = false
        models = []
        availabilityDetail = "Requires macOS 26 (Tahoe) or later"
        #endif
    }

    // MARK: - Chat (Streaming)

    func chat(
        model: String,
        messages: [ChatMessage],
        parameters: ChatParameters = .empty,
        onToken: @escaping (String) -> Void
    ) async throws -> ChatResult {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            return try await chatWithFoundationModels(messages: messages, onToken: onToken)
        }
        #endif
        // Apple Intelligence ignores temperature/maxTokens — on-device model
        // has fixed behavior. Parameters shown in UI for transparency.
        throw LLMProviderError.notConnected
    }

    #if canImport(FoundationModels)
    @available(macOS 26, *)
    private func chatWithFoundationModels(
        messages: [ChatMessage],
        onToken: @escaping (String) -> Void
    ) async throws -> ChatResult {
        // Build the session with system prompt if provided
        var systemInstruction: String?
        var conversationParts: [String] = []

        for msg in messages {
            switch msg.role {
            case .system:
                systemInstruction = msg.content
            case .user:
                conversationParts.append("User: \(msg.content)")
            case .assistant:
                conversationParts.append("Assistant: \(msg.content)")
            }
        }

        let session: LanguageModelSession
        let effectiveInstructions = systemInstruction
            ?? "You are a helpful, friendly assistant. Answer questions clearly and conversationally. If the user greets you, greet them back warmly."
        session = LanguageModelSession(instructions: effectiveInstructions)

        // Foundation Models is single-turn. If there's conversation history,
        // include it as context, but send the last user message cleanly.
        let prompt: String
        if conversationParts.count <= 1 {
            // Single message — send the raw user text without "User:" prefix
            prompt = conversationParts.first.map { String($0.dropFirst("User: ".count)) } ?? ""
        } else {
            // Multi-turn: include history as context for the model
            prompt = conversationParts.joined(separator: "\n")
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        var fullContent = ""

        // Use streaming for progressive output
        let stream = session.streamResponse(to: prompt)
        var previousText = ""

        for try await partial in stream {
            // Foundation Models uses snapshot streaming — each emission
            // is the full text so far, not just the delta
            let currentText = partial.content
            if currentText.count > previousText.count {
                let delta = String(currentText.dropFirst(previousText.count))
                onToken(delta)
            }
            previousText = currentText
        }

        fullContent = previousText
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

        // Estimate token count from content (≈4 chars per token for English).
        // The Foundation Models framework doesn't expose a public token
        // counting API on SystemLanguageModel in the current SDK.
        let estimatedTokens = max(1, fullContent.count / 4)

        return ChatResult(
            content: fullContent,
            tokenCount: estimatedTokens,
            inputTokenCount: 0,
            durationMs: elapsed,
            model: "apple-intelligence",
            providerId: providerId
        )
    }
    #endif
}
