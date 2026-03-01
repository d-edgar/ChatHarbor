import Foundation
import Combine
import SwiftUI

class ServiceManager: ObservableObject {
    @Published var services: [ChatService]
    @Published var selectedServiceId: String?
    @Published var isLaunching: Bool = true

    private let storageKey = "chatharbor.services"
    private var navigationObserver: NSObjectProtocol?

    init() {
        // Load persisted services or seed with defaults
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([ChatService].self, from: data) {
            self.services = decoded
            migrateServices()
        } else {
            self.services = ChatService.allPreconfigured
        }

        // Listen for notification-driven navigation
        navigationObserver = NotificationCenter.default.addObserver(
            forName: .navigateToService,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let serviceId = notification.userInfo?["serviceId"] as? String {
                self?.selectedServiceId = serviceId
            }
        }

        // Dismiss splash after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            withAnimation(.easeInOut(duration: 0.3)) {
                self?.isLaunching = false
            }
        }
    }

    deinit {
        if let observer = navigationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Computed Properties

    var enabledServices: [ChatService] {
        services.filter { $0.isEnabled }
    }

    var totalNotificationCount: Int {
        services.reduce(0) { $0 + $1.notificationCount }
    }

    // MARK: - Service Management

    func toggleService(_ service: ChatService) {
        if let index = services.firstIndex(where: { $0.id == service.id }) {
            services[index].isEnabled.toggle()
            persist()
        }
    }

    func addCustomService(name: String, urlString: String) {
        guard let url = URL(string: urlString),
              url.scheme == "http" || url.scheme == "https" else { return }

        let id = "custom-\(UUID().uuidString.prefix(8).lowercased())"
        let service = ChatService(
            id: id,
            name: name,
            url: url,
            iconName: "globe",
            category: .custom
        )
        services.append(service)
        persist()
    }

    func removeService(_ service: ChatService) {
        services.removeAll { $0.id == service.id }
        if selectedServiceId == service.id {
            selectedServiceId = nil
        }
        persist()
    }

    func moveService(from source: IndexSet, to destination: Int) {
        var updated = services
        updated.move(fromOffsets: source, toOffset: destination)
        services = updated
        persist()
    }

    // MARK: - Notification Counts

    func updateNotificationCount(for serviceId: String, count: Int) {
        if let index = services.firstIndex(where: { $0.id == serviceId }) {
            services[index].notificationCount = count
            AppDelegate.updateDockBadge(count: totalNotificationCount)
        }
    }

    // MARK: - Migration

    /// Updates persisted services with the latest URLs and adds any new
    /// preconfigured services that were introduced in an update.
    private func migrateServices() {
        let canonical = Dictionary(
            uniqueKeysWithValues: ChatService.allPreconfigured.map { ($0.id, $0) }
        )
        var changed = false

        // Update URLs for existing preconfigured services
        for i in services.indices {
            if let latest = canonical[services[i].id], services[i].url != latest.url {
                services[i].url = latest.url
                changed = true
            }
        }

        // Add any new preconfigured services that don't exist yet
        let existingIds = Set(services.map(\.id))
        for preconfigured in ChatService.allPreconfigured where !existingIds.contains(preconfigured.id) {
            services.append(preconfigured)
            changed = true
        }

        if changed {
            persist()
        }
    }

    // MARK: - Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(services) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
