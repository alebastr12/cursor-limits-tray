import Foundation
import CryptoKit

struct UpdateRelease {
    let version: String
    let zipURL: URL?
    let checksumURL: URL?
    let dmgURL: URL?
    let pageURL: URL?
    let notes: String
}

enum UpdateError: LocalizedError {
    case noAsset
    case download
    case checksumMissing
    case checksumMismatch
    case unzip
    case invalidVersion
    case permissions

    var errorDescription: String? {
        switch self {
        case .noAsset: return L10n.tr("update.no_asset")
        case .download: return L10n.tr("update.download_failed")
        case .checksumMissing: return L10n.tr("update.checksum_missing")
        case .checksumMismatch: return L10n.tr("update.checksum_mismatch")
        case .unzip: return L10n.tr("update.unzip_failed")
        case .invalidVersion: return L10n.tr("update.invalid_version")
        case .permissions: return L10n.tr("update.permissions")
        }
    }
}

enum UpdateService {
    private static let repo = "alebastr12/cursor-limits-tray"

    /// Test seam.
    static var currentVersionOverride: String?

    static var currentVersion: String {
        if let currentVersionOverride { return currentVersionOverride }
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func latestRelease() async throws -> UpdateRelease? {
        guard let current = AppVersion(currentVersion) else { return nil }

        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TrayAILimits/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let object = try await HTTPClient.json(for: request)
        guard let json = object as? [String: Any],
              let tag = json["tag_name"] as? String,
              let latest = AppVersion(tag),
              latest > current
        else { return nil }

        let version = latest.description
        let assets = (json["assets"] as? [[String: Any]]) ?? []

        func assetURL(_ name: String) -> URL? {
            guard let asset = assets.first(where: { ($0["name"] as? String) == name }),
                  let value = asset["browser_download_url"] as? String
            else { return nil }
            return URL(string: value)
        }

        let zip = assetURL("TrayAILimits-\(version).zip")
        let dmg = assetURL("TrayAILimits-\(version).dmg")
        guard zip != nil || dmg != nil else { throw UpdateError.noAsset }

        return UpdateRelease(
            version: version,
            zipURL: zip,
            checksumURL: assetURL("SHA256SUMS-\(version).txt"),
            dmgURL: dmg,
            pageURL: (json["html_url"] as? String).flatMap(URL.init(string:)),
            notes: (json["body"] as? String) ?? ""
        )
    }
}

enum UpdateInstaller {
    static func install(_ release: UpdateRelease) async throws {
        guard let zipURL = release.zipURL else { throw UpdateError.noAsset }

        let fm = FileManager.default
        let work = fm.temporaryDirectory
            .appendingPathComponent("TrayAILimits-update-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)

        let zipFile = work.appendingPathComponent("update.zip")
        let (zipData, zipResponse) = try await HTTPClient.data(for: URLRequest(url: zipURL))
        guard zipResponse.statusCode == 200 else { throw UpdateError.download }
        try zipData.write(to: zipFile)

        if let checksumURL = release.checksumURL {
            let (sumData, sumResponse) = try await HTTPClient.data(for: URLRequest(url: checksumURL))
            guard sumResponse.statusCode == 200 else { throw UpdateError.download }
            let sums = String(data: sumData, encoding: .utf8) ?? ""
            guard let expected = parseChecksum(sums, assetName: zipURL.lastPathComponent) else {
                throw UpdateError.checksumMissing
            }
            let actual = SHA256.hash(data: zipData).map { String(format: "%02x", $0) }.joined()
            guard expected.lowercased() == actual.lowercased() else {
                throw UpdateError.checksumMismatch
            }
        } else {
            throw UpdateError.checksumMissing
        }

        let staging = work.appendingPathComponent("staging", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", zipFile.path, staging.path])

        let newApp = staging.appendingPathComponent("TrayAILimits.app", isDirectory: true)
        guard fm.fileExists(atPath: newApp.path) else { throw UpdateError.unzip }

        let plistURL = newApp.appendingPathComponent("Contents/Info.plist")
        if let plist = NSDictionary(contentsOf: plistURL),
           let version = plist["CFBundleShortVersionString"] as? String,
           AppVersion(version) != AppVersion(release.version) {
            throw UpdateError.invalidVersion
        }

        let destination = try destinationURL()
        guard fm.isWritableFile(atPath: destination.deletingLastPathComponent().path) else {
            throw UpdateError.permissions
        }

        try installScript(in: work, destination: destination, newApp: newApp)
    }

    /// Parse `SHA256SUMS` lines (`<hash>  <file>`).
    static func parseChecksum(_ text: String, assetName: String) -> String? {
        for line in text.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2 else { continue }
            if parts.last.map(String.init) == assetName {
                return String(parts[0])
            }
        }
        return nil
    }

    private static func destinationURL() throws -> URL {
        let fm = FileManager.default
        let current = Bundle.main.bundleURL
        let installed = URL(fileURLWithPath: "/Applications/TrayAILimits.app", isDirectory: true)
        let homeInstalled = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/TrayAILimits.app", isDirectory: true)

        // Running from a DMG or a Gatekeeper-translocated copy: update the real
        // installed app, never the read-only/temporary bundle.
        if current.path.hasPrefix("/Volumes/") || current.path.contains("/AppTranslocation/") {
            if fm.fileExists(atPath: installed.path) { return installed }
            if fm.fileExists(atPath: homeInstalled.path) { return homeInstalled }
            if fm.isWritableFile(atPath: "/Applications") { return installed }
            try fm.createDirectory(
                at: homeInstalled.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            return homeInstalled
        }
        return current
    }

    private static func installScript(in work: URL, destination: URL, newApp: URL) throws {
        let scriptURL = work.appendingPathComponent("update.sh")
        let script = """
        #!/bin/bash
        set -u
        PID="$1"
        DEST="$2"
        NEW="$3"
        STAGE="$4"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.3; done
        BACKUP="${DEST}.old"
        rm -rf "$BACKUP"
        if [ -e "$DEST" ]; then
          if ! mv "$DEST" "$BACKUP" 2>/dev/null; then
            open "$DEST"
            exit 1
          fi
        fi
        if /usr/bin/ditto "$NEW" "$DEST"; then
          /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
          rm -rf "$BACKUP"
          open "$DEST"
        else
          rm -rf "$DEST"
          if [ -e "$BACKUP" ]; then
            mv "$BACKUP" "$DEST"
            open "$DEST"
          fi
        fi
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let logURL = URL(fileURLWithPath: "/tmp/TrayAILimits-update.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            scriptURL.path,
            String(ProcessInfo.processInfo.processIdentifier),
            destination.path,
            newApp.path,
            work.path
        ]
        process.standardOutput = log
        process.standardError = log
        try process.run()
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.unzip }
    }
}
