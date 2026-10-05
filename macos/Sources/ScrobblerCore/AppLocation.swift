import Foundation

/// Where the app runs from. It can only update itself and start at login reliably from an
/// Applications folder; opened straight from Downloads, macOS may even run a read-only copy
/// ("App Translocation").
public enum AppLocation {
    public static func isInApplications(_ path: String, home: String = NSHomeDirectory()) -> Bool {
        let p = (path as NSString).standardizingPath
        return p.hasPrefix("/Applications/") || p.hasPrefix((home as NSString).appendingPathComponent("Applications") + "/")
    }

    public static func isTranslocated(_ path: String) -> Bool {
        path.contains("/AppTranslocation/")
    }
}
