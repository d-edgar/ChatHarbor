import Foundation

struct ChatService: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var url: URL
    var iconName: String
    var isEnabled: Bool
    var notificationCount: Int
    var category: String

    init(id: String, name: String, url: URL, iconName: String, isEnabled: Bool = true, notificationCount: Int = 0, category: String = "Chat") {
        self.id = id
        self.name = name
        self.url = url
        self.iconName = iconName
        self.isEnabled = isEnabled
        self.notificationCount = notificationCount
        self.category = category
    }
}

// MARK: - Default Category Names

enum DefaultCategory {
    static let workspace = "Workspace"
    static let chat = "Chat"
    static let social = "Social"
    static let custom = "Custom"

    static let allDefaults: [String] = [workspace, chat, social, custom]
}

// MARK: - Service Catalog (templates users can add from)

/// A template entry in the service catalog. Not added to the user's
/// service list until they explicitly choose it.
struct ServiceTemplate: Identifiable {
    let id: String
    let name: String
    let url: URL
    let iconName: String
    let suggestedCategory: String
    let description: String
}

enum ServiceCatalog {

    static let all: [ServiceTemplate] = [
        // Workspace
        ServiceTemplate(
            id: "slack",
            name: "Slack",
            url: URL(string: "https://app.slack.com/client")!,
            iconName: "number.square.fill",
            suggestedCategory: DefaultCategory.workspace,
            description: "Team messaging and collaboration"
        ),
        ServiceTemplate(
            id: "microsoft-teams",
            name: "Microsoft Teams",
            url: URL(string: "https://teams.microsoft.com")!,
            iconName: "person.3.fill",
            suggestedCategory: DefaultCategory.workspace,
            description: "Video calls, chat, and file sharing"
        ),
        ServiceTemplate(
            id: "google-chat",
            name: "Google Chat",
            url: URL(string: "https://mail.google.com/chat/")!,
            iconName: "bubble.left.and.bubble.right.fill",
            suggestedCategory: DefaultCategory.workspace,
            description: "Google Workspace messaging"
        ),

        // Chat
        ServiceTemplate(
            id: "discord",
            name: "Discord",
            url: URL(string: "https://discord.com/app")!,
            iconName: "gamecontroller.fill",
            suggestedCategory: DefaultCategory.chat,
            description: "Voice, video, and text communities"
        ),
        ServiceTemplate(
            id: "whatsapp",
            name: "WhatsApp",
            url: URL(string: "https://web.whatsapp.com")!,
            iconName: "phone.fill",
            suggestedCategory: DefaultCategory.chat,
            description: "End-to-end encrypted messaging"
        ),
        ServiceTemplate(
            id: "telegram",
            name: "Telegram",
            url: URL(string: "https://web.telegram.org")!,
            iconName: "paperplane.fill",
            suggestedCategory: DefaultCategory.chat,
            description: "Cloud-based instant messaging"
        ),
        ServiceTemplate(
            id: "signal",
            name: "Signal",
            url: URL(string: "https://signal.org/download/")!,
            iconName: "lock.shield.fill",
            suggestedCategory: DefaultCategory.chat,
            description: "Private, secure messaging"
        ),

        // Social
        ServiceTemplate(
            id: "messenger",
            name: "Messenger",
            url: URL(string: "https://www.messenger.com")!,
            iconName: "message.fill",
            suggestedCategory: DefaultCategory.social,
            description: "Facebook / Meta messaging"
        ),
        ServiceTemplate(
            id: "linkedin",
            name: "LinkedIn Messages",
            url: URL(string: "https://www.linkedin.com/messaging/")!,
            iconName: "briefcase.fill",
            suggestedCategory: DefaultCategory.social,
            description: "Professional networking messages"
        ),
    ]

    /// Templates not yet added by the user
    static func available(excluding existingIds: Set<String>) -> [ServiceTemplate] {
        all.filter { !existingIds.contains($0.id) }
    }

    /// Group available templates by suggested category
    static func grouped(excluding existingIds: Set<String>) -> [(category: String, templates: [ServiceTemplate])] {
        let available = self.available(excluding: existingIds)
        let grouped = Dictionary(grouping: available) { $0.suggestedCategory }
        let order = [DefaultCategory.workspace, DefaultCategory.chat, DefaultCategory.social]
        return order.compactMap { cat in
            guard let templates = grouped[cat], !templates.isEmpty else { return nil }
            return (category: cat, templates: templates)
        }
    }
}
