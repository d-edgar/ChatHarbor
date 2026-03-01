import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var serviceManager: ServiceManager

    var body: some View {
        List(selection: $serviceManager.selectedServiceId) {
            ForEach(ServiceCategory.allCases, id: \.self) { category in
                let servicesInCategory = serviceManager.enabledServices.filter { $0.category == category }
                if !servicesInCategory.isEmpty {
                    Section(header: Text(category.rawValue).font(.caption).foregroundStyle(.secondary)) {
                        ForEach(servicesInCategory) { service in
                            ServiceRow(service: service)
                                .tag(service.id)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180)
        .navigationTitle("ChatHarbor")
        .toolbar {
            // Compact icon strip at the top of sidebar for quick access
            ToolbarItem(placement: .automatic) {
                CompactServiceStrip()
                    .environmentObject(serviceManager)
            }
        }
    }
}

// MARK: - Compact Service Strip (shown at top of sidebar)

struct CompactServiceStrip: View {
    @EnvironmentObject var serviceManager: ServiceManager

    var body: some View {
        HStack(spacing: 4) {
            ForEach(serviceManager.enabledServices) { service in
                Button {
                    serviceManager.selectedServiceId = service.id
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: service.iconName)
                            .font(.system(size: 13))
                            .frame(width: 24, height: 24)
                            .foregroundStyle(
                                serviceManager.selectedServiceId == service.id
                                    ? .primary
                                    : .secondary
                            )

                        if service.notificationCount > 0 {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 7, height: 7)
                                .offset(x: 3, y: -3)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(service.name)
            }
        }
    }
}

// MARK: - Service Row

struct ServiceRow: View {
    let service: ChatService

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: service.iconName)
                    .font(.title3)
                    .frame(width: 26, height: 26)
                    .foregroundStyle(.primary)

                if service.notificationCount > 0 {
                    NotificationBadge(count: service.notificationCount)
                }
            }

            Text(service.name)
                .lineLimit(1)

            Spacer()

            if service.notificationCount > 0 {
                Text("\(service.notificationCount)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red, in: Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Notification Badge (icon overlay)

struct NotificationBadge: View {
    let count: Int

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 8, height: 8)
            .offset(x: 4, y: -4)
    }
}
