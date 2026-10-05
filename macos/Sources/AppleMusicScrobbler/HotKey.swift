import AppKit
import Carbon
import ScrobblerCore

/// The shortcuts offered for loving the current song from any app (Options › ♥ Keyboard Shortcut).
enum LoveShortcut: String, CaseIterable {
    case controlOptionL = "ctrl-opt-l"
    case controlCommandL = "ctrl-cmd-l"
    case controlOptionCommandL = "ctrl-opt-cmd-l"
    case off

    static let standard = LoveShortcut.controlOptionL

    var description: String {
        switch self {
        case .controlOptionL: return "\u{2303}\u{2325}L"
        case .controlCommandL: return "\u{2303}\u{2318}L"
        case .controlOptionCommandL: return "\u{2303}\u{2325}\u{2318}L"
        case .off: return L("Off")
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .controlOptionL: return UInt32(controlKey | optionKey)
        case .controlCommandL: return UInt32(controlKey | cmdKey)
        case .controlOptionCommandL: return UInt32(controlKey | optionKey | cmdKey)
        case .off: return 0
        }
    }

    var menuModifiers: NSEvent.ModifierFlags {
        switch self {
        case .controlOptionL: return [.control, .option]
        case .controlCommandL: return [.control, .command]
        case .controlOptionCommandL: return [.control, .option, .command]
        case .off: return []
        }
    }
}

/// A system-wide keyboard shortcut (Carbon's RegisterEventHotKey, which needs no Accessibility permission).
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    /// Nil if macOS refused (another app already uses the shortcut).
    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { hotKey.action() }
            return noErr
        }, 1, &type, me, &handler)
        let id = EventHotKeyID(signature: OSType(0x414D5343), id: 1) // "AMSC"
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
    }

    /// The chosen shortcut with L, or nil if it's off or taken.
    static func love(_ shortcut: LoveShortcut, _ action: @escaping () -> Void) -> HotKey? {
        shortcut == .off ? nil : HotKey(keyCode: UInt32(kVK_ANSI_L), modifiers: shortcut.carbonModifiers, action: action)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
