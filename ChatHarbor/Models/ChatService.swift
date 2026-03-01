import Foundation

struct ChatService: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var url: URL
    var iconName: String
    var isEnabled: Bool
    var notificationCount: Int
    var category: ServiceCategory

    init(id: String, name: String, url: URL, iconName: String, isEnabled: Bool = true, notificationCount: Int = 0, category: ServiceCategory = .chat) {
        self.id = id
        self.name = name
        self.url = url
        self.iconName = iconName
        self.isEnabled = isEnabled
        self.notificationCount = notificationCount
        self.category = category
    }
}

// MARK: - Service Categories

enum ServiceCategory: String, Codable, CaseIterable {
    case workspace = "Workspace"
    case chat = "Chat"
    case social = "Social"
    case custom = "Custom"
}

// MARK: - Preconfigured Services

extension ChatService {

    // --- Workspace ---

    static let slack = ChatService(
        id: "slack",
        name: "Slack",
        url: URL(string: "https://app.slack.com/client")!,
        iconName: "number.square.fill",
        category: .workspace
    )

    static let microsoftTeams = ChatService(
        id: "microsoft-teams",
        name: "Microsoft Teams",
        url: URL(string: "https://teams.microsoft.com")!,
        iconName: "person.3.fill",
        category: .workspace
    )

    static let googleChat = ChatService(
        id: "google-chat",
        name: "Google Chat",
        url: URL(string: "https://mail.google.com/chat/")!,
        iconName: "bubble.left.and.bubble.right.fill",
        category: .workspace
    )

    // --- Chat ---

    static let discord = ChatService(
        id: "discord",
        name: "Discord",
        url: URL(string: "https://discord.com/app")!,
        iconName: "gamecontroller.fill",
        category: .chat
    )

    static let whatsApp = ChatService(
        id: "whatsapp",
        name: "WhatsApp",
        url: URL(string: "https://web.whatsapp.com")!,
        iconName: "phone.fill",
        category: .chat
    )

    static let telegram = ChatService(
        id: "telegram",
        name: "Telegram",
        url: URL(string: "https://web.telegram.org")!,
        iconName: "paperplane.fill",
        category: .chat
    )

    static let signal = ChatService(
        id: "signal",
        name: "Signal",
        url: URL(string: "https://signal.org/download/")!,
        iconName: "lock.shield.fill",
        isEnabled: false,
        category: .chat
    )

    // --- Social ---

    static let messenger = ChatService(
        id: "messenger",
        name: "Messenger",
        url: URL(string: "https://www.messenger.com")!,
        iconName: "message.fill",
        isEnabled: false,
        category: .social
    )

    static let linkedIn = ChatService(
        id: "linkedin",
        name: "LinkedIn Messages",
        url: URL(string: "https://www.linkedin.com/messaging/")!,
        iconName: "briefcase.fill",
        isEnabled: false,
        category: .social
    )

    static let allPreconfigured: [ChatService] = [
        // Workspace
        .slack, .microsoftTeams, .googleChat,
        // Chat
        .discord, .whatsApp, .telegram, .signal,
        // Social
        .messenger, .linkedIn
    ]
}
