import AppKit
import ScrobblerCore

/// Offers to move the app into Applications when it was opened from somewhere else (usually
/// Downloads), then reopens it from there. From Applications it can update itself and start at
/// login; opened from Downloads, macOS may run it from a temporary read-only copy.
@MainActor
enum AppMover {
    /// True if the app is somewhere it should offer to move from (release builds only).
    static var shouldOffer: Bool {
        let path = Bundle.main.bundleURL.path
        return !AppInfo.gitHubRepo.isEmpty && Bundle.main.bundleURL.pathExtension == "app" && !AppLocation.isInApplications(path)
    }

    /// Asks once (unless `force`), and moves and relaunches if the user agrees. Returns true if the app is relaunching.
    @discardableResult
    static func offer(settings: Settings, force: Bool = false) -> Bool {
        guard shouldOffer, force || !settings.declinedMoveToApplications else { return false }
        let alert = NSAlert()
        alert.messageText = L("Move to the Applications folder?")
        alert.informativeText = L("Apple Music Scrobbler can update itself and start when you log in only from the Applications folder. It will move there and reopen.")
        alert.addButton(withTitle: L("Move to Applications"))
        alert.addButton(withTitle: L("Not Now"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            settings.declinedMoveToApplications = true
            return false
        }
        do {
            try moveAndRelaunch()
            return true
        } catch {
            Log.write("Couldn't move the app to Applications: \(error)")
            let failed = NSAlert()
            failed.messageText = L("Couldn't move the app")
            failed.informativeText = L("Drag Apple Music Scrobbler into the Applications folder in Finder, then open it from there.") + "\n\n\(error.localizedDescription)"
            failed.runModal()
            return false
        }
    }

    /// Copies the app into Applications (replacing an older copy), moves the original to the Trash,
    /// and reopens the copy once this process has quit.
    static func moveAndRelaunch() throws {
        let running = Bundle.main.bundleURL
        let original = originalLocation(of: running)
        let fm = FileManager.default
        var folder = URL(fileURLWithPath: "/Applications", isDirectory: true)
        if !fm.isWritableFile(atPath: folder.path) {
            folder = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let destination = folder.appendingPathComponent(original.lastPathComponent)

        // Copy first (ditto keeps the signature intact), then swap, so a failure leaves everything as it was.
        let staging = folder.appendingPathComponent(".\(original.lastPathComponent).moving")
        try? fm.removeItem(at: staging)
        try run("/usr/bin/ditto", [original.path, staging.path])
        // It was opened already, so Gatekeeper has approved it: don't let the copy be quarantined again.
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staging.path])
        if fm.fileExists(atPath: destination.path) { try fm.trashItem(at: destination, resultingItemURL: nil) }
        try fm.moveItem(at: staging, to: destination)
        if original.standardizedFileURL != destination.standardizedFileURL { try? fm.trashItem(at: original, resultingItemURL: nil) }
        Log.write("Moved the app to \(destination.path)")

        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        helper.arguments = ["/bin/sh", "-c", "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done; open \"$0\"", destination.path]
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()
        NSApp.terminate(nil)
    }

    /// The app's real location: when macOS runs a translocated copy, the original file in Downloads.
    static func originalLocation(of url: URL) -> URL {
        guard AppLocation.isTranslocated(url.path),
              let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let symbol = dlsym(security, "SecTranslocateCreateOriginalPathForURL") else { return url }
        typealias OriginalPath = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        let originalPath = unsafeBitCast(symbol, to: OriginalPath.self)
        return originalPath(url as CFURL, nil)?.takeRetainedValue() as URL? ?? url
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
            throw Updater.Failure(description: "\((tool as NSString).lastPathComponent): \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return output
    }
}
