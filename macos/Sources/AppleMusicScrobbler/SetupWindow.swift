import AppKit
import SwiftUI
import ScrobblerCore

/// First-run window: (optionally) collects a Last.fm API key, asks for access to Music, then runs
/// Last.fm's desktop auth flow: get a token, open the approval page in the browser, poll until approved.
@MainActor
final class SetupModel: ObservableObject {
    static let createApiAccountUrl = URL(string: "https://www.last.fm/api/account/create")!

    @Published var apiKey: String
    @Published var apiSecret: String
    @Published var startAtLogin = true
    @Published var status = ""
    @Published var statusIsError = false
    @Published var busy = false
    @Published var waitingForApproval = false
    @Published var musicAccess: MusicAccess

    let needsApiKey: Bool
    private let settings: ScrobblerCore.Settings
    private let api: LastFmClient
    private let reader: MusicReader
    private var token: String?
    private var pollTask: Task<Void, Never>?
    var onConnected: (() -> Void)?

    init(settings: ScrobblerCore.Settings, reader: MusicReader) {
        self.settings = settings
        self.reader = reader
        api = LastFmClient(settings: settings)
        needsApiKey = AppInfo.builtInApiKey.isEmpty || !settings.apiKey.isEmpty
        apiKey = settings.apiKey
        apiSecret = settings.apiSecret
        musicAccess = reader.access
    }

    func allowMusic() {
        Task {
            musicAccess = await reader.requestAccess()
        }
    }

    func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }

    func connect() {
        if needsApiKey {
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let secret = apiSecret.trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty || secret.isEmpty {
                show(L("Paste both the API key and the Shared secret first."), error: true)
                return
            }
            settings.apiKey = key
            settings.apiSecret = secret
        }

        busy = true
        show(L("Contacting Last.fm..."))
        Task {
            do {
                let token = try await api.getToken()
                self.token = token
                NSWorkspace.shared.open(api.authUrl(token: token))
                show(L("Waiting for you to click \u{201C}Yes, allow access\u{201D} on the Last.fm page in your browser..."))
                waitingForApproval = true
                pollTask = Task { await poll(token: token, issued: Date()) }
            } catch let error as LastFmError where error.code == 10 || error.code == 26 {
                show(L("Last.fm didn't accept that API key. Check you copied the API key and Shared secret correctly."), error: true)
                busy = false
            } catch {
                show(L("Couldn't reach Last.fm: %@", error.localizedDescriptionIfUseful), error: true)
                busy = false
            }
        }
    }

    func reopenApprovalPage() {
        if let token { NSWorkspace.shared.open(api.authUrl(token: token)) }
    }

    func cancel() {
        pollTask?.cancel()
    }

    private func poll(token: String, issued: Date) async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if Task.isCancelled { return }
            do {
                let (key, username) = try await api.getSession(token: token)
                settings.sessionKey = key
                settings.username = username
                try settings.save()
                Startup.set(startAtLogin)
                Log.write("Connected to Last.fm as \(username)")
                onConnected?()
                return
            } catch let error as LastFmError where error.code == 14 { // not approved yet
                if Date().timeIntervalSince(issued) > 600 { return fail(L("Timed out waiting for approval. Click Connect to try again.")) }
            } catch let error as LastFmError where error.code == 4 || error.code == 15 { // token expired/invalid
                return fail(L("That approval link expired. Click Connect to try again."))
            } catch let error as LastFmError where error.code == 13 {
                return fail(L("Last.fm rejected the Shared secret. Check you copied it correctly."))
            } catch {
                // Network blip: keep trying for a while.
                if Date().timeIntervalSince(issued) > 600 { return fail(L("Couldn't reach Last.fm: %@", error.localizedDescriptionIfUseful)) }
            }
        }
    }

    private func fail(_ message: String) {
        show(message, error: true)
        waitingForApproval = false
        busy = false
    }

    private func show(_ text: String, error: Bool = false) {
        status = text
        statusIsError = error
    }
}

struct SetupView: View {
    @ObservedObject var model: SetupModel
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Connect to Last.fm")).font(.title).bold()
            Text(L("This app watches what the Music app is playing and adds it to your Last.fm profile."))

