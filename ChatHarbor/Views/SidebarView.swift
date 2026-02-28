import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var serviceManager: ServiceManager

    var body: some View {
        List(serviceManager.enabledServices, selection: $serviceManager.selectedServiceId) { service in
            Label {
                Text(service.name)
            } icon: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: service.iconName)
                        .font(.title2)
                        .frame(width: 28, height: 28)

                    if service.notificationCount > 0 {
                        NotificationBadge(count: service.notificationCount)
                    }
                }
            }
            .tag(service.id)
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180)
        .navigationTitle("Services")
    }
}

// MARK: - Notification Badge

struct NotificationBadge: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.red, in: Capsule())
            .offset(x: 6, y: -6)
    }
}
