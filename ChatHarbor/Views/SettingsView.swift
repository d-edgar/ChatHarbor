import SwiftUI
import UniformTypeIdentifiers

// MARK: - Settings Window

struct SettingsView: View {
    @EnvironmentObject var serviceManager: ServiceManager

    var body: some View {
        TabView {
            ServicesSettingsView()
                .environmentObject(serviceManager)
                .tabItem {
                    Label("Services", systemImage: "list.bullet")
                }

            AppearanceSettingsView()
                .environmentObject(serviceManager)
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            NotificationSettingsView()
                .environmentObject(serviceManager)
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }

            SecuritySettingsView()
                .environmentObject(serviceManager)
                .tabItem {
                    Label("Security", systemImage: "lock.shield")
                }

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 560, height: 560)
    }
}

// MARK: - Services Tab

struct ServicesSettingsView: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @State private var showingAddService = false
    @State private var showingAddCategory = false
    @State private var showingCatalog = false
    @State private var showingResetConfirm = false
    @State private var showingRestartSetup = false
    @State private var draggingServiceId: String?

    var body: some View {
        VStack(spacing: 0) {
            // Hint
            HStack(spacing: 4) {
                Image(systemName: "hand.draw")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text("Drag services between categories to organize.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Category zones
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(serviceManager.categories, id: \.self) { category in
                        CategoryZoneView(
                            category: category,
                            draggingServiceId: $draggingServiceId
                        )
                        .environmentObject(serviceManager)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            Divider()

            // Bottom bar
            HStack(spacing: 12) {
                Button {
                    showingAddCategory = true
                } label: {
                    Label("Add Category", systemImage: "folder.badge.plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button {
                    showingResetConfirm = true
                } label: {
                    Label("Remove All", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red.opacity(0.7))

                Button {
                    showingRestartSetup = true
                } label: {
                    Label("Re-run Setup", systemImage: "arrow.counterclockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Browse Catalog...") {
                    showingCatalog = true
                }
                .controlSize(.small)

                Button("Add Custom...") {
                    showingAddService = true
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .sheet(isPresented: $showingAddService) {
            AddCustomServiceSheet(isPresented: $showingAddService)
                .environmentObject(serviceManager)
        }
        .sheet(isPresented: $showingAddCategory) {
            AddCategorySheet(isPresented: $showingAddCategory)
                .environmentObject(serviceManager)
        }
        .sheet(isPresented: $showingCatalog) {
            CatalogSheet(isPresented: $showingCatalog)
                .environmentObject(serviceManager)
        }
        .alert("Remove All Services?", isPresented: $showingResetConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Remove All", role: .destructive) {
                serviceManager.resetToDefaults()
            }
        } message: {
            Text("This will remove all services and reset categories and appearance to defaults.")
        }
        .alert("Re-run First-Time Setup?", isPresented: $showingRestartSetup) {
            Button("Cancel", role: .cancel) { }
            Button("Re-run Setup", role: .destructive) {
                serviceManager.resetToDefaults()
                // Close all non-main windows (Settings) and focus the main window
                DispatchQueue.main.async {
                    let mainWindow = NSApp.windows.first { $0.level == .normal && $0.styleMask.contains(.titled) && $0.contentView != nil }
                    for window in NSApp.windows where window != mainWindow {
                        window.close()
                    }
                    mainWindow?.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        } message: {
            Text("This will remove all services, reset all settings to defaults, and take you back to the welcome screen where you can pick your services again.")
        }
    }
}

// MARK: - Category Zone (drop target)

struct CategoryZoneView: View {
    let category: String
    @EnvironmentObject var serviceManager: ServiceManager
    @Environment(\.colorScheme) private var colorScheme
    @Binding var draggingServiceId: String?
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var isTargeted = false
    @State private var showingDeleteConfirm = false
    @State private var showingRenameConfirm = false

    private var accent: Color {
        serviceManager.currentTheme.accentColor(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Category header
            HStack(spacing: 8) {
                if isRenaming {
                    TextField("Category name", text: $renameText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: 160)
                        .onSubmit {
                            let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty && trimmed != category {
                                showingRenameConfirm = true
                            } else {
                                isRenaming = false
                            }
                        }

                    Button("Save") {
                        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty && trimmed != category {
                            showingRenameConfirm = true
                        } else {
                            isRenaming = false
                        }
                    }
                    .font(.caption)
                    .controlSize(.small)

                    Button("Cancel") {
                        isRenaming = false
                    }
                    .font(.caption)
                    .controlSize(.small)
                } else {
                    Text(category.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)

                    Text("(\(serviceManager.services(inCategory: category).count))")
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)

                    Spacer()

                    HStack(spacing: 8) {
                        Button("Rename") {
                            renameText = category
                            isRenaming = true
                        }
                        .font(.system(size: 10, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)

                        if serviceManager.categories.count > 1 {
                            Button("Delete") {
                                showingDeleteConfirm = true
                            }
                            .font(.system(size: 10, weight: .medium))
                            .buttonStyle(.plain)
                            .foregroundStyle(.red.opacity(0.7))
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary.opacity(0.5))
            )
            .alert("Rename Category?", isPresented: $showingRenameConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Rename") {
                    serviceManager.renameCategory(from: category, to: renameText)
                    isRenaming = false
                }
            } message: {
                Text("Rename \"\(category)\" to \"\(renameText.trimmingCharacters(in: .whitespaces))\"?")
            }
            .alert("Delete Category?", isPresented: $showingDeleteConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    serviceManager.removeCategory(named: category)
                }
            } message: {
                let count = serviceManager.services(inCategory: category).count
                if count > 0 {
                    Text("Delete \"\(category)\"? The \(count) service\(count == 1 ? "" : "s") in this category will be moved to the first remaining category.")
                } else {
                    Text("Delete the empty \"\(category)\" category?")
                }
            }

            // Service rows
            VStack(spacing: 1) {
                let servicesInCategory = serviceManager.services(inCategory: category)

                if servicesInCategory.isEmpty {
                    Text("Drag services here")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                } else {
                    ForEach(servicesInCategory) { service in
                        DraggableServiceRow(
                            service: service,
                            draggingServiceId: $draggingServiceId
                        )
                        .environmentObject(serviceManager)
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isTargeted ? accent.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isTargeted ? accent : Color.clear,
                        style: StrokeStyle(lineWidth: 2, dash: [6, 3])
                    )
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.background)
                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.quaternary.opacity(0.5), lineWidth: 1)
        )
        .onDrop(of: [.utf8PlainText], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            provider.loadObject(ofClass: NSString.self) { reading, _ in
                guard let serviceId = reading as? String else { return }
                DispatchQueue.main.async {
                    serviceManager.updateCategory(forServiceId: serviceId, to: category)
                    draggingServiceId = nil
                }
            }
            return true
        }
    }
}

// MARK: - Draggable Service Row

struct DraggableServiceRow: View {
    let service: ChatService
    @Binding var draggingServiceId: String?
    @EnvironmentObject var serviceManager: ServiceManager
    @State private var showingRemoveConfirm = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.quaternary)

            Image(systemName: service.iconName)
                .font(.body)
                .frame(width: 22)
                .foregroundStyle(.secondary)

            Text(service.name)
                .font(.system(size: 13))
                .lineLimit(1)

            Spacer()

            Toggle("", isOn: Binding(
                get: { service.isEnabled },
                set: { _ in serviceManager.toggleService(service) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            Button(role: .destructive) {
                showingRemoveConfirm = true
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Remove \(service.name)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.background)
        )
        .opacity(draggingServiceId == service.id ? 0.4 : 1.0)
        .onDrag {
            draggingServiceId = service.id
            return NSItemProvider(object: service.id as NSString)
        }
        .alert("Remove Service?", isPresented: $showingRemoveConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                serviceManager.removeService(service)
            }
        } message: {
            Text("Remove \"\(service.name)\" from ChatHarbor? You can add it back later from the catalog.")
        }
    }
}

// MARK: - Add Category Sheet

struct AddCategorySheet: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @Binding var isPresented: Bool
    @State private var name = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("New Category")
                .font(.headline)

            TextField("Category Name (e.g. Personal, Work, Gaming)", text: $name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    serviceManager.addCategory(named: name)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 340)
    }
}

// MARK: - Catalog Sheet (browse & add services from Settings)

struct CatalogSheet: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @Binding var isPresented: Bool
    @State private var selectedIds: Set<String> = []

    private var catalog: [(category: String, templates: [ServiceTemplate])] {
        ServiceCatalog.grouped(excluding: serviceManager.existingServiceIds)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Service Catalog")
                .font(.headline)

            if catalog.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 28))
                        .foregroundStyle(.green)
                    Text("All available services have been added.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(catalog, id: \.category) { group in
                            Text(group.category.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)

                            ForEach(group.templates) { template in
                                HStack(spacing: 10) {
                                    Image(systemName: template.iconName)
                                        .font(.body)
                                        .frame(width: 24)
                                        .foregroundStyle(.secondary)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(template.name)
                                            .font(.system(size: 13, weight: .medium))
                                        Text(template.description)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.tertiary)
                                    }

                                    Spacer()

                                    Toggle("", isOn: Binding(
                                        get: { selectedIds.contains(template.id) },
                                        set: { on in
                                            if on { selectedIds.insert(template.id) }
                                            else { selectedIds.remove(template.id) }
                                        }
                                    ))
                                    .labelsHidden()
                                    .toggleStyle(.checkbox)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .padding(.trailing, 16)
                }
            }

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if !selectedIds.isEmpty {
                    Text("\(selectedIds.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Add") {
                    let templates = ServiceCatalog.all.filter { selectedIds.contains($0.id) }
                    serviceManager.addFromCatalog(templates)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedIds.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400, height: 380)
    }
}

// MARK: - Appearance Tab

struct AppearanceSettingsView: View {
    @EnvironmentObject var serviceManager: ServiceManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Mode section
                VStack(alignment: .leading, spacing: 10) {
                    Text("MODE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)

                    Text("\"System\" follows your macOS appearance automatically.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    HStack(spacing: 16) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            AppearanceCard(
                                mode: mode,
                                isSelected: serviceManager.appearanceMode == mode
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    serviceManager.appearanceMode = mode
                                }
                            }
                        }
                    }
                }

                Divider()

                // Theme section
                VStack(alignment: .leading, spacing: 10) {
                    Text("THEME")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)

                    Text("Themes change the accent color and sidebar tint throughout ChatHarbor.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    // Standard themes
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ], spacing: 10) {
                        ForEach(ThemeCatalog.standardThemes) { theme in
                            ThemeCard(
                                theme: theme,
                                isSelected: serviceManager.selectedThemeId == theme.id
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    serviceManager.selectedThemeId = theme.id
                                }
                            }
                        }
                    }
                }

                Divider()

                // Seasonal themes
                VStack(alignment: .leading, spacing: 10) {
                    Text("SEASONAL")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ], spacing: 10) {
                        ForEach(ThemeCatalog.seasonalThemes) { theme in
                            ThemeCard(
                                theme: theme,
                                isSelected: serviceManager.selectedThemeId == theme.id
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    serviceManager.selectedThemeId = theme.id
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Theme Preview Card

struct ThemeCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                // Mini preview swatch showing sidebar + content area
                ZStack {
                    HStack(spacing: 0) {
                        // Sidebar preview
                        ZStack {
                            Rectangle().fill(theme.sidebarLight)
                            VStack(spacing: 3) {
                                ForEach(0..<3, id: \.self) { i in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(i == 0 ? theme.accentLight.opacity(0.7) : Color.gray.opacity(0.2))
                                        .frame(width: 20, height: 4)
                                }
                            }
                        }
                        .frame(width: 30)

                        // Content area
                        ZStack {
                            Rectangle().fill(Color.white)
                            VStack(spacing: 3) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(theme.accentLight.opacity(0.4))
                                    .frame(width: 36, height: 4)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.gray.opacity(0.15))
                                    .frame(width: 30, height: 3)
                            }
                        }
                    }

                    // Dark half overlay for split preview
                    HStack(spacing: 0) {
                        Color.clear
                        ZStack {
                            HStack(spacing: 0) {
                                ZStack {
                                    Rectangle().fill(theme.sidebarDark)
                                    VStack(spacing: 3) {
                                        ForEach(0..<3, id: \.self) { i in
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(i == 0 ? theme.accentDark.opacity(0.7) : Color.white.opacity(0.12))
                                                .frame(width: 20, height: 4)
                                        }
                                    }
                                }
                                .frame(width: 30)

                                ZStack {
                                    Rectangle().fill(Color(white: 0.15))
                                    VStack(spacing: 3) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(theme.accentDark.opacity(0.4))
                                            .frame(width: 36, height: 4)
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.white.opacity(0.08))
                                            .frame(width: 30, height: 3)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isSelected ? theme.accentLight : Color.gray.opacity(0.3),
                            lineWidth: isSelected ? 2.5 : 1
                        )
                )

                // Icon + name
                HStack(spacing: 4) {
                    Image(systemName: theme.icon)
                        .font(.system(size: 9))
                        .foregroundStyle(isSelected ? theme.accentLight : .secondary)

                    Text(theme.name)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct AppearanceCard: View {
    let mode: AppearanceMode
    let isSelected: Bool
    let action: () -> Void
    @EnvironmentObject var serviceManager: ServiceManager
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color {
        serviceManager.currentTheme.accentColor(for: colorScheme)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Preview swatch
                ZStack {
                    switch mode {
                    case .auto:
                        HStack(spacing: 0) {
                            Rectangle().fill(.white)
                            Rectangle().fill(Color(white: 0.15))
                        }
                    case .light:
                        Rectangle().fill(.white)
                    case .dark:
                        Rectangle().fill(Color(white: 0.15))
                    }

                    // Mini sidebar + content mockup
                    HStack(spacing: 0) {
                        VStack(spacing: 3) {
                            ForEach(0..<4, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(mode == .light ? Color.gray.opacity(0.25) : Color.white.opacity(0.15))
                                    .frame(width: 18, height: 4)
                            }
                        }
                        .frame(width: 28)
                        .padding(.vertical, 8)

                        Rectangle()
                            .fill(mode == .light ? Color.gray.opacity(0.08) : Color.white.opacity(0.05))
                    }
                }
                .frame(width: 80, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? accent : Color.gray.opacity(0.3), lineWidth: isSelected ? 2.5 : 1)
                )

                Text(mode.displayName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add Custom Service Sheet

struct AddCustomServiceSheet: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var urlString = "https://"
    @State private var selectedCategory = DefaultCategory.custom
    @State private var showingError = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Custom Service")
                .font(.headline)

            TextField("Service Name", text: $name)
                .textFieldStyle(.roundedBorder)

            TextField("URL (https://...)", text: $urlString)
                .textFieldStyle(.roundedBorder)

            Picker("Category", selection: $selectedCategory) {
                ForEach(serviceManager.categories, id: \.self) { category in
                    Text(category).tag(category)
                }
            }
            .pickerStyle(.menu)

            if showingError {
                Text("Please enter a valid name and URL starting with http:// or https://")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
                          let url = URL(string: urlString),
                          url.scheme == "http" || url.scheme == "https",
                          url.host != nil else {
                        showingError = true
                        return
                    }
                    serviceManager.addCustomService(name: name, urlString: urlString, category: selectedCategory)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

// MARK: - Notifications Tab

struct NotificationSettingsView: View {
    @EnvironmentObject var serviceManager: ServiceManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Global toggle
                VStack(alignment: .leading, spacing: 8) {
                    Text("GENERAL")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)

                    Toggle("Enable Notifications", isOn: $serviceManager.notificationSettings.globalEnabled)
                        .font(.system(size: 13))

                    Text("When disabled, all notifications from every service are suppressed.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Divider()

                // Display options
                VStack(alignment: .leading, spacing: 10) {
                    Text("DISPLAY")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)

                    Toggle("Show Banners", isOn: $serviceManager.notificationSettings.showBanners)
                        .font(.system(size: 13))
                        .disabled(!serviceManager.notificationSettings.globalEnabled)

                    Toggle("Play Sound", isOn: $serviceManager.notificationSettings.playSound)
                        .font(.system(size: 13))
                        .disabled(!serviceManager.notificationSettings.globalEnabled)

                    Toggle("Bounce Dock Icon", isOn: $serviceManager.notificationSettings.bounceDock)
                        .font(.system(size: 13))
                        .disabled(!serviceManager.notificationSettings.globalEnabled)

                    Toggle("Show Dock Badge Count", isOn: $serviceManager.notificationSettings.showDockBadge)
                        .font(.system(size: 13))
                        .disabled(!serviceManager.notificationSettings.globalEnabled)
                }
                .opacity(serviceManager.notificationSettings.globalEnabled ? 1.0 : 0.5)

                Divider()

                // Badge color
                VStack(alignment: .leading, spacing: 10) {
                    Text("BADGE COLOR")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        ForEach(BadgeColor.allCases, id: \.self) { color in
                            Button {
                                serviceManager.notificationSettings.badgeColor = color
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(color.color)
                                        .frame(width: 26, height: 26)

                                    if serviceManager.notificationSettings.badgeColor == color {
                                        Circle()
                                            .stroke(.primary, lineWidth: 2.5)
                                            .frame(width: 32, height: 32)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .help(color.displayName)
                        }
                    }

                    Text("Changes the color of notification badges in the sidebar.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Divider()

                // Per-service mute
                VStack(alignment: .leading, spacing: 10) {
                    Text("PER-SERVICE NOTIFICATIONS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)

                    if serviceManager.services.isEmpty {
                        Text("Add services to manage their notification settings.")
                            .font(.caption)
                            .foregroundStyle(.quaternary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(serviceManager.services) { service in
                            HStack(spacing: 10) {
                                Image(systemName: service.iconName)
                                    .font(.body)
                                    .frame(width: 22)
                                    .foregroundStyle(.secondary)

                                Text(service.name)
                                    .font(.system(size: 13))

                                Spacer()

                                Toggle("", isOn: Binding(
                                    get: { !serviceManager.isServiceMuted(service.id) },
                                    set: { _ in serviceManager.toggleMute(for: service.id) }
                                ))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .disabled(!serviceManager.notificationSettings.globalEnabled)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .opacity(serviceManager.notificationSettings.globalEnabled ? 1.0 : 0.5)
            }
            .padding(24)
        }
    }
}

// MARK: - Security Tab

struct SecuritySettingsView: View {
    @EnvironmentObject var serviceManager: ServiceManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Workspace Guard
                VStack(alignment: .leading, spacing: 10) {
                    Text("WORKSPACE GUARD")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)

                    Toggle("Enable Workspace Guard", isOn: $serviceManager.notificationSettings.workspaceGuardEnabled)
                        .font(.system(size: 13))

                    Text("When switching from a personal chat to a workspace service, ChatHarbor can clear your clipboard and show a warning to prevent accidental cross-contamination of copied content.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    Group {
                        Toggle("Clear Clipboard on Transition", isOn: $serviceManager.notificationSettings.workspaceGuardClearClipboard)
                            .font(.system(size: 13))

                        Toggle("Show Warning Banner", isOn: $serviceManager.notificationSettings.workspaceGuardShowWarning)
                            .font(.system(size: 13))
                    }
                    .disabled(!serviceManager.notificationSettings.workspaceGuardEnabled)
                    .opacity(serviceManager.notificationSettings.workspaceGuardEnabled ? 1.0 : 0.5)

                    // Workspace category picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Workspace Categories")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)

                        Text("Select which categories are treated as workspace zones.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        ForEach(serviceManager.categories, id: \.self) { category in
                            HStack(spacing: 8) {
                                Toggle("", isOn: Binding(
                                    get: {
                                        serviceManager.notificationSettings.workspaceCategories.contains(category)
                                    },
                                    set: { on in
                                        if on {
                                            serviceManager.notificationSettings.workspaceCategories.insert(category)
                                        } else {
                                            serviceManager.notificationSettings.workspaceCategories.remove(category)
                                        }
                                    }
                                ))
                                .labelsHidden()
                                .toggleStyle(.checkbox)

                                Text(category)
                                    .font(.system(size: 13))
                            }
                        }
                    }
                    .disabled(!serviceManager.notificationSettings.workspaceGuardEnabled)
                    .opacity(serviceManager.notificationSettings.workspaceGuardEnabled ? 1.0 : 0.5)
                }

                Divider()

                // Privacy Shield
                VStack(alignment: .leading, spacing: 10) {
                    Text("PRIVACY SHIELD")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)

                    Toggle("Enable Privacy Shield", isOn: $serviceManager.notificationSettings.privacyShieldEnabled)
                        .font(.system(size: 13))

                    Text("When your screen is being shared, recorded, or remotely viewed, ChatHarbor automatically blurs your chat content to keep sensitive conversations private.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    Group {
                        Toggle("Auto-detect screen sharing", isOn: $serviceManager.notificationSettings.privacyShieldAutoDetect)
                            .font(.system(size: 13))

                        Toggle("Blur Chat Content", isOn: $serviceManager.notificationSettings.privacyShieldBlurContent)
                            .font(.system(size: 13))

                        Toggle("Show Warning Overlay", isOn: $serviceManager.notificationSettings.privacyShieldShowWarning)
                            .font(.system(size: 13))
                    }
                    .disabled(!serviceManager.notificationSettings.privacyShieldEnabled)
                    .opacity(serviceManager.notificationSettings.privacyShieldEnabled ? 1.0 : 0.5)

                    if serviceManager.notificationSettings.privacyShieldEnabled && !serviceManager.notificationSettings.privacyShieldAutoDetect {
                        Text("Auto-detection is off. Use ⌘⇧P to manually engage the shield.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.top, 2)
                    }

                    // Keyboard shortcut info
                    HStack(spacing: 10) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Manual Toggle: ⌘⇧P")
                                .font(.system(size: 12, weight: .medium))
                            Text("Use this shortcut to engage the shield when sharing your screen through a browser (e.g. Google Meet in Safari or Chrome), which can't be detected automatically.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.quaternary.opacity(0.3))
                    )
                    .disabled(!serviceManager.notificationSettings.privacyShieldEnabled)
                    .opacity(serviceManager.notificationSettings.privacyShieldEnabled ? 1.0 : 0.5)

                    // Detection capabilities
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AUTO-DETECTION")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 4)

                        Label("Screen sharing apps (Zoom, Teams, Discord, etc.)", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Label("Screen recording tools (QuickTime, OBS, Loom, etc.)", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Label("AirPlay and display mirroring", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Label("Remote desktop (TeamViewer, AnyDesk, etc.)", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Label("Browser-based sharing — use ⌘⇧P", systemImage: "keyboard")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .disabled(!serviceManager.notificationSettings.privacyShieldEnabled)
                    .opacity(serviceManager.notificationSettings.privacyShieldEnabled ? 1.0 : 0.5)
                }
            }
            .padding(24)
        }
    }
}

// MARK: - About Tab

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image("ChatHarborLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

            Text("ChatHarbor")
                .font(.title)
                .fontWeight(.bold)

            Text("Version 1.0.1")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("A lightweight, native macOS chat aggregator.\nBuilt with SwiftUI and WebKit.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Link(destination: URL(string: "https://d-edgar.github.io/chatharbor-site/bug-report.html")!) {
                Label("Report a Bug", systemImage: "ladybug")
                    .font(.caption)
            }
            .padding(.top, 8)

            HStack(spacing: 16) {
                Link("Privacy Policy", destination: URL(string: "https://d-edgar.github.io/chatharbor-site/privacy.html")!)
                    .font(.caption)
                Link("Terms of Use", destination: URL(string: "https://d-edgar.github.io/chatharbor-site/terms.html")!)
                    .font(.caption)
            }
            .padding(.top, 4)

            Text("MIT License")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