            if model.needsApiKey {
                step(1, L("Get a free Last.fm API key"))
                Text(L("Last.fm requires every app to have one. It takes a minute: fill in any application name and description, leave \u{201C}Callback URL\u{201D} empty, and submit. Then copy the API key and Shared secret here."))
                Link(L("Create a Last.fm API account"), destination: SetupModel.createApiAccountUrl)
                Grid(alignment: .leading) {
                    GridRow {
                        Text(L("API key"))
                        TextField("", text: $model.apiKey).frame(width: 280)
                    }
                    GridRow {
                        Text(L("Shared secret"))
                        SecureField("", text: $model.apiSecret).frame(width: 280)
                    }
                }
                .disabled(model.busy)
            }

            step(model.needsApiKey ? 2 : 1, L("Allow access to Music"))
            Text(L("So repeated songs are counted, the app reads how far into a song you are. macOS asks you once: click Allow."))
            HStack {
                switch model.musicAccess {
                case .granted:
                    Label(L("Allowed"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .denied:
                    Label(L("Not allowed. Scrobbling still works, but repeats may be missed."), systemImage: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                    Button(L("Open Privacy Settings")) { model.openPrivacySettings() }
                default:
                    Button(L("Allow Access to Music\u{2026}")) { model.allowMusic() }
                }
            }

            step(model.needsApiKey ? 3 : 2, L("Allow access to your Last.fm account"))
            Text(L("Click Connect. Last.fm opens in your browser: click \u{201C}Yes, allow access\u{201D} there and this window finishes by itself."))

            Toggle(L("Start automatically when I log in"), isOn: $model.startAtLogin)

            HStack {
                if model.waitingForApproval {
                    Button(L("Open the Last.fm page again")) { model.reopenApprovalPage() }.buttonStyle(.link)
                }
                Spacer()
                Button(L("Cancel"), action: onCancel).keyboardShortcut(.cancelAction)
                Button(L("Connect")) { model.connect() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.busy)
            }

            if !model.status.isEmpty {
                Text(model.status)
                    .foregroundStyle(model.statusIsError ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func step(_ number: Int, _ title: String) -> some View {
        Text("\(number). \(title)").font(.headline).padding(.top, 4)
    }
}

/// --save-setup-screenshot PATH: draws the setup window (with its title bar) into a PNG for the
/// README, without showing it or needing screen-recording permission.
@MainActor
func saveSetupScreenshot(to path: String, settings: ScrobblerCore.Settings, reader: MusicReader) {
    let model = SetupModel(settings: settings, reader: reader)
    let window = NSWindow(contentViewController: NSHostingController(rootView: SetupView(model: model) {}))
    window.title = AppInfo.name
    window.styleMask = [.titled, .closable]
    window.appearance = NSAppearance(named: .aqua)
    window.layoutIfNeeded()
    guard let frameView = window.contentView?.superview else { return }
    frameView.layoutSubtreeIfNeeded()
    let bounds = frameView.bounds
    let scale = 2
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width) * scale, pixelsHigh: Int(bounds.height) * scale,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
    rep.size = bounds.size
    NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
        frameView.cacheDisplay(in: bounds, to: rep)
    }
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

/// Shows the setup window; calls `completion(true)` once connected, `false` if closed.
@MainActor
final class SetupWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var model: SetupModel?
    private var completion: ((Bool) -> Void)?

    func show(settings: ScrobblerCore.Settings, reader: MusicReader, completion: @escaping (Bool) -> Void) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        self.completion = completion
        let model = SetupModel(settings: settings, reader: reader)
        model.onConnected = { [weak self] in self?.finish(true) }
        self.model = model

        let window = NSWindow(contentViewController: NSHostingController(rootView: SetupView(model: model) { [weak self] in self?.finish(false) }))
        window.title = AppInfo.name
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        finish(false)
    }

    private func finish(_ connected: Bool) {
        guard let completion else { return }
        self.completion = nil
        model?.cancel()
        window?.delegate = nil
        window?.close()
        window = nil
        model = nil
        completion(connected)
    }
}
