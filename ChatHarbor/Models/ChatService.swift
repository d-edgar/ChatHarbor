import Foundation

struct ChatService: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var url: URL
    var iconName: String
    var isEnabled: Bool
    var notificationCount: Int

    init(id: String, name: String, url: URL, iconName: String, isEnabled: Bool = true, notificationCount: Int = 0) {
        self.id = id
        self.name = name
        self.url = url
        self.iconName = iconName
        self.isEnabled = isEnabled
        self.notificationCount = notificationCount
    }
}

// MARK: - Preconfigured Services

extension ChatService {
    static let googleChat = ChatService(
        id: "google-chat",
        name: "Google Chat",
        url: URL(string: "https://chat.google.com")!,
        iconName: "bubble.left.and.bubble.right.fill"
    )

    static let slack = ChatService(
        id: "slack",
        name: "Slack",
        url: URL(string: "https://app.slack.com")!,
        iconName: "number.square.fill"
    )

    static let microsoftTeams = ChatService(
        id: "microsoft-teams",
        name: "Microsoft Teams",
        url: URL(string: "https://teams.microsoft.com")!,
        iconName: "person.3.fill"
    )

    static let discord = ChatService(
        id: "discord",
        name: "Discord",
        url: URL(string: "https://discord.com/app")!,
        iconName: "gamecontroller.fill"
    )

    static let allPreconfigured: [ChatService] = [
        .googleChat, .slack, .microsoftTeams, .discord
    ]
}
