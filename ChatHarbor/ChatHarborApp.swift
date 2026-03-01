import SwiftUI

@main
struct ChatHarborApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var serviceManager = ServiceManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(serviceManager)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    AppDelegate.serviceManager = serviceManager
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 750)
        .commands {
            ChatHarborCommands(serviceManager: serviceManager)
        }

        Settings {
            ThemedSettingsWrapper()
                .environmentObject(serviceManager)
        }
    }
}

/// Wrapper that applies the current theme tint to the Settings window
struct ThemedSettingsWrapper: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SettingsView()
            .environmentObject(serviceManager)
            .tint(serviceManager.currentTheme.accentColor(for: colorScheme))
    }
}
