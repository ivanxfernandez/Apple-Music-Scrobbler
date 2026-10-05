import AppKit
import CryptoKit
import ScrobblerCore

/// One-click updates: downloads the new release, checks it against the SHA-256 GitHub publishes,
/// swaps it in for the running app and restarts. When anything doesn't check out, nothing is
/// changed and the release page opens instead, so the user can update by hand.
@MainActor
final class Updater {
    struct Failure: Error, CustomStringConvertible { let description: String }

    private(set) var installing = false

    /// The running app, or nil when it can't replace itself (and why).
    static func installLocation() -> Result<URL, Failure> {
        let app = Bundle.main.bundleURL
        guard app.pathExtension == "app" else { return .failure(Failure(description: L("not running as an app"))) }
        // Opened straight from Downloads, macOS runs a read-only copy ("App Translocation").
        if app.path.contains("/AppTranslocation/") {
            return .failure(Failure(description: L("the app is running from a temporary copy; move it to Applications first")))
        }
        guard FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path) else {
            return .failure(Failure(description: L("no permission to replace the app in %@", app.deletingLastPathComponent().path)))
        }
        return .success(app)
    }

    /// Downloads and installs the release, then quits so the helper can swap the app and reopen it.
    /// Calls `fallback` (open the release page) if it can't.
    func install(_ release: ReleaseInfo, fallback: @escaping () -> Void) {
        guard !installing else { return }
        installing = true
        Task {
            do {
                try await installNow(release)
            } catch {
                installing = false
                Log.write("Update to \(release.tag) failed: \(error)")
                Notifier.shared.show(L("Couldn't install the update"), L("%@. Opening the download page instead.", "\(error)"))
                fallback()
            }
        }
    }

    private func installNow(_ release: ReleaseInfo) async throws {
        guard let asset = release.download else { throw Failure(description: L("this release has no checked download for Mac")) }
        let current = try Self.installLocation().get()

        Log.write("Downloading \(release.tag)...")
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("AppleMusicScrobbler-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let (downloaded, response) = try await Http.download(asset.url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure(description: L("the download failed")) }
        let zip = work.appendingPathComponent(asset.name)
        try FileManager.default.moveItem(at: downloaded, to: zip)

        let hash = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
        guard hash == asset.sha256 else { throw Failure(description: L("the download doesn't match the published SHA-256")) }

        let unpacked = work.appendingPathComponent("unpacked")
        try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])
        let new = unpacked.appendingPathComponent(current.lastPathComponent)
        guard let info = Bundle(url: new)?.infoDictionary,
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              let version = AppVersion(info["CFBundleShortVersionString"] as? String ?? ""), version == release.version
        else { throw Failure(description: L("the download isn't the expected app")) }
        try Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", new.path])
        // The browser marks downloads as quarantined, URLSession doesn't. Clear it in case, the way
        // Sparkle does for updates it installs, so the new version opens without the Gatekeeper prompt.
        _ = try? Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", new.path])

        // A helper swaps the bundles once this process has quit, then opens the new version.
        let script = work.appendingPathComponent("install.sh")
        try """
            #!/bin/sh
            # Waits for the app to quit, swaps in the new version and opens it. Puts the old one back if the swap fails.
            pid="$1"; old="$2"; new="$3"; work="$4"
            for i in $(seq 1 100); do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
            backup="$old.updating"
            rm -rf "$backup"
            if mv "$old" "$backup" && mv "$new" "$old"; then
                rm -rf "$backup"
            elif [ -d "$backup" ] && [ ! -d "$old" ]; then
                mv "$backup" "$old"
            fi
            open "$old"
            rm -rf "$work"
            """.write(to: script, atomically: true, encoding: .utf8)
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        helper.arguments = ["/bin/sh", script.path, String(getpid()), current.path, new.path, work.path]
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()

        Log.write("Installing \(release.tag) and restarting")
        NSApp.terminate(nil)
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw Failure(description: "\((tool as NSString).lastPathComponent) failed: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return output
    }
}
