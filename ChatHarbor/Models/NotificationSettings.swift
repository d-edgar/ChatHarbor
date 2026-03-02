import Foundation
import SwiftUI

// MARK: - Notification Settings

struct NotificationSettings: Codable {
    var globalEnabled: Bool = true
    var showBanners: Bool = true
    var playSound: Bool = true
    var bounceDock: Bool = true
    var showDockBadge: Bool = true
    var badgeColor: BadgeColor = .red
    var mutedServiceIds: Set<String> = []

    // Workspace guard — prevents clipboard cross-contamination
    var workspaceGuardEnabled: Bool = false
    var workspaceGuardClearClipboard: Bool = true
    var workspaceGuardShowWarning: Bool = true
    /// Category names treated as "workspace" zones (e.g. "Workspace")
    var workspaceCategories: Set<String> = [DefaultCategory.workspace]

    // Privacy Shield — blur content when screen is being shared/recorded
    var privacyShieldEnabled: Bool = false
    var privacyShieldBlurContent: Bool = true
    var privacyShieldShowWarning: Bool = true
}

// MARK: - Badge Color Options

enum BadgeColor: String, Codable, CaseIterable {
    case red
    case orange
    case blue
    case purple
    case green

    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .blue: return .blue
        case .purple: return .purple
        case .green: return .green
        }
    }

    var displayName: String {
        rawValue.capitalized
    }
}
