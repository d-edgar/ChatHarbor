import SwiftUI

struct ContentView: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            SidebarView()
        } detail: {
            if serviceManager.isLaunching {
                SplashView()
            } else if let selectedId = serviceManager.selectedServiceId,
               let service = serviceManager.enabledServices.first(where: { $0.id == selectedId }) {
                WebContainerView(service: service)
                    .id(service.id)
            } else {
                WelcomeView()
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

// MARK: - Splash Screen

struct SplashView: View {
    @State private var opacity: Double = 0
    @State private var scale: Double = 0.8

    var body: some View {
        VStack(spacing: 20) {
            Image("ChatHarborLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

            Text("ChatHarbor")
                .font(.system(size: 36, weight: .bold, design: .rounded))

            Text("All your chats, one harbor.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ProgressView()
                .scaleEffect(0.8)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(opacity)
        .scaleEffect(scale)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                opacity = 1.0
                scale = 1.0
            }
        }
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image("ChatHarborLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.1), radius: 6, y: 3)

            Text("Welcome to ChatHarbor")
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text("Select a service from the sidebar to get started.")
                .font(.body)
                .foregroundStyle(.secondary)

            HStack(spacing: 20) {
                KeyboardHint(key: "Cmd+1-9", label: "Switch services")
                KeyboardHint(key: "Cmd+R", label: "Reload")
                KeyboardHint(key: "Cmd+[", label: "Go back")
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Keyboard Hint Chip

struct KeyboardHint: View {
    let key: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
