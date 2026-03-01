import Foundation
import Combine
import SwiftUI

class ServiceManager: ObservableObject {
    @Published var services: [ChatService]
    @Published var categories: [String]
    @Published var selectedServiceId: String?
    @Published var isLaunching: Bool = true
    @Published var isOnboarding: Bool = false
    @Published var appearanceMode: AppearanceMode {
        didSet {
            persistAppearance()
            applyAppearance()
        }
    }
    @Published var notificationSettings: NotificationSettings {
        didSet { persistNotificationSettings() }
    }
    @Published var selectedThemeId: String {
        didSet { persistTheme() }
    }

    /// The resolved theme object for the current selection
    var currentTheme: AppTheme {
        ThemeCatalog.theme(forId: selectedThemeId)
    }

    private let storageKey = "chatharbor.services"
    private let categoriesKey = "chatharbor.categories"
    private let appearanceKey = "chatharbor.appearance"
    private let notificationSettingsKey = "chatharbor.notificationSettings"
    private let themeKey = "chatharbor.theme"
    private let hasLaunchedKey = "chatharbor.hasLaunched"
    private var navigationObserver: NSObjectProtocol?

    /// Whether this is the very first launch (no saved data)
    var isFirstLaunch: Bool {
        !UserDefaults.standard.bool(forKey: hasLaunchedKey)
    }

