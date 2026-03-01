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

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 560, height: 520)
    }
}

// MARK: - Services Tab

struct ServicesSettingsView: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @State private var showingAddService = false
    @State private var showingAddCategory = false
    @State private var showingCatalog = false
    @State private var showingResetConfirm = false
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
    }
}

// MARK: - Category Zone (drop target)

struct CategoryZoneView: View {
    let category: String
    @EnvironmentObject var serviceManager: ServiceManager
    @Binding var draggingServiceId: String?
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            // Category header
            HStack(spacing: 8) {
                if isRenaming {
                    TextField("Category name", text: $renameText, onCommit: {
                        serviceManager.renameCategory(from: category, to: renameText)
                        isRenaming = false
                    })
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: 160)

                    Button("Save") {
                        serviceManager.renameCategory(from: category, to: renameText)
                        isRenaming = false
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
                                serviceManager.removeCategory(named: category)
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
                    .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color.clear,
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
                serviceManager.removeService(service)
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
        VStack(spacing: 20) {
            Image(systemName: "paintbrush.fill")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("Appearance")
                .font(.headline)

            Text("Choose how ChatHarbor looks. \"System\" follows your macOS appearance automatically.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            // Theme picker cards
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
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AppearanceCard: View {
    let mode: AppearanceMode
    let isSelected: Bool
    let action: () -> Void

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
                        .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isSelected ? 2.5 : 1)
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

            Text("Version 1.0.0")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("A lightweight, native macOS chat aggregator.\nBuilt with SwiftUI and WebKit.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Link("View on GitHub", destination: URL(string: "https://github.com/d-edgar/ChatHarbor")!)
                .padding(.top, 4)

            Text("MIT License")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
