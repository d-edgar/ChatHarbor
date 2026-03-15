import SwiftUI
import SwiftData

@main
struct ChatHarborApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var chatManager = ChatManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(chatManager)
                .frame(minWidth: 700, minHeight: 500)
        }
        .modelContainer(for: [Conversation.self, Message.self])
        .windowStyle(.titleBar)
        .defaultSize(width: 1000, height: 700)
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
