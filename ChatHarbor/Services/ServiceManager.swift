import Foundation
import Combine
import SwiftUI

class ServiceManager: ObservableObject {
    @Published var services: [ChatService]
    @Published var categories: [String]
    @Published var selectedServiceId: String?
    @Published var isLaunching: Bool = true
    @Published var appearanceMode: AppearanceMode {
        didSet {
            persistAppearance()
            applyAppearance()
        }
    }

    private let storageKey = "chatharbor.services"
    private let categoriesKey = "chatharbor.categories"
    private let appearanceKey = "chatharbor.appearance"
    private var navigationObserver: NSObjectProtocol?

    init() {
        // Load appearance preference
        if let saved = UserDefaults.standard.string(forKey: appearanceKey),
           let mode = AppearanceMode(rawValue: saved) {
            self.appearanceMode = mode
        } else {
            self.appearanceMode = .auto
        }

        // Load persisted categories or seed with defaults
        if let savedCategories = UserDefaults.standard.stringArray(forKey: categoriesKey) {
            self.categories = savedCategories
        } else {
            self.categories = DefaultCategory.allDefaults
        }

        // Load persisted services or seed with defaults
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([ChatService].self, from: data) {
            self.services = decoded
            migrateServices()
        } else {
            self.services = ChatService.allPreconfigured
        }

        // Ensure all service categories exist in category list
        syncCategories()

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

        // Apply saved appearance on launch
        applyAppearance()
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

    /// Services grouped by category, in category order
    func services(inCategory category: String) -> [ChatService] {
        services.filter { $0.category == category }
    }

    func enabledServices(inCategory category: String) -> [ChatService] {
        enabledServices.filter { $0.category == category }
    }

    // MARK: - Service Management

    func toggleService(_ service: ChatService) {
        if let index = services.firstIndex(where: { $0.id == service.id }) {
            services[index].isEnabled.toggle()
            persist()
        }
    }

    func addCustomService(name: String, urlString: String, category: String = DefaultCategory.custom) {
        guard let url = URL(string: urlString),
              url.scheme == "http" || url.scheme == "https" else { return }

        let id = "custom-\(UUID().uuidString.prefix(8).lowercased())"
        let service = ChatService(
            id: id,
            name: name,
            url: url,
            iconName: "globe",
            category: category
        )
        services.append(service)
        persist()
    }

    func updateCategory(for service: ChatService, to category: String) {
        updateCategory(forServiceId: service.id, to: category)
    }

    func updateCategory(forServiceId serviceId: String, to category: String) {
        if let index = services.firstIndex(where: { $0.id == serviceId }) {
            services[index].category = category
            persist()
        }
    }

    func removeService(_ service: ChatService) {
        services.removeAll { $0.id == service.id }
        if selectedServiceId == service.id {
            selectedServiceId = nil
        }
        persist()
    }

    /// Move a service within its category
    func moveServiceWithinCategory(_ category: String, from source: IndexSet, to destination: Int) {
        // Get indices of services in this category within the master array
        var categoryIndices: [Int] = []
        for (i, service) in services.enumerated() where service.category == category {
            categoryIndices.append(i)
        }

        // Perform the move on a copy of just the category indices
        var reordered = categoryIndices
        reordered.move(fromOffsets: source, toOffset: destination)

        // Rebuild the full services array with reordered category items
        var updated = services
        for (newPos, oldIndex) in reordered.enumerated() {
            updated[categoryIndices[newPos]] = services[oldIndex]
        }
        services = updated
        persist()
    }

    // MARK: - Category Management

    func addCategory(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !categories.contains(trimmed) else { return }
        categories.append(trimmed)
        persistCategories()
    }

    func renameCategory(from oldName: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !categories.contains(trimmed),
              let index = categories.firstIndex(of: oldName) else { return }
        categories[index] = trimmed

        // Update all services in this category
        for i in services.indices where services[i].category == oldName {
            services[i].category = trimmed
        }
        persistCategories()
        persist()
    }

    func removeCategory(named name: String) {
        guard let index = categories.firstIndex(of: name) else { return }
        categories.remove(at: index)

        // Move orphaned services to the first available category
        let fallback = categories.first ?? DefaultCategory.custom
        for i in services.indices where services[i].category == name {
            services[i].category = fallback
        }

        persistCategories()
        persist()
    }

    func moveCategory(from source: IndexSet, to destination: Int) {
        var updated = categories
        updated.move(fromOffsets: source, toOffset: destination)
        categories = updated
        persistCategories()
    }

    /// Ensure every category used by a service exists in the ordered list
    private func syncCategories() {
        var changed = false
        for service in services {
            if !categories.contains(service.category) {
                categories.append(service.category)
                changed = true
            }
        }
        if changed { persistCategories() }
    }

    // MARK: - Notification Counts

    func updateNotificationCount(for serviceId: String, count: Int) {
        if let index = services.firstIndex(where: { $0.id == serviceId }) {
            services[index].notificationCount = count
            AppDelegate.updateDockBadge(count: totalNotificationCount)
        }
    }

    // MARK: - Migration

    private func migrateServices() {
        let canonical = Dictionary(
            uniqueKeysWithValues: ChatService.allPreconfigured.map { ($0.id, $0) }
        )
        var changed = false

        for i in services.indices {
            if let latest = canonical[services[i].id], services[i].url != latest.url {
                services[i].url = latest.url
                changed = true
            }
        }

        let existingIds = Set(services.map(\.id))
        for preconfigured in ChatService.allPreconfigured where !existingIds.contains(preconfigured.id) {
            services.append(preconfigured)
            changed = true
        }

        if changed { persist() }
    }

    // MARK: - Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(services) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func persistCategories() {
        UserDefaults.standard.set(categories, forKey: categoriesKey)
    }

    private func persistAppearance() {
        UserDefaults.standard.set(appearanceMode.rawValue, forKey: appearanceKey)
    }

    /// Apply appearance at the NSApp level so all windows update consistently
    func applyAppearance() {
        switch appearanceMode {
        case .auto:
            NSApp.appearance = nil  // nil = follow system
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    // MARK: - Reset to Defaults

    func resetToDefaults() {
        services = ChatService.allPreconfigured
        categories = DefaultCategory.allDefaults
        selectedServiceId = nil
        appearanceMode = .auto
        persist()
        persistCategories()
        persistAppearance()
    }
}

// MARK: - Appearance Mode

enum AppearanceMode: String, CaseIterable {
    case auto = "auto"
    case light = "light"
    case dark = "dark"

    var displayName: String {
        switch self {
        case .auto: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
