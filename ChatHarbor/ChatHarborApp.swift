import SwiftUI
import SwiftData

@main
struct ChatHarborApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var chatManager: ChatManager
    private let container: ModelContainer

    init() {
        let schema = Schema([Harbor.self, Conversation.self, Message.self, BrainstormSession.self,
                             BrainstormEntry.self, Ship.self, ShipConversation.self, ShipMessage.self])
        let configuration = ModelConfiguration(schema: schema)
        let domain = Bundle.main.bundleIdentifier!
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .map { $0.appendingPathComponent(domain, isDirectory: true) }
        while true {
            do {
                try LocalDataReset.perform(storeURL: configuration.url, defaults: .standard,
                                           domain: domain, cacheURLs: caches,
                                           deleteCredentials: { try KeychainHelper.deleteAll() })
                container = try ModelContainer(for: schema, configurations: [configuration])
                break
            } catch {
                let alert = NSAlert()
                alert.messageText = "ChatHarbor could not open its data"
                alert.informativeText = "If a reset was requested, it has not finished. " + error.localizedDescription
                alert.addButton(withTitle: "Retry")
                alert.addButton(withTitle: "Quit")
                if alert.runModal() != .alertFirstButtonReturn { exit(1) }
            }
        }
        _chatManager = StateObject(wrappedValue: ChatManager())
    }

    /// Brainstorm manager — initialized after chatManager so it can share providers
    private var brainstormManager: BrainstormManager {
        chatManager.brainstormManager
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(chatManager)
                .environmentObject(brainstormManager)
                .frame(minWidth: 800, minHeight: 600)
        }
        .modelContainer(container)
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            ChatHarborCommands(chatManager: chatManager)
        }

        Settings {
            ThemedSettingsWrapper()
                .environmentObject(chatManager)
                .modelContainer(container)
        }
    }
}

/// Wrapper that applies the current theme tint to the Settings window
struct ThemedSettingsWrapper: View {
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SettingsView()
            .environmentObject(chatManager)
            .tint(chatManager.currentTheme.accentColor(for: colorScheme))
    }
}
