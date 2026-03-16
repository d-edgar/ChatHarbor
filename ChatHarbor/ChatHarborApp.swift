import SwiftUI
import SwiftData

@main
struct ChatHarborApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var chatManager = ChatManager()

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
        .modelContainer(for: [Conversation.self, Message.self, BrainstormSession.self, BrainstormEntry.self])
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            ChatHarborCommands(chatManager: chatManager)
        }

        Settings {
            ThemedSettingsWrapper()
                .environmentObject(chatManager)
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
