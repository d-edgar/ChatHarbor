import Foundation
import SwiftData

// MARK: - Ship
//
// A Ship is a self-contained AI workspace — a configured persona with its own
// model, personality, knowledge base, and conversation history. Ships live in
// the Harbor and can be used anywhere a model can be selected (chat, brainstorm,
// compare, fork). Think of it as "ChatGPT Projects" but provider-agnostic and
// with full knowledge context support.

@Model
final class Ship {
    var id: UUID = UUID()
    var name: String = "New Ship"
    var icon: String = "sailboat"           // SF Symbol name
    var colorHex: String = "#3B82F6"        // Accent color (hex)
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // MARK: - Engine (model + parameters)

    /// Qualified model ID (e.g., "anthropic:claude-sonnet-4-6", "ollama:llama3")
    var modelId: String = ""
    /// Locked parameter overrides — nil = use model defaults
    var temperature: Double?
    var maxTokens: Int?
    var topP: Double?
    var frequencyPenalty: Double?
    var presencePenalty: Double?

    // MARK: - Personality

    /// System prompt that defines the Ship's behavior, tone, and expertise
    var systemPrompt: String = ""
    /// Short description shown in the Harbor grid and model picker
    var tagline: String = ""

    // MARK: - Heading (conversation rules)

    /// Topics or domains this Ship focuses on (guidance text)
    var focusTopics: String = ""
    /// Response format instructions (e.g., "Always use bullet points", "Respond in JSON")
    var responseFormat: String = ""

    // MARK: - Cargo (knowledge context)

    /// Direct text knowledge — pasted by the user
    var knowledgeText: String = ""
    /// Serialized array of CargoItem (URLs and files with their scraped/parsed content)
    var cargoItemsData: Data?

    // MARK: - Conversations

    @Relationship(deleteRule: .cascade, inverse: \ShipConversation.ship)
    var conversations: [ShipConversation] = []

    // MARK: - Init

    init(
        name: String = "New Ship",
        modelId: String = "",
        systemPrompt: String = "",
        icon: String = "sailboat",
        colorHex: String = "#3B82F6"
    ) {
        self.id = UUID()
        self.name = name
        self.modelId = modelId
        self.systemPrompt = systemPrompt
        self.icon = icon
        self.colorHex = colorHex
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: - Computed

    /// Build ChatParameters from this Ship's overrides
    var chatParameters: ChatParameters {
        ChatParameters(
            temperature: temperature,
            maxTokens: maxTokens,
            topP: topP,
            frequencyPenalty: frequencyPenalty,
            presencePenalty: presencePenalty
        )
    }

    /// Cargo items decoded from the serialized data
    var cargoItems: [CargoItem] {
        get {
            guard let data = cargoItemsData else { return [] }
            return (try? JSONDecoder().decode([CargoItem].self, from: data)) ?? []
        }
        set {
            cargoItemsData = try? JSONEncoder().encode(newValue)
        }
    }

    /// The full system prompt including knowledge context.
    /// This is what actually gets sent to the model.
    var resolvedSystemPrompt: String {
        var parts: [String] = []

        // Core personality
        if !systemPrompt.isEmpty {
            parts.append(systemPrompt)
        }

        // Focus and format rules
        if !focusTopics.isEmpty {
            parts.append("## Focus Areas\n\(focusTopics)")
        }
        if !responseFormat.isEmpty {
            parts.append("## Response Format\n\(responseFormat)")
        }

        // Knowledge context (Cargo)
        let knowledgeContext = buildKnowledgeContext()
        if !knowledgeContext.isEmpty {
            parts.append("## Reference Knowledge\n\nUse the following information as context when answering. Reference it when relevant but do not repeat it verbatim unless asked.\n\n\(knowledgeContext)")
        }

        return parts.joined(separator: "\n\n")
    }

    /// Approximate token count of the full resolved system prompt (rough estimate: 1 token per 4 chars)
    var estimatedContextTokens: Int {
        resolvedSystemPrompt.count / 4
    }

    /// Sorted conversations by most recent activity
    var sortedConversations: [ShipConversation] {
        conversations.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Private

    private func buildKnowledgeContext() -> String {
        var sections: [String] = []

        // Direct text knowledge
        if !knowledgeText.isEmpty {
            sections.append(knowledgeText)
        }

        // Cargo items (URLs and files)
        for item in cargoItems where !item.content.isEmpty {
            switch item.sourceType {
            case .url:
                sections.append("### Source: \(item.title)\nURL: \(item.source)\n\n\(item.content)")
            case .file:
                sections.append("### Document: \(item.title)\n\n\(item.content)")
            case .text:
                sections.append("### \(item.title)\n\n\(item.content)")
            }
        }

        return sections.joined(separator: "\n\n---\n\n")
    }
}

// MARK: - Cargo Item
//
// A piece of knowledge loaded into a Ship — can be from a URL (scraped),
// a file (parsed), or direct text.

struct CargoItem: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String
    var source: String          // URL string, file path, or descriptive label
    var sourceType: CargoSourceType
    var content: String         // The actual text content (scraped/parsed/pasted)
    var fetchedAt: Date?        // When the content was last fetched (for URLs)
    var sizeBytes: Int?         // Original file size for display

    enum CargoSourceType: String, Codable {
        case url
        case file
        case text
    }

    /// Approximate token count (1 token per 4 chars)
    var estimatedTokens: Int {
        content.count / 4
    }
}

// MARK: - Ship Conversation
//
// A conversation that happens inside a Ship. Similar to a regular Conversation
// but linked to a Ship and inherits its configuration.

@Model
final class ShipConversation {
    var id: UUID = UUID()
    var title: String = "New Conversation"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var ship: Ship?

