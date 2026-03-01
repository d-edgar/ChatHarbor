import SwiftUI

// MARK: - App Theme

struct AppTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String            // SF Symbol name
    let accentLight: Color      // Accent color in light mode
    let accentDark: Color       // Accent color in dark mode
    let sidebarLight: Color     // Sidebar background tint in light mode
    let sidebarDark: Color      // Sidebar background tint in dark mode
    let isSeasonal: Bool

    /// Resolve the accent color based on the current color scheme
    func accentColor(for scheme: ColorScheme) -> Color {
        scheme == .dark ? accentDark : accentLight
    }

    /// Resolve the sidebar tint based on the current color scheme
    func sidebarColor(for scheme: ColorScheme) -> Color {
        scheme == .dark ? sidebarDark : sidebarLight
    }

    static func == (lhs: AppTheme, rhs: AppTheme) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Theme Catalog

enum ThemeCatalog {
    // Standard themes
    static let defaultTheme = AppTheme(
        id: "default",
        name: "Default",
        icon: "circle.lefthalf.filled",
        accentLight: Color(red: 0.20, green: 0.47, blue: 0.96),   // System blue
        accentDark: Color(red: 0.25, green: 0.52, blue: 1.0),
        sidebarLight: Color(white: 0.97),
        sidebarDark: Color(white: 0.12),
        isSeasonal: false
    )

    static let ocean = AppTheme(
        id: "ocean",
        name: "Ocean",
        icon: "water.waves",
        accentLight: Color(red: 0.00, green: 0.55, blue: 0.65),   // Teal
        accentDark: Color(red: 0.15, green: 0.70, blue: 0.80),
        sidebarLight: Color(red: 0.93, green: 0.97, blue: 0.98),
        sidebarDark: Color(red: 0.06, green: 0.12, blue: 0.16),
        isSeasonal: false
    )

    static let forest = AppTheme(
        id: "forest",
        name: "Forest",
        icon: "leaf.fill",
        accentLight: Color(red: 0.20, green: 0.60, blue: 0.30),   // Green
        accentDark: Color(red: 0.30, green: 0.75, blue: 0.40),
        sidebarLight: Color(red: 0.94, green: 0.97, blue: 0.94),
        sidebarDark: Color(red: 0.07, green: 0.13, blue: 0.08),
        isSeasonal: false
    )

    static let sunset = AppTheme(
        id: "sunset",
        name: "Sunset",
        icon: "sun.horizon.fill",
        accentLight: Color(red: 0.90, green: 0.40, blue: 0.20),   // Warm orange
        accentDark: Color(red: 1.0, green: 0.55, blue: 0.30),
        sidebarLight: Color(red: 0.99, green: 0.96, blue: 0.93),
        sidebarDark: Color(red: 0.16, green: 0.10, blue: 0.06),
        isSeasonal: false
    )

    static let berry = AppTheme(
        id: "berry",
        name: "Berry",
        icon: "heart.fill",
        accentLight: Color(red: 0.68, green: 0.18, blue: 0.55),   // Purple-pink
        accentDark: Color(red: 0.82, green: 0.35, blue: 0.70),
        sidebarLight: Color(red: 0.98, green: 0.94, blue: 0.97),
        sidebarDark: Color(red: 0.14, green: 0.07, blue: 0.12),
        isSeasonal: false
    )

    static let slate = AppTheme(
        id: "slate",
        name: "Slate",
        icon: "square.stack.fill",
        accentLight: Color(red: 0.40, green: 0.45, blue: 0.52),   // Cool gray
        accentDark: Color(red: 0.60, green: 0.65, blue: 0.72),
        sidebarLight: Color(red: 0.95, green: 0.95, blue: 0.96),
        sidebarDark: Color(red: 0.11, green: 0.12, blue: 0.13),
        isSeasonal: false
    )

    // Seasonal themes
    static let spring = AppTheme(
        id: "spring",
        name: "Spring",
        icon: "camera.macro",
        accentLight: Color(red: 0.85, green: 0.40, blue: 0.55),   // Cherry blossom pink
        accentDark: Color(red: 0.95, green: 0.55, blue: 0.68),
        sidebarLight: Color(red: 0.97, green: 0.95, blue: 0.96),
        sidebarDark: Color(red: 0.13, green: 0.09, blue: 0.11),
        isSeasonal: true
    )

    static let summer = AppTheme(
        id: "summer",
        name: "Summer",
        icon: "sun.max.fill",
        accentLight: Color(red: 0.95, green: 0.65, blue: 0.10),   // Golden yellow
        accentDark: Color(red: 1.0, green: 0.78, blue: 0.25),
        sidebarLight: Color(red: 0.99, green: 0.98, blue: 0.93),
        sidebarDark: Color(red: 0.14, green: 0.12, blue: 0.06),
        isSeasonal: true
    )

    static let autumn = AppTheme(
        id: "autumn",
        name: "Autumn",
        icon: "leaf.arrow.circlepath",
        accentLight: Color(red: 0.78, green: 0.35, blue: 0.12),   // Burnt amber
        accentDark: Color(red: 0.90, green: 0.50, blue: 0.25),
        sidebarLight: Color(red: 0.98, green: 0.96, blue: 0.93),
        sidebarDark: Color(red: 0.14, green: 0.10, blue: 0.07),
        isSeasonal: true
    )

    static let winter = AppTheme(
        id: "winter",
        name: "Winter",
        icon: "snowflake",
        accentLight: Color(red: 0.35, green: 0.55, blue: 0.75),   // Ice blue
        accentDark: Color(red: 0.50, green: 0.72, blue: 0.90),
        sidebarLight: Color(red: 0.95, green: 0.97, blue: 0.99),
        sidebarDark: Color(red: 0.08, green: 0.10, blue: 0.15),
        isSeasonal: true
    )

    /// All standard (non-seasonal) themes
    static let standardThemes: [AppTheme] = [
        defaultTheme, ocean, forest, sunset, berry, slate
    ]

    /// All seasonal themes
    static let seasonalThemes: [AppTheme] = [
        spring, summer, autumn, winter
    ]

    /// Every available theme
    static let allThemes: [AppTheme] = standardThemes + seasonalThemes

    /// Find a theme by its ID, falling back to default
    static func theme(forId id: String) -> AppTheme {
        allThemes.first(where: { $0.id == id }) ?? defaultTheme
    }
}
