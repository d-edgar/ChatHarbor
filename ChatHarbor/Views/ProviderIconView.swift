import SwiftUI

// MARK: - Provider Icon View
//
// Renders the correct icon for a provider — custom asset from the catalog
// if available, SF Symbol fallback otherwise. Supports template rendering
// so icons adopt the surrounding foregroundStyle.

struct ProviderIconView: View {
    let providerId: String
    /// Fallback SF Symbol name (from provider.iconName)
    let sfSymbolFallback: String

    var body: some View {
        if let assetName = ProviderIcon.customAssetName(for: providerId) {
            Image(assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: sfSymbolFallback)
        }
    }
}

// MARK: - Convenience initializer from providerInfo

extension ProviderIconView {
    /// Create from a provider's icon name and ID
    init(for providerId: String, fallback: String) {
        self.providerId = providerId
        self.sfSymbolFallback = fallback
    }
}
