import SwiftUI

/// Compact live title — provider template icon + every live % for connected providers.
struct MenuBarLabel: View {
    @ObservedObject var poller: UsagePoller

    var body: some View {
        HStack(spacing: 4) {
            if poller.menuBarSegments.isEmpty {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(poller.menuBarSegments.enumerated()), id: \.offset) { index, segment in
                    let previous = index > 0 ? poller.menuBarSegments[index - 1] : nil
                    let isNewProvider = previous.map { $0.provider != segment.provider } ?? true

                    if index > 0 {
                        if isNewProvider {
                            Text("·")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 2) {
                        if isNewProvider, let ns = loadTemplate(segment.provider.resourceName) {
                            Image(nsImage: ns)
                                .resizable()
                                .renderingMode(.template)
                                .frame(width: 15, height: 15)
                        }
                        Text("\(segment.remainingPercent)%")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(segment.severity.color)
                }
            }
        }
        .accessibilityLabel(
            poller.menuBarSegments.isEmpty
                ? L10n.tr("a11y.menubar_empty")
                : poller.menuBarSegments.map {
                    L10n.tr("a11y.menubar_item", $0.provider.accessibilityName, $0.remainingPercent)
                }.joined(separator: ", ")
        )
    }

    private func loadTemplate(_ name: String) -> NSImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "MenuBarProviders"),
           let img = NSImage(contentsOf: url) {
            img.isTemplate = true
            return img
        }
        let path = Bundle.main.bundlePath + "/Contents/Resources/MenuBarProviders/\(name).png"
        if let img = NSImage(contentsOfFile: path) {
            img.isTemplate = true
            return img
        }
        return nil
    }
}
