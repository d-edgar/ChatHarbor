import SwiftUI

struct ContentView: View {
    @EnvironmentObject var serviceManager: ServiceManager

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if let selectedId = serviceManager.selectedServiceId,
               let service = serviceManager.enabledServices.first(where: { $0.id == selectedId }) {
                WebContainerView(service: service)
                    .id(service.id)
            } else {
                WelcomeView()
            }
        }
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Welcome to ChatHarbor")
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text("Select a service from the sidebar to get started.")
                .font(.body)
                .foregroundStyle(.secondary)

            Text("Cmd+1 through Cmd+9 to switch services")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
