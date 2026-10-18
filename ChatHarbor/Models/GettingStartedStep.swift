import Foundation

enum GettingStartedStep: String, CaseIterable {
    case overview, connect, chat, ships, harbors, data

    static let storageKey = "gettingStartedStep"

    static func restore(from defaults: UserDefaults) -> Self {
        defaults.string(forKey: storageKey).flatMap(Self.init(rawValue:)) ?? .overview
    }

    var index: Int { Self.allCases.firstIndex(of: self)! }
    var previous: Self { Self.allCases[max(0, index - 1)] }
    var next: Self { Self.allCases[min(Self.allCases.count - 1, index + 1)] }

    func canContinue(modelAvailable: Bool, hasUserMessage: Bool) -> Bool {
        switch self {
        case .connect: return modelAvailable
        case .chat: return hasUserMessage
        default: return true
        }
    }

    var title: String {
        switch self {
        case .overview: return "Find your way around"
        case .connect: return "Connect one model"
        case .chat: return "Try your first chat"
        case .ships: return "Reuse instructions with Ships"
        case .harbors: return "Separate work with Harbors"
        case .data: return "Keep control of your data"
        }
    }

    var explanation: String {
        switch self {
        case .overview:
            return "The highlighted areas are your starting points: Chat starts a conversation, Models chooses the AI, Ships holds reusable assistants, and Harbors separates areas of life. The app stays usable during this guide."
        case .connect:
            return "Open model settings and connect a provider. For local use, start Ollama or LM Studio and load a model. This guide waits here while you set up; close Settings to return. Choose an available model below, then continue."
        case .chat:
            return "Open a chat and send a question in the message box. Try: Help me plan my week. You choose what to send; the guide never sends a message for you. Continue after your message appears, or skip this step."
        case .ships:
            return "A Ship is an optional reusable assistant with its own model, instructions, and reference material. Use the + beside Ships to try building a Writing Coach. Save or cancel the builder; this guide keeps your place. You can also continue without creating one."
        case .harbors:
            return "Use the highlighted harbor menu to create or switch between Personal, Work, and other areas. Each holds its own chats, Ships, and brainstorms. Right-click an item to move it. Model connections stay shared. Creating a harbor is optional."
        case .data:
            return "Settings → General → Data & Storage explains deletion and reset. Chat confirmations offer a five-minute skip. Full reset requires DELETE, quits, and finishes when you reopen. It does not securely erase an SSD or remove exports, backups, provider copies, or local models. You do not need to delete anything to finish."
        }
    }
}
