import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isExpanded: Bool
    @State private var showingAboutPopover = false

    /// Flat list of enabled services so we can assign Cmd+1, Cmd+2, etc.
    private var indexedServices: [(index: Int, service: ChatService)] {
        serviceManager.enabledServices.enumerated().map { ($0.offset, $0.element) }
    }

    /// Look up the shortcut number (1-9) for a service, or nil if > 9
    private func shortcutNumber(for service: ChatService) -> Int? {
        guard let idx = indexedServices.first(where: { $0.service.id == service.id })?.index,
              idx < 9 else { return nil }
        return idx + 1
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header (clickable to go home, only shown when expanded)
            if isExpanded {
                HStack {
                    Button {
                        serviceManager.selectedServiceId = nil
                    } label: {
                        HStack(spacing: 6) {
                            Image("ChatHarborLogo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20)
                                .clipShape(RoundedRectangle(cornerRadius: 4))

                            Text("ChatHarbor")
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Go to home screen")

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Collapse sidebar")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
            } else {
                // Compact: just the toggle button, no logo
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Expand sidebar")
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
            }

            Divider()

            // MARK: - Service List
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(serviceManager.categories, id: \.self) { category in
                        let servicesInCategory = serviceManager.enabledServices(inCategory: category)
                        if !servicesInCategory.isEmpty {
                            if isExpanded {
                                HStack {
                                    Text(category.uppercased())
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.top, 12)
                                .padding(.bottom, 4)
                            } else {
                                let firstNonEmpty = serviceManager.categories.first { cat in
                                    !serviceManager.enabledServices(inCategory: cat).isEmpty
                                }
                                if category != firstNonEmpty {
                                    Divider()
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                }
                            }

                            ForEach(servicesInCategory) { service in
                                let shortcut = shortcutNumber(for: service)
                                if isExpanded {
                                    ExpandedServiceRow(
                                        service: service,
                                        isSelected: serviceManager.selectedServiceId == service.id,
                                        shortcutNumber: shortcut
                                    ) {
                                        serviceManager.selectService(service.id)
                                    }
                                } else {
                                    CompactServiceRow(
                                        service: service,
                                        isSelected: serviceManager.selectedServiceId == service.id,
                                        shortcutNumber: shortcut
                                    ) {
                                        serviceManager.selectService(service.id)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Spacer(minLength: 0)

            Divider()

            // MARK: - Footer: Settings + About
            VStack(spacing: 0) {
                if isExpanded {
                    // Settings button
                    SettingsLink {
                        HStack(spacing: 8) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 13))
                                .frame(width: 22, height: 22)
                                .foregroundStyle(.secondary)

                            Text("Settings")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Open Settings")

                    Divider()
                        .padding(.horizontal, 14)

                    // About button
                    Button {
                        showingAboutPopover.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            Image("ChatHarborLogo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 22, height: 22)
                                .clipShape(RoundedRectangle(cornerRadius: 5))

                            Text("About")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text("v1.0.0")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .help("About ChatHarbor")
                    .popover(isPresented: $showingAboutPopover, arrowEdge: .trailing) {
                        AboutPopoverView()
                    }
                } else {
                    // Compact: just a settings gear
                    SettingsLink {
                        Image(systemName: "gearshape")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Open Settings")
                }
            }
            .padding(.bottom, 4)
        }
        .frame(width: isExpanded ? 200 : 52)
        .background(serviceManager.currentTheme.sidebarColor(for: colorScheme))
    }
}

// MARK: - Expanded Service Row

struct ExpandedServiceRow: View {
    let service: ChatService
    let isSelected: Bool
    var shortcutNumber: Int?
    let action: () -> Void
    @EnvironmentObject var serviceManager: ServiceManager
    @Environment(\.colorScheme) private var colorScheme

    private var badgeColor: Color {
        serviceManager.notificationSettings.badgeColor.color
    }

    private var themeAccent: Color {
        serviceManager.currentTheme.accentColor(for: colorScheme)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: service.iconName)
                        .font(.system(size: 15))
                        .frame(width: 26, height: 26)
                        .foregroundStyle(isSelected ? themeAccent : .secondary)

                    if service.notificationCount > 0 {
                        Circle()
                            .fill(badgeColor)
                            .frame(width: 8, height: 8)
                            .offset(x: 4, y: -4)
                    }
                }

                Text(service.name)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)

                Spacer()

                if service.notificationCount > 0 {
                    Text("\(service.notificationCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeColor, in: Capsule())
                } else if let num = shortcutNumber {
                    Text("⌘\(num)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.quaternary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isSelected
                    ? AnyShapeStyle(themeAccent.opacity(0.15))
                    : AnyShapeStyle(.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }
}

// MARK: - Compact Service Row (icon only)

struct CompactServiceRow: View {
    let service: ChatService
    let isSelected: Bool
    var shortcutNumber: Int?
    let action: () -> Void
    @EnvironmentObject var serviceManager: ServiceManager
    @Environment(\.colorScheme) private var colorScheme

    private var badgeColor: Color {
        serviceManager.notificationSettings.badgeColor.color
    }

    private var themeAccent: Color {
        serviceManager.currentTheme.accentColor(for: colorScheme)
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: service.iconName)
                    .font(.system(size: 17))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(isSelected ? themeAccent : .secondary)
                    .background(
                        isSelected
                            ? AnyShapeStyle(themeAccent.opacity(0.15))
                            : AnyShapeStyle(.clear)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if service.notificationCount > 0 {
                    Circle()
                        .fill(badgeColor)
                        .frame(width: 9, height: 9)
                        .offset(x: 2, y: -2)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .help(service.name + (shortcutNumber != nil ? " (⌘\(shortcutNumber!))" : "")
              + (service.notificationCount > 0 ? " — \(service.notificationCount) unread" : ""))
    }
}

// MARK: - About Popover

struct AboutPopoverView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 12) {
            Image("ChatHarborLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 3, y: 2)

            Text("ChatHarbor")
                .font(.headline)

            Text("Version 1.0.0")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            VStack(spacing: 6) {
                Text("Developed by David Edgar")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("A lightweight, native macOS chat aggregator.\nBuilt with SwiftUI and WebKit.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

            Divider()

            VStack(spacing: 4) {
                Button {
                    openURL(URL(string: "https://github.com/d-edgar/ChatHarbor/releases")!)
                } label: {
                    Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())

                Button {
                    openURL(URL(string: "https://github.com/d-edgar/ChatHarbor")!)
                } label: {
                    Label("View on GitHub", systemImage: "link")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())

                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString("https://github.com/d-edgar/ChatHarbor", forType: .string)
                } label: {
                    Label("Copy Share Link", systemImage: "square.on.square")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            }

            Divider()

            Button {
                openURL(URL(string: "https://d-edgar.github.io/chatharbor-site/bug-report.html")!)
            } label: {
                Label("Report a Bug", systemImage: "ladybug")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())

            Divider()

            HStack(spacing: 12) {
                Button {
                    openURL(URL(string: "https://d-edgar.github.io/chatharbor-site/privacy.html")!)
                } label: {
                    Text("Privacy Policy")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    openURL(URL(string: "https://d-edgar.github.io/chatharbor-site/terms.html")!)
                } label: {
                    Text("Terms of Use")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text("MIT License")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 240)
    }
}

