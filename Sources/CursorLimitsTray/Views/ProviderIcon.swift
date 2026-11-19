import AppKit

/// Loads the provider template glyphs used by both the menu bar and the popover.
enum ProviderIcon {
    static func template(for provider: MenuBarSegment.Provider) -> NSImage? {
        if let image = loadPNG(named: provider.resourceName) {
            image.isTemplate = true
            return image
        }
        guard let symbol = provider.fallbackSymbolName,
              let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    private static func loadPNG(named: String) -> NSImage? {
        let bundle = Bundle.main
        let candidates: [URL?] = [
            bundle.url(forResource: named + "@2x", withExtension: "png", subdirectory: "MenuBarProviders"),
            bundle.url(forResource: named, withExtension: "png", subdirectory: "MenuBarProviders"),
            bundle.url(forResource: named + "@2x", withExtension: "png"),
            bundle.url(forResource: named, withExtension: "png"),
            URL(fileURLWithPath: bundle.bundlePath + "/Contents/Resources/MenuBarProviders/\(named)@2x.png"),
            URL(fileURLWithPath: bundle.bundlePath + "/Contents/Resources/MenuBarProviders/\(named).png")
        ]
        for case let url? in candidates {
            if let image = NSImage(contentsOf: url), image.isValid {
                return image
            }
        }
        return nil
    }
}