    init() {
        // Load appearance preference
        if let saved = UserDefaults.standard.string(forKey: appearanceKey),
           let mode = AppearanceMode(rawValue: saved) {
            self.appearanceMode = mode
        } else {
            self.appearanceMode = .auto
        }

        // Load theme preference
        if let savedTheme = UserDefaults.standard.string(forKey: themeKey) {
            self.selectedThemeId = savedTheme
        } else {
            self.selectedThemeId = ThemeCatalog.defaultTheme.id
        }

        // Load notification settings
        if let data = UserDefaults.standard.data(forKey: notificationSettingsKey),
           let decoded = try? JSONDecoder().decode(NotificationSettings.self, from: data) {
            self.notificationSettings = decoded
        } else {
            self.notificationSettings = NotificationSettings()
        }

        // Load persisted categories or seed with defaults
        if let savedCategories = UserDefaults.standard.stringArray(forKey: categoriesKey) {
            self.categories = savedCategories
        } else {
            self.categories = DefaultCategory.allDefaults
        }

        // Load persisted services — or start empty for new users
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([ChatService].self, from: data) {
            self.services = decoded
        } else {
            // New user: start with an empty service list
            self.services = []
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
                self?.selectService(serviceId)
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

        // Mark that we've launched at least once
        UserDefaults.standard.set(true, forKey: hasLaunchedKey)
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

    /// IDs of services already added
    var existingServiceIds: Set<String> {
        Set(services.map(\.id))
    }

    // MARK: - Workspace Guard

    /// Whether a service is in a workspace category
    func isWorkspaceService(_ service: ChatService) -> Bool {
        notificationSettings.workspaceCategories.contains(service.category)
    }

    /// Pending workspace transition info (set when guard triggers, consumed by UI)
    @Published var pendingWorkspaceWarning: WorkspaceTransition?

    struct WorkspaceTransition {
        let targetServiceId: String
        let targetServiceName: String
    }

    /// Central method for navigating to a service.
    /// Checks workspace guard and fires warning/clipboard clear as needed.
    func selectService(_ serviceId: String?) {
        guard let serviceId = serviceId,
              let target = services.first(where: { $0.id == serviceId }) else {
            selectedServiceId = serviceId
            return
        }

        let settings = notificationSettings
        let guardEnabled = settings.workspaceGuardEnabled

        // Determine if we're crossing from non-workspace → workspace
        var crossingIntoWorkspace = false
        if guardEnabled, isWorkspaceService(target) {
            if let currentId = selectedServiceId,
               let current = services.first(where: { $0.id == currentId }) {
                crossingIntoWorkspace = !isWorkspaceService(current)
            } else {
                // Coming from home / no selection — not a cross-contamination risk
                crossingIntoWorkspace = false
            }
        }

        if crossingIntoWorkspace {
            if settings.workspaceGuardClearClipboard {
                NSPasteboard.general.clearContents()
            }
            if settings.workspaceGuardShowWarning {
                pendingWorkspaceWarning = WorkspaceTransition(
                    targetServiceId: serviceId,
                    targetServiceName: target.name
                )
                // Navigation happens after user dismisses the alert
                return
            }
        }

        selectedServiceId = serviceId
    }

    /// Called after the user dismisses the workspace warning
    func confirmWorkspaceTransition() {
        if let transition = pendingWorkspaceWarning {
            selectedServiceId = transition.targetServiceId
            pendingWorkspaceWarning = nil
        }
    }

    func dismissWorkspaceWarning() {
        pendingWorkspaceWarning = nil
    }

    // MARK: - Service Management

    func toggleService(_ service: ChatService) {
        if let index = services.firstIndex(where: { $0.id == service.id }) {
            services[index].isEnabled.toggle()
            persist()
        }
    }

    /// Add a service from the catalog
    func addFromCatalog(_ template: ServiceTemplate) {
        guard !existingServiceIds.contains(template.id) else { return }
        let service = ChatService(
            id: template.id,
            name: template.name,
            url: template.url,
            iconName: template.iconName,
            category: template.suggestedCategory
        )
        services.append(service)

        // Ensure the category exists
        if !categories.contains(template.suggestedCategory) {
            categories.append(template.suggestedCategory)
            persistCategories()
        }

        persist()
    }

    /// Add multiple services from the catalog at once
    func addFromCatalog(_ templates: [ServiceTemplate]) {
        for template in templates {
            addFromCatalog(template)
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
        WebViewPool.shared.removeWebView(for: service.id)
        persist()
    }

    /// Move a service within its category
    func moveServiceWithinCategory(_ category: String, from source: IndexSet, to destination: Int) {
        var categoryIndices: [Int] = []
        for (i, service) in services.enumerated() where service.category == category {
            categoryIndices.append(i)
        }

        var reordered = categoryIndices
        reordered.move(fromOffsets: source, toOffset: destination)

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

        for i in services.indices where services[i].category == oldName {
            services[i].category = trimmed
        }
        persistCategories()
        persist()
    }

    func removeCategory(named name: String) {
        guard let index = categories.firstIndex(of: name) else { return }
        categories.remove(at: index)

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

    // MARK: - Notification Settings Helpers

    func isServiceMuted(_ serviceId: String) -> Bool {
        notificationSettings.mutedServiceIds.contains(serviceId)
    }

    func toggleMute(for serviceId: String) {
        if notificationSettings.mutedServiceIds.contains(serviceId) {
            notificationSettings.mutedServiceIds.remove(serviceId)
        } else {
            notificationSettings.mutedServiceIds.insert(serviceId)
        }
    }

    // MARK: - Notification Counts

    func updateNotificationCount(for serviceId: String, count: Int) {
        if let index = services.firstIndex(where: { $0.id == serviceId }) {
            services[index].notificationCount = count
            if notificationSettings.showDockBadge {
                AppDelegate.updateDockBadge(count: totalNotificationCount)
            } else {
                AppDelegate.updateDockBadge(count: 0)
            }
        }
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

    private func persistNotificationSettings() {
        if let data = try? JSONEncoder().encode(notificationSettings) {
            UserDefaults.standard.set(data, forKey: notificationSettingsKey)
        }
    }

    private func persistTheme() {
        UserDefaults.standard.set(selectedThemeId, forKey: themeKey)
    }

    /// Apply appearance at the NSApp level so all windows update consistently
    func applyAppearance() {
        switch appearanceMode {
        case .auto:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    // MARK: - Reset to Defaults

    func resetToDefaults() {
        services = []
        categories = DefaultCategory.allDefaults
        selectedServiceId = nil
        isOnboarding = true
        appearanceMode = .auto
        selectedThemeId = ThemeCatalog.defaultTheme.id
        notificationSettings = NotificationSettings()
        WebViewPool.shared.removeAll()
        persist()
        persistCategories()
        persistAppearance()
        persistTheme()
        persistNotificationSettings()
    }

    func finishOnboarding() {
        isOnboarding = false
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
