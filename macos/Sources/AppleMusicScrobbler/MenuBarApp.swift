import AppKit
import ScrobblerCore

/// The menu bar icon and its menu; reads Music once a second. Same menu as the Windows tray app.
@MainActor
final class MenuBarApp: NSObject, NSMenuDelegate {
    private static let updateCheckInterval: TimeInterval = 24 * 60 * 60

    private let settings: Settings
    private let dryRun: Bool
    private let api: LastFmClient
    private let reader: MusicReader
    private let scrobbler: Scrobbler
    private let discord: DiscordPresence
    private let setup = SetupWindowController()
    private let updater = Updater()

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let nowItem = NSMenuItem(title: "Nothing playing", action: nil, keyEquivalent: "")
    private let lastItem = NSMenuItem(title: "Nothing scrobbled yet", action: nil, keyEquivalent: "")
    private let recentItem = NSMenuItem(title: "Recent Scrobbles", action: nil, keyEquivalent: "")
    private let recentMenu = NSMenu()
    private let updateItem = NSMenuItem(title: "Update available", action: #selector(openUpdate), keyEquivalent: "")
    private let musicAccessItem = NSMenuItem(title: "Allow Access to Music\u{2026}", action: #selector(allowMusic), keyEquivalent: "")
    private let loveItem = NSMenuItem(title: "\u{2665} Love This Song on Last.fm", action: #selector(loveCurrent), keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "Pause Scrobbling", action: #selector(togglePause), keyEquivalent: "")
    private let startupItem = NSMenuItem(title: "Start at Login", action: #selector(toggleStartup), keyEquivalent: "")
    private let discordItem = NSMenuItem(title: "Show \u{201C}Listening to\u{201D} on Discord", action: #selector(toggleDiscord), keyEquivalent: "")
    private let cleanItem = NSMenuItem(title: "Clean Up Titles (Remove \u{201C}Remaster\u{201D}, \u{201C}- Single\u{201D}\u{2026})", action: #selector(toggleClean), keyEquivalent: "")
    private let mainArtistItem = NSMenuItem(title: "Scrobble Only the Main Artist of Collaborations", action: #selector(toggleMainArtist), keyEquivalent: "")
    private let checkUpdatesItem = NSMenuItem(title: "Check for Updates Automatically", action: #selector(toggleUpdateChecks), keyEquivalent: "")

    private var timer: Timer?
    private var updateTimer: Timer?
    private var update: ReleaseInfo?
    private var authWarningShown = false

    init(settings: Settings, reader: MusicReader, dryRun: Bool) {
        self.settings = settings
        self.reader = reader
        self.dryRun = dryRun
        api = LastFmClient(settings: settings)
        scrobbler = Scrobbler(settings: settings, api: api, dryRun: dryRun)
        discord = DiscordPresence(settings: settings)
        super.init()
        scrobbler.onAuthProblem = { [weak self] in self?.onAuthProblem() }
        reader.onAccessChanged = { [weak self] in self?.updateUi() }
        buildMenu()
    }

    func start(justConnected: Bool) {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer?.tolerance = 0.1

        // First update check a minute after starting (right away when testing the updater), then daily.
        if !AppInfo.gitHubRepo.isEmpty {
            updateTimer = Timer.scheduledTimer(withTimeInterval: UpdateChecker.pretendVersion == nil ? 60 : 3, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduledUpdateCheck() }
            }
        }

        Log.write(dryRun
            ? "Started \(AppInfo.version) (dry run: nothing is sent to Last.fm)"
            : "Started \(AppInfo.version), scrobbling as \(settings.username)")
        Notifier.shared.onAction = { [weak self] action in
            if action == "install-update" { self?.openUpdate() }
        }
        if !settings.lastRunVersion.isEmpty && settings.lastRunVersion != AppInfo.version {
            Log.write("Updated from \(settings.lastRunVersion) to \(AppInfo.version)")
            Notifier.shared.show("Updated to \(AppInfo.version)", "\(AppInfo.name) is up to date. See what's new on the release page.",
                                 url: AppInfo.repoUrl.isEmpty ? nil : URL(string: "\(AppInfo.repoUrl)/releases/tag/v\(AppInfo.version)"))
        }
        settings.lastRunVersion = AppInfo.version
        if justConnected {
            Notifier.shared.show("Connected to Last.fm", "Scrobbling Music as \(settings.username). I'll be here in the menu bar.")
        }
        tick()
    }

    func stop() {
        timer?.invalidate()
        updateTimer?.invalidate()
        discord.shutDown()
        Log.write("Stopped")
    }

    private func tick() {
        scrobbler.update(reader.snapshot())
        discord.update(scrobbler.current) // same (cleaned) track info as Last.fm gets
        updateUi()
    }

    // MARK: - Menu

    private func buildMenu() {
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "music.note", accessibilityDescription: AppInfo.name)
            image?.isTemplate = true // follows the light/dark menu bar
            button.image = image
            button.toolTip = AppInfo.name
        }

        nowItem.isEnabled = false
        mainArtistItem.toolTip = "\u{201C}Joji & BENEE\u{201D} is scrobbled as \u{201C}Joji\u{201D}. Bands like \u{201C}Simon & Garfunkel\u{201D} are left alone (Last.fm's listener counts tell them apart)."
        cleanItem.toolTip = "\u{201C}Song [2022 Remaster]\u{201D} is scrobbled as \u{201C}Song\u{201D}, \u{201C}Album (Deluxe Edition)\u{201D} as \u{201C}Album\u{201D}"
        lastItem.isEnabled = false
        updateItem.isHidden = true
        musicAccessItem.isHidden = true
        checkUpdatesItem.isHidden = AppInfo.gitHubRepo.isEmpty
        discordItem.isHidden = !DiscordPresence.available

        let options = NSMenu()
        for item in [startupItem, discordItem, cleanItem, mainArtistItem, checkUpdatesItem] { options.addItem(item) }
        options.addItem(.separator())
        options.addItem(withTitle: "Switch Last.fm Account\u{2026}", action: #selector(reconnect), keyEquivalent: "")
        options.addItem(withTitle: "Open Log", action: #selector(openLog), keyEquivalent: "")
        let optionsItem = NSMenuItem(title: "Options", action: nil, keyEquivalent: "")
        optionsItem.submenu = options

        let menu = NSMenu()
        menu.autoenablesItems = false
        options.autoenablesItems = false
        menu.addItem(nowItem)
        menu.addItem(lastItem)
        recentMenu.autoenablesItems = false
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)
        menu.addItem(.separator())
        menu.addItem(updateItem)
        menu.addItem(musicAccessItem)
        menu.addItem(loveItem)
        menu.addItem(pauseItem)
        menu.addItem(withTitle: "Open My Last.fm Profile", action: #selector(openProfile), keyEquivalent: "")
        menu.addItem(optionsItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Report a Problem\u{2026}", action: #selector(reportProblem), keyEquivalent: "")
        menu.addItem(withTitle: "About \(AppInfo.name)", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items + options.items where item.action != nil { item.target = self }
        menu.delegate = self
        statusItem.menu = menu
        updateUi()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        startupItem.state = Startup.isEnabled ? .on : .off
        buildRecentMenu()
        updateUi()
    }

    /// Latest scrobbles (click one to open it on Last.fm), anything waiting to be sent, and Send Now.
    private func buildRecentMenu() {
        recentMenu.removeAllItems()
        let recent = scrobbler.recent
        if recent.isEmpty {
            let none = NSMenuItem(title: "Nothing scrobbled yet", action: nil, keyEquivalent: "")
            none.isEnabled = false
            recentMenu.addItem(none)
        }
        for item in recent {
            let entry = NSMenuItem(title: Self.menuText("\(RecentScrobbles.time(item))   \(item.artist) - \(item.track)"),
                                   action: #selector(openRecent(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = item.url
            entry.toolTip = "Open on Last.fm"
            recentMenu.addItem(entry)
        }

        let pending = scrobbler.pendingScrobbles
        if !pending.isEmpty {
            recentMenu.addItem(.separator())
            let waiting = NSMenuItem(title: pending.count == 1 ? "1 Waiting to Send" : "\(pending.count) Waiting to Send", action: nil, keyEquivalent: "")
            waiting.isEnabled = false
            recentMenu.addItem(waiting)
            for s in pending.suffix(5).reversed() {
                let entry = NSMenuItem(title: Self.menuText("    \(s.artist) - \(s.track)"), action: nil, keyEquivalent: "")
                entry.isEnabled = false
                recentMenu.addItem(entry)
            }
            let sendNow = NSMenuItem(title: "Send Now", action: #selector(sendNow), keyEquivalent: "")
            sendNow.target = self
            sendNow.isEnabled = !dryRun
            recentMenu.addItem(sendNow)
        }

        recentMenu.addItem(.separator())
        let library = NSMenuItem(title: "Open My Last.fm Library", action: #selector(openLibrary), keyEquivalent: "")
        library.target = self
        recentMenu.addItem(library)
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.open(url) }
    }

    @objc private func sendNow() {
        Log.write("Sending \(scrobbler.pending) waiting scrobble(s) now")
        scrobbler.retrySoon()
        tick()
    }

    @objc private func openLibrary() {
        let user = settings.username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        if let url = URL(string: "https://www.last.fm/user/\(user)/library") { NSWorkspace.shared.open(url) }
    }

    private func updateUi() {
        let np = scrobbler.current
        let playing = np.map { $0.isValid ? $0.description + ($0.isPlaying ? "" : " (paused)") : nil } ?? nil
        setTitle(nowItem, Self.menuText(playing ?? "Nothing playing"))
        setTitle(lastItem, scrobbler.lastScrobbled.isEmpty ? "Nothing scrobbled yet" : Self.menuText("Last scrobbled: " + scrobbler.lastScrobbled))
        setTitle(recentItem, scrobbler.pending > 0 ? "Recent Scrobbles (\(scrobbler.pending) Waiting)" : "Recent Scrobbles")
        loveItem.isEnabled = np?.isValid == true && !dryRun
        pauseItem.state = settings.paused ? .on : .off
        discordItem.state = settings.showOnDiscord ? .on : .off
        setTitle(discordItem, "Show \u{201C}Listening to\u{201D} on Discord" + (settings.showOnDiscord && !discord.isConnected ? " (Waiting for Discord)" : ""))
        cleanItem.state = settings.cleanTitles ? .on : .off
        mainArtistItem.state = settings.mainArtistOnly ? .on : .off
        checkUpdatesItem.state = settings.checkForUpdates ? .on : .off
        musicAccessItem.isHidden = reader.access == .granted || reader.access == .unknown
        setTitle(musicAccessItem, reader.access == .denied ? "Music Access Is Off (Repeats May Be Missed)\u{2026}" : "Allow Access to Music\u{2026}")

        statusItem.button?.appearsDisabled = settings.paused
        var tip = (settings.paused ? "Scrobbling paused\n" : "") + (playing ?? "Nothing playing")
        if scrobbler.pending > 0 { tip += "\n\(scrobbler.pending) waiting to send" }
        if statusItem.button?.toolTip != tip { statusItem.button?.toolTip = tip }
    }

    private static func menuText(_ text: String) -> String {
        text.count > 70 ? String(text.prefix(69)) + "\u{2026}" : text
    }

    private func setTitle(_ item: NSMenuItem, _ title: String) {
        if item.title != title { item.title = title }
    }

    // MARK: - Actions

    /// Asks before installing; Release Notes opens the release page.
    @objc private func openUpdate() {
        guard let update else { return }
        let alert = NSAlert()
        alert.messageText = "Update to \(AppInfo.name) \(update.tag)?"
        switch Updater.installLocation() {
        case .success where update.download != nil:
            alert.informativeText = "The app downloads the new version, checks it, and restarts. Your settings and Last.fm login are kept."
            alert.addButton(withTitle: "Install and Restart")
        case .failure(let reason):
            alert.informativeText = "It can't update itself because \(reason). You can download the new version from the release page."
            alert.addButton(withTitle: "Open Release Page")
        default:
            alert.informativeText = "You can download the new version from the release page."
            alert.addButton(withTitle: "Open Release Page")
        }
        alert.addButton(withTitle: "Later")
        if alert.buttons.first?.title == "Install and Restart" { alert.addButton(withTitle: "Release Notes") }
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if alert.buttons.first?.title == "Install and Restart" {
                updateItem.title = "Installing \(update.tag)\u{2026}"
                updateItem.isEnabled = false
                updater.install(update) { [weak self] in
                    self?.updateItem.isEnabled = true
                    self?.updateItem.title = "\u{2B06} Update Available: \(update.tag)"
                    NSWorkspace.shared.open(update.url)
                }
            } else {
                NSWorkspace.shared.open(update.url)
            }
        case .alertThirdButtonReturn:
            NSWorkspace.shared.open(update.url)
        default:
            break
        }
    }

    @objc private func allowMusic() {
        if reader.access == .denied {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
            return
        }
        Task { _ = await reader.requestAccess(); updateUi() }
    }

    @objc private func loveCurrent() {
        guard let np = scrobbler.current, np.isValid else { return }
        Task {
            do {
                try await api.love(artist: np.artist, title: np.title)
                Log.write("Loved: \(np)")
                Notifier.shared.show("\u{2665} Loved on Last.fm", np.description)
            } catch {
                Log.write("Love failed: \(error)")
                Notifier.shared.show("Couldn't love this song", error.localizedDescriptionIfUseful)
            }
        }
    }

    @objc private func togglePause() {
        settings.paused.toggle()
        Log.write(settings.paused ? "Scrobbling paused" : "Scrobbling resumed")
        updateUi()
    }

    @objc private func openProfile() {
        let user = settings.username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        if let url = URL(string: "https://www.last.fm/user/" + user) { NSWorkspace.shared.open(url) }
    }

    @objc private func toggleStartup() {
        Startup.set(!Startup.isEnabled)
        startupItem.state = Startup.isEnabled ? .on : .off
    }

    @objc private func toggleDiscord() {
        settings.showOnDiscord.toggle()
        Log.write(settings.showOnDiscord ? "Discord status turned on" : "Discord status turned off")
        updateUi()
    }

    @objc private func toggleClean() {
        settings.cleanTitles.toggle()
        updateUi()
    }

    @objc private func toggleMainArtist() {
        settings.mainArtistOnly.toggle()
        Log.write(settings.mainArtistOnly ? "Scrobbling only the main artist of collaborations" : "Scrobbling full artist credits")
        updateUi()
    }

    @objc private func toggleUpdateChecks() {
        settings.checkForUpdates.toggle()
        updateUi()
    }

    @objc private func reconnect() {
        setup.show(settings: settings, reader: reader) { [weak self] connected in
            guard let self, connected else { return }
            authWarningShown = false
            scrobbler.retrySoon()
            Log.write("Now scrobbling as \(settings.username)")
        }
    }

    @objc private func openLog() {
        Log.write("Log opened")
        NSWorkspace.shared.open(Log.fileURL) // opens in Console
    }

    @objc private func reportProblem() {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var arch = "Apple Silicon"
        #if arch(x86_64)
        arch = "Intel"
        #endif
        let system = "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) (\(arch))"
        let log = (try? String(contentsOf: Log.fileURL, encoding: .utf8)) ?? ""
        Log.write("Opened the problem report form")
        NSWorkspace.shared.open(IssueReport.url(repo: AppInfo.gitHubRepo, version: AppInfo.version, system: system, log: log))
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "\(AppInfo.name) \(AppInfo.version)"
        alert.informativeText = "Scrobbles the Music app on your Mac to Last.fm.\nNot affiliated with Apple or Last.fm."
        alert.addButton(withTitle: "OK")
        if !AppInfo.repoUrl.isEmpty { alert.addButton(withTitle: "Open Project Page") }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn, let url = URL(string: AppInfo.repoUrl) {
            NSWorkspace.shared.open(url)
            Task { await checkForUpdate(manual: true) }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Updates and problems

    private func scheduledUpdateCheck() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: Self.updateCheckInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.checkForUpdate(manual: false) }
            }
        }
        Task { await checkForUpdate(manual: false) }
    }

    private func checkForUpdate(manual: Bool) async {
        if !manual && !settings.checkForUpdates { return }
        do {
            guard let release = try await UpdateChecker.newerRelease() else {
                if manual { Notifier.shared.show("You're up to date", "\(AppInfo.name) \(AppInfo.version) is the latest version.") }
                return
            }
            update = release
            updateItem.title = "\u{2B06} Update Available: \(release.tag)"
            updateItem.isHidden = false
            if manual || settings.updateNotifiedFor != release.tag {
                Log.write("Update available: \(release.tag)")
                settings.updateNotifiedFor = release.tag
                Notifier.shared.show("Update available", "\(AppInfo.name) \(release.tag) is out. Click to install it.", action: "install-update")
            }
        } catch {
            Log.write("Update check failed: \(error.localizedDescription)")
            if manual { Notifier.shared.show("Couldn't check for updates", error.localizedDescription) }
        }
    }

    private func onAuthProblem() {
        if authWarningShown { return }
        authWarningShown = true
        Notifier.shared.show("Last.fm needs you to reconnect",
                             "Click the menu bar icon and choose Options › Switch Last.fm Account. Your scrobbles are saved until then.")
    }
}
