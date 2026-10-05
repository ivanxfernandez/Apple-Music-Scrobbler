import Foundation

public enum Log {
    private static let lock = NSLock()
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    public static var fileURL: URL { AppInfo.logFolder.appendingPathComponent("scrobbler.log") }

    /// Also print to the terminal (for --dry-run runs from a shell).
    nonisolated(unsafe) public static var echo = false

    public static func write(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        let line = "\(formatter.string(from: Date()))  \(message)\n"
        if echo { FileHandle.standardError.write(Data(line.utf8)) }
        // Logging must never take the app down.
        let fm = FileManager.default
        let url = fileURL
        try? fm.createDirectory(at: AppInfo.logFolder, withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 1_000_000 {
            let old = url.appendingPathExtension("old")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: url, to: old)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
