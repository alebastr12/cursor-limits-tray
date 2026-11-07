import AppKit
import SwiftUI

@MainActor
enum SnapshotExporter {
    static func writeDemoMain(to path: String) {
        write(view: SnapshotCanvas(snapshot: .demo, showConnectChatGPT: false), size: NSSize(width: 360, height: 480), to: path)
    }

    static func writeLiveMain(to path: String) async {
        let poller = UsagePoller()
        _ = await poller.autoConnectChatGPTIfNeeded()
        await poller.refresh()
        var snap = poller.snapshot
        let showConnect = snap.chatGPT.rows.isEmpty
        if snap.cursor.rows.isEmpty && snap.chatGPT.rows.isEmpty {
            snap = .demo
        }
        write(
            view: SnapshotCanvas(snapshot: snap, showConnectChatGPT: showConnect),
            size: NSSize(width: 360, height: 480),
            to: path
        )
    }

    static func writeSettings(to path: String, cursorOK: Bool, chatOK: Bool) {
        write(
            view: SettingsSnapshotCanvas(cursorOK: cursorOK, chatOK: chatOK),
            size: NSSize(width: 480, height: 420),
            to: path
        )
    }

    private static func write<V: View>(view: V, size: NSSize, to path: String) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderBack(nil)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            fputs("SnapshotExporter: no bitmap rep\n", stderr)
            window.close()
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.close()

        guard let png = rep.representation(using: .png, properties: [:]) else {
            fputs("SnapshotExporter: PNG encode failed\n", stderr)
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: path).deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try png.write(to: URL(fileURLWithPath: path))
            fputs("Wrote snapshot \(path)\n", stderr)
        } catch {
            fputs("SnapshotExporter write error: \(error)\n", stderr)
        }
    }
}
