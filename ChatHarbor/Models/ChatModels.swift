import Foundation
import SwiftData

// MARK: - Conversation

@Model
final class Conversation {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var modelId: String
    var systemPrompt: String
    /// If this conversation was forked, the ID of the source conversation
    var forkedFromId: UUID?
    /// The message ID at which the fork occurred
    var forkedAtMessageId: UUID?

    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message]

    init(
        title: String = "New Conversation",
        modelId: String = "",
        systemPrompt: String = "",
        forkedFromId: UUID? = nil,
        forkedAtMessageId: UUID? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.modelId = modelId
        self.systemPrompt = systemPrompt
        self.forkedFromId = forkedFromId
        self.forkedAtMessageId = forkedAtMessageId
        self.messages = []
    }

    /// Sorted messages by creation date
    var sortedMessages: [Message] {
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

    /// Whether this conversation was forked from another
    var isForked: Bool {
        forkedFromId != nil
    }
}

// MARK: - Message

@Model
final class Message {
    var id: UUID
    var role: MessageRole
    var content: String
    var createdAt: Date
    var isStreaming: Bool
    var tokenCount: Int?
    var durationMs: Double?
    /// Which model produced this response (for multi-model compare)
    var modelUsed: String?

    var conversation: Conversation?

    init(
        role: MessageRole,
        content: String,
        isStreaming: Bool = false,
        modelUsed: String? = nil
    ) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.createdAt = Date()
        self.isStreaming = isStreaming
        self.modelUsed = modelUsed
    }
}

// MARK: - Message Role

enum MessageRole: String, Codable {
    case system
    case user
    case assistant
}

// MARK: - LLM Model Info

/// Represents a locally available model from Ollama
struct LLMModel: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let size: Int64
    let parameterSize: String
    let quantizationLevel: String
    let modifiedAt: Date
    let family: String
    let digest: String

    /// Human-readable file size
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    /// Short display name (strips tag if it's ":latest")
    var displayName: String {
        if name.hasSuffix(":latest") {
            return String(name.dropLast(7))
        }
        return name
    }
}

// MARK: - Pull Progress

struct PullProgress: Identifiable {
    let id = UUID()
    let modelName: String
    var status: String
    var completed: Int64
    var total: Int64

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}

// MARK: - Prompt Template

struct PromptTemplate: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var systemPrompt: String
    var icon: String
    var isBuiltIn: Bool

    init(
        name: String,
        systemPrompt: String,
        icon: String = "text.bubble",
        isBuiltIn: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.systemPrompt = systemPrompt
        self.icon = icon
        self.isBuiltIn = isBuiltIn
    }
}

// MARK: - Built-in Prompt Templates

enum PromptLibrary {
    static let builtIn: [PromptTemplate] = [
        PromptTemplate(
            name: "Default",
            systemPrompt: "",
            icon: "bubble.left",
            isBuiltIn: true
        ),
        PromptTemplate(
            name: "Code Assistant",
            systemPrompt: "You are an expert software engineer. Write clean, well-documented code. Explain your reasoning. When showing code, use appropriate language-specific idioms and best practices. If the user's request is ambiguous, ask clarifying questions before writing code.",
            icon: "chevron.left.forwardslash.chevron.right",
            isBuiltIn: true
        ),
        PromptTemplate(
            name: "Writing Editor",
            systemPrompt: "You are a skilled editor and writing coach. Help improve clarity, flow, and impact. Preserve the author's voice while suggesting improvements. Be specific about what works and what could be better. When editing, show your changes clearly.",
            icon: "pencil.line",
            isBuiltIn: true
        ),
        PromptTemplate(
            name: "Research Analyst",
            systemPrompt: "You are a thorough research analyst. Break down complex topics into clear explanations. Cite your reasoning, acknowledge uncertainty, and present multiple perspectives where relevant. Distinguish between established facts and your analysis.",
            icon: "magnifyingglass",
            isBuiltIn: true
        ),
        PromptTemplate(
            name: "Socratic Tutor",
            systemPrompt: "You are a Socratic tutor. Instead of giving direct answers, guide the learner through questions that help them discover the answer themselves. Adapt to their level of understanding. Celebrate progress and gently redirect misconceptions.",
            icon: "lightbulb",
            isBuiltIn: true
        ),
        PromptTemplate(
            name: "Concise",
            systemPrompt: "Be extremely concise. Answer in as few words as possible while remaining accurate and helpful. No preamble, no filler, no unnecessary explanation. If a one-word answer suffices, give one word.",
            icon: "arrow.down.right.and.arrow.up.left",
            isBuiltIn: true
        ),
        PromptTemplate(
            name: "Creative Writer",
            systemPrompt: "You are a creative writing partner. Help brainstorm ideas, develop characters, build worlds, and craft compelling narratives. Match the tone and genre the user is going for. Be imaginative and push creative boundaries while respecting the user's vision.",
            icon: "sparkles",
            isBuiltIn: true
        ),
        PromptTemplate(
            name: "Devil's Advocate",
            systemPrompt: "You are a thoughtful devil's advocate. Challenge assumptions, find weaknesses in arguments, and present counterpoints. Be respectful but rigorous. Your goal is to help the user stress-test their thinking, not to be contrarian for its own sake.",
            icon: "exclamationmark.triangle",
            isBuiltIn: true
        ),
    ]
}

// MARK: - Compare Session

/// Tracks a multi-model comparison (same prompt sent to N models)
struct CompareSlot: Identifiable {
    let id = UUID()
    let modelName: String
    var content: String = ""
    var isStreaming: Bool = true
    var tokenCount: Int?
    var durationMs: Double?
    var error: String?

    var displayName: String {
        if modelName.hasSuffix(":latest") {
            return String(modelName.dropLast(7))
        }
        return modelName
    }

    var tokensPerSecond: Double? {
        guard let tokens = tokenCount, let ms = durationMs,
              tokens > 0, ms > 0 else { return nil }
        return Double(tokens) / (ms / 1000.0)
    }
}