    @Relationship(deleteRule: .cascade, inverse: \ShipMessage.conversation)
    var messages: [ShipMessage] = []

    init(title: String = "New Conversation") {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Sorted messages by creation date
    var sortedMessages: [ShipMessage] {
        messages.sorted { $0.createdAt < $1.createdAt }
    }

    /// Generate a title from the first user message
    var autoTitle: String {
        if let firstUserMessage = sortedMessages.first(where: { $0.role == .user }) {
            let text = firstUserMessage.content
            let trimmed = text.prefix(60)
            return trimmed.count < text.count ? "\(trimmed)…" : String(trimmed)
        }
        return "New Conversation"
    }
}

// MARK: - Ship Message

@Model
final class ShipMessage {
    var id: UUID = UUID()
    var role: MessageRole = MessageRole.user
    var content: String = ""
    var createdAt: Date = Date()
    /// Token and performance tracking
    var tokenCount: Int?
    var inputTokenCount: Int?
    var durationMs: Double?
    var modelUsed: String?

    var conversation: ShipConversation?

    init(role: MessageRole, content: String, modelUsed: String? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.createdAt = Date()
        self.modelUsed = modelUsed
    }
}

// MARK: - Ship Icon Options
//
// Curated set of SF Symbols that work well as Ship icons.

enum ShipIconOptions {
    static let icons: [(symbol: String, label: String)] = [
        ("sailboat", "Sailboat"),
        ("sailboat.fill", "Sailboat (filled)"),
        ("ferry", "Ferry"),
        ("ferry.fill", "Ferry (filled)"),
        ("scope", "Scope"),
        ("binoculars", "Binoculars"),
        ("map", "Map"),
        ("globe", "Globe"),
        ("compass.drawing", "Compass"),
        ("flag", "Flag"),
        ("star", "Star"),
        ("bolt", "Bolt"),
        ("brain", "Brain"),
        ("brain.head.profile", "Brain Profile"),
        ("doc.text.magnifyingglass", "Search Doc"),
        ("book", "Book"),
        ("hammer", "Hammer"),
        ("wrench.and.screwdriver", "Tools"),
        ("theatermasks", "Theater"),
        ("paintpalette", "Palette"),
        ("music.note", "Music"),
        ("stethoscope", "Medical"),
        ("banknote", "Finance"),
        ("chart.line.uptrend.xyaxis", "Analytics"),
        ("cpu", "CPU"),
        ("terminal", "Terminal"),
        ("shield", "Shield"),
        ("lightbulb", "Lightbulb"),
        ("graduationcap", "Education"),
        ("briefcase", "Business"),
    ]

    static let colors: [(hex: String, label: String)] = [
        ("#3B82F6", "Blue"),
        ("#8B5CF6", "Purple"),
        ("#EC4899", "Pink"),
        ("#EF4444", "Red"),
        ("#F97316", "Orange"),
        ("#EAB308", "Yellow"),
        ("#22C55E", "Green"),
        ("#14B8A6", "Teal"),
        ("#06B6D4", "Cyan"),
        ("#64748B", "Slate"),
    ]
}
