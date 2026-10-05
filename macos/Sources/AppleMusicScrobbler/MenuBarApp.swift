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
    private let nowItem = NSMenuItem(title: L("Nothing playing"), action: nil, keyEquivalent: "")
    private let lastItem = NSMenuItem(title: L("Nothing scrobbled yet"), action: nil, keyEquivalent: "")
    private let recentItem = NSMenuItem(title: L("Recent Scrobbles"), action: nil, keyEquivalent: "")
    private let recentMenu = NSMenu()
    private let updateItem = NSMenuItem(title: L("Update available"), action: #selector(openUpdate), keyEquivalent: "")
    private let musicAccessItem = NSMenuItem(title: L("Allow Access to Music\u{2026}"), action: #selector(allowMusic), keyEquivalent: "")
    private let loveItem = NSMenuItem(title: L("\u{2665} Love This Song on Last.fm"), action: #selector(loveCurrent), keyEquivalent: "")
    private let ignoreItem = NSMenuItem(title: L("Don\u{2019}t Scrobble This Artist"), action: #selector(ignoreCurrentArtist), keyEquivalent: "")
    private let ignoredListItem = NSMenuItem(title: L("Ignored Artists"), action: nil, keyEquivalent: "")
    private let ignoredMenu = NSMenu()
    private let pauseItem = NSMenuItem(title: L("Pause Scrobbling"), action: #selector(togglePause), keyEquivalent: "")
    private let startupItem = NSMenuItem(title: L("Start at Login"), action: #selector(toggleStartup), keyEquivalent: "")
    private let discordItem = NSMenuItem(title: L("Show \u{201C}Listening to\u{201D} on Discord"), action: #selector(toggleDiscord), keyEquivalent: "")
    private let cleanItem = NSMenuItem(title: L("Clean Up Titles (Remove \u{201C}Remaster\u{201D}, \u{201C}- Single\u{201D}\u{2026})"), action: #selector(toggleClean), keyEquivalent: "")
    private let mainArtistItem = NSMenuItem(title: L("Scrobble Only the Main Artist of Collaborations"), action: #selector(toggleMainArtist), keyEquivalent: "")
    private let catchUpItem = NSMenuItem(title: L("Catch Up on Plays from Other Devices"), action: #selector(toggleCatchUp), keyEquivalent: "")
    private let loveShortcutItem = NSMenuItem(title: L("\u{2665} Keyboard Shortcut"), action: nil, keyEquivalent: "")
    private let loveShortcutMenu = NSMenu()
    private let nowPlayingNotificationItem = NSMenuItem(title: L("Show a Notification When a Song Starts"), action: #selector(toggleNowPlayingNotification), keyEquivalent: "")
    private let checkUpdatesItem = NSMenuItem(title: L("Check for Updates Automatically"), action: #selector(toggleUpdateChecks), keyEquivalent: "")

    private var timer: Timer?
    private var loveHotKey: HotKey?
    /// Whether songs (artist + title as sent to Last.fm) are loved there; filled in as songs play.
    private var loved: [String: Bool] = [:]
    private var lovedPending: Set<String> = []
    private let artwork = AppleMusicLinks()
    private var catchUpTimer: Timer?
    private var catchingUp = false
    private var sightings: [CatchUp.Sighting] = []
    private var sentByCatchUp: [CatchUp.Sighting] = []
    private var lastSightingsSave = Date.distantPast
    private static let catchUpFile = AppInfo.dataFolder.appendingPathComponent("catchup.json")
    private struct CatchUpState: Codable {
        var sightings: [CatchUp.Sighting]
        var sent: [CatchUp.Sighting]
    }
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
        scrobbler.onNowPlaying = { [weak self] np in self?.showNowPlaying(np) }
        reader.onAccessChanged = { [weak self] in self?.updateUi() }
        buildMenu()
    }

    func start(justConnected: Bool) {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer?.tolerance = 0.1

        // Catch-up: 2 minutes after starting, then every 15 minutes (it checks the setting each time).
        if let data = try? Data(contentsOf: Self.catchUpFile), let state = try? JSONDecoder().decode(CatchUpState.self, from: data) {
            sightings = state.sightings
            sentByCatchUp = state.sent
        }
        catchUpTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.catchUp() }
                self.catchUpTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        Task { await self.catchUp() }
                    }
                }
            }
        }

        // First update check a minute after starting (right away when testing the updater), then daily.
        if !AppInfo.gitHubRepo.isEmpty {
            updateTimer = Timer.scheduledTimer(withTimeInterval: UpdateChecker.pretendVersion == nil ? 60 : 3, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduledUpdateCheck() }
            }
        }

        Log.write(dryRun
            ? "Started \(AppInfo.version) (dry run: nothing is sent to Last.fm)"
            : "Started \(AppInfo.version), scrobbling as \(settings.username)")
        updateLoveShortcut()
        Notifier.shared.onAction = { [weak self] action in
            if action == "install-update" { self?.openUpdate() }
        }
        if !settings.lastRunVersion.isEmpty && settings.lastRunVersion != AppInfo.version {
            Log.write("Updated from \(settings.lastRunVersion) to \(AppInfo.version)")
            Notifier.shared.show(L("Updated to %@", AppInfo.version), L("%@ is up to date. See what's new on the release page.", AppInfo.name),
                                 url: AppInfo.repoUrl.isEmpty ? nil : URL(string: "\(AppInfo.repoUrl)/releases/tag/v\(AppInfo.version)"))
        }
        settings.lastRunVersion = AppInfo.version
        if justConnected {
            Notifier.shared.show(L("Connected to Last.fm"), L("Scrobbling Music as %@. I'll be here in the menu bar.", settings.username))
        }
        tick()
    }

    func stop() {
        saveCatchUpState()
        timer?.invalidate()
        catchUpTimer?.invalidate()
        updateTimer?.invalidate()
        discord.shutDown()
        Log.write("Stopped")
    }

    private func tick() {
        let snapshot = reader.snapshot()
        scrobbler.update(snapshot)
        // Remember what played here, so catch-up never sends a play this app already handled.
        if let np = snapshot, np.isValid, np.isPlaying {
            sightings = CatchUp.recording(CatchUp.key(np.artist, np.title), at: Date(), in: sightings)
            if Date().timeIntervalSince(lastSightingsSave) > 60 { saveCatchUpState() }
        }
        // Same (cleaned) track info as Last.fm gets; nothing for ignored artists.
        discord.update(scrobbler.currentIsIgnored ? nil : scrobbler.current)
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
        loveShortcutMenu.autoenablesItems = false
        loveShortcutItem.submenu = loveShortcutMenu
        mainArtistItem.toolTip = L("\u{201C}Joji & BENEE\u{201D} is scrobbled as \u{201C}Joji\u{201D}. Bands like \u{201C}Simon & Garfunkel\u{201D} are left alone (Last.fm's listener counts tell them apart).")
        catchUpItem.toolTip = L("Scrobbles songs from your library that you played on your iPhone or iPad, from Music's play history (synced through iCloud).")
        cleanItem.toolTip = L("\u{201C}Song [2022 Remaster]\u{201D} is scrobbled as \u{201C}Song\u{201D}, \u{201C}Album (Deluxe Edition)\u{201D} as \u{201C}Album\u{201D}")
        lastItem.isEnabled = false
        updateItem.isHidden = true
        musicAccessItem.isHidden = true
        checkUpdatesItem.isHidden = AppInfo.gitHubRepo.isEmpty
        discordItem.isHidden = !DiscordPresence.available

        let options = NSMenu()
        for item in [startupItem, discordItem, nowPlayingNotificationItem, loveShortcutItem, cleanItem, mainArtistItem, catchUpItem, checkUpdatesItem] { options.addItem(item) }
        ignoredMenu.autoenablesItems = false
        ignoredListItem.submenu = ignoredMenu
        options.addItem(ignoredListItem)
        options.addItem(.separator())
        options.addItem(withTitle: L("Switch Last.fm Account\u{2026}"), action: #selector(reconnect), keyEquivalent: "")
        options.addItem(withTitle: L("Open Log"), action: #selector(openLog), keyEquivalent: "")
        let optionsItem = NSMenuItem(title: L("Options"), action: nil, keyEquivalent: "")
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
        menu.addItem(ignoreItem)
        menu.addItem(pauseItem)
        menu.addItem(withTitle: L("Open My Last.fm Profile"), action: #selector(openProfile), keyEquivalent: "")
        menu.addItem(optionsItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Report a Problem\u{2026}"), action: #selector(reportProblem), keyEquivalent: "")
        menu.addItem(withTitle: L("About %@", AppInfo.name), action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(withTitle: L("Quit"), action: #selector(quit), keyEquivalent: "q")
        for item in menu.items + options.items where item.action != nil { item.target = self }
        menu.delegate = self
        statusItem.menu = menu
        updateUi()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        startupItem.state = Startup.isEnabled ? .on : .off
        buildRecentMenu()
        buildIgnoredMenu()
        updateUi()
    }

    /// Ignored artists; clicking one scrobbles it again.
    private func buildIgnoredMenu() {
        ignoredMenu.removeAllItems()
        let artists = settings.ignoredArtists
        let hint = NSMenuItem(title: artists.isEmpty ? L("No ignored artists. Use \u{201C}Don\u{2019}t Scrobble\u{201D} while one plays.") : L("Not sent to Last.fm or shown on Discord. Click to undo:"),
                              action: nil, keyEquivalent: "")
        hint.isEnabled = false
        ignoredMenu.addItem(hint)
        for artist in artists {
            let item = NSMenuItem(title: Self.menuText(artist), action: #selector(unignoreArtist(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = artist
            ignoredMenu.addItem(item)
        }
    }

    @objc private func ignoreCurrentArtist() {
        guard let np = scrobbler.current, np.isValid else { return }
        if scrobbler.currentIsIgnored {
            settings.ignoredArtists = settings.ignoredArtists.filter { !IgnoreList.isIgnored(np.artist, in: [$0]) }
            Log.write("Scrobbling \(np.artist) again")
        } else {
            settings.ignoredArtists = IgnoreList.adding(np.artist, to: settings.ignoredArtists)
            Log.write("Ignoring \(np.artist): not scrobbled or shown on Discord")
        }
        tick()
    }

    @objc private func unignoreArtist(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? String else { return }
        settings.ignoredArtists = IgnoreList.removing(artist, from: settings.ignoredArtists)
        Log.write("Scrobbling \(artist) again")
        tick()
    }

    /// Latest scrobbles (click one to open it on Last.fm), anything waiting to be sent, and Send Now.
    private func buildRecentMenu() {
        recentMenu.removeAllItems()
        let recent = scrobbler.recent
        if recent.isEmpty {
            let none = NSMenuItem(title: L("Nothing scrobbled yet"), action: nil, keyEquivalent: "")
            none.isEnabled = false
            recentMenu.addItem(none)
        }
        for item in recent {
            let entry = NSMenuItem(title: Self.menuText("\(RecentScrobbles.time(item))   \(item.artist) - \(item.track)"),
                                   action: #selector(openRecent(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = item.url
            entry.toolTip = L("Open on Last.fm")
            recentMenu.addItem(entry)
        }

        let pending = scrobbler.pendingScrobbles
        if !pending.isEmpty {
            recentMenu.addItem(.separator())
            let waiting = NSMenuItem(title: pending.count == 1 ? L("1 Waiting to Send") : L("%@ Waiting to Send", pending.count), action: nil, keyEquivalent: "")
            waiting.isEnabled = false
            recentMenu.addItem(waiting)
            for s in pending.suffix(5).reversed() {
                let entry = NSMenuItem(title: Self.menuText("    \(s.artist) - \(s.track)"), action: nil, keyEquivalent: "")
                entry.isEnabled = false
                recentMenu.addItem(entry)
            }
            let sendNow = NSMenuItem(title: L("Send Now"), action: #selector(sendNow), keyEquivalent: "")
            sendNow.target = self
            sendNow.isEnabled = !dryRun
            recentMenu.addItem(sendNow)
        }

        recentMenu.addItem(.separator())
        let library = NSMenuItem(title: L("Open My Last.fm Library"), action: #selector(openLibrary), keyEquivalent: "")
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
        let ignored = scrobbler.currentIsIgnored
        let playing: String? = np.flatMap { np in
            guard np.isValid else { return nil }
            var text = np.description
            if !np.isPlaying { text = L("%@ (paused)", text) }
            if ignored { text = L("%@ (not scrobbled)", text) }
            return text
        }
        setTitle(nowItem, Self.menuText(playing ?? L("Nothing playing")))
        setTitle(lastItem, scrobbler.lastScrobbled.isEmpty ? L("Nothing scrobbled yet") : Self.menuText(L("Last scrobbled: %@", scrobbler.lastScrobbled)))
        setTitle(recentItem, scrobbler.pending > 0 ? L("Recent Scrobbles (%@ Waiting)", scrobbler.pending) : L("Recent Scrobbles"))
        loveItem.isEnabled = np?.isValid == true && !dryRun
        loveItem.state = lovedState() == true ? .on : .off
        nowPlayingNotificationItem.state = settings.nowPlayingNotification ? .on : .off
        ignoreItem.isEnabled = np?.isValid == true
        setTitle(ignoreItem, np?.isValid == true
            ? Self.menuText(ignored ? L("Scrobble %@ Again", np?.artist ?? "") : L("Don\u{2019}t Scrobble %@", np?.artist ?? ""))
            : L("Don\u{2019}t Scrobble This Artist"))
        pauseItem.state = settings.paused ? .on : .off
        discordItem.state = settings.showOnDiscord ? .on : .off
        setTitle(discordItem, settings.showOnDiscord && !discord.isConnected ? L("Show \u{201C}Listening to\u{201D} on Discord (Waiting for Discord)") : L("Show \u{201C}Listening to\u{201D} on Discord"))
        cleanItem.state = settings.cleanTitles ? .on : .off
        mainArtistItem.state = settings.mainArtistOnly ? .on : .off
        catchUpItem.state = settings.catchUp ? .on : .off
        checkUpdatesItem.state = settings.checkForUpdates ? .on : .off
        musicAccessItem.isHidden = reader.access == .granted || reader.access == .unknown
        setTitle(musicAccessItem, reader.access == .denied ? L("Music Access Is Off (Repeats May Be Missed)\u{2026}") : L("Allow Access to Music\u{2026}"))

        statusItem.button?.appearsDisabled = settings.paused
        var tip = (settings.paused ? L("Scrobbling paused") + "\n" : "") + (playing ?? L("Nothing playing"))
        if scrobbler.pending > 0 { tip += "\n" + L("%@ waiting to send", scrobbler.pending) }
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
        alert.messageText = L("Update to %@ %@?", AppInfo.name, update.tag)
        switch Updater.installLocation() {
        case .success where update.download != nil:
            alert.informativeText = L("The app downloads the new version, checks it, and restarts. Your settings and Last.fm login are kept.")
            alert.addButton(withTitle: L("Install and Restart"))
        case .failure(let reason):
            alert.informativeText = L("It can't update itself because %@. You can download the new version from the release page.", reason)
            alert.addButton(withTitle: L("Open Release Page"))
        default:
            alert.informativeText = L("You can download the new version from the release page.")
            alert.addButton(withTitle: L("Open Release Page"))
        }
        alert.addButton(withTitle: L("Later"))
        if alert.buttons.first?.title == L("Install and Restart") { alert.addButton(withTitle: L("Release Notes")) }
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if alert.buttons.first?.title == L("Install and Restart") {
                updateItem.title = L("Installing %@\u{2026}", update.tag)
                updateItem.isEnabled = false
                updater.install(update) { [weak self] in
                    self?.updateItem.isEnabled = true
                    self?.updateItem.title = L("\u{2B06} Update Available: %@", update.tag)
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

    /// Whether the current song is loved on Last.fm; nil while unknown (starts the lookup).
    private func lovedState() -> Bool? {
        guard let np = scrobbler.currentAsSent, !dryRun, !settings.username.isEmpty else { return nil }
        let key = np.artist + "\n" + np.title
        if let known = loved[key] { return known }
        if !lovedPending.contains(key) {
            lovedPending.insert(key)
            Task {
                // Unknown on failure: the item just shows without a checkmark.
                if let isLoved = try? await api.isLoved(artist: np.artist, title: np.title, user: settings.username) {
                    if loved.count > 500 { loved.removeAll() }
                    loved[key] = isLoved
                }
                lovedPending.remove(key)
                updateUi()
            }
        }
        return nil
    }

    /// The menu item: loves the song, or un-loves it if it's already loved (shown with a checkmark).
    @objc private func loveCurrent() {
        setLoved(lovedState() != true)
    }

    /// The keyboard shortcut only loves; it never takes a love back.
    private func loveFromShortcut() {
        guard let np = scrobbler.currentAsSent, !dryRun else {
            Notifier.shared.show(L("Nothing playing"), L("Play a song in Music, then press %@ to love it.", currentShortcut.description))
            return
        }
        if lovedState() == true {
            Notifier.shared.show(L("Already loved"), np.description)
        } else {
            setLoved(true)
        }
    }

    private func setLoved(_ love: Bool) {
        guard let np = scrobbler.currentAsSent else { return }
        let key = np.artist + "\n" + np.title
        Task {
            do {
                if love { try await api.love(artist: np.artist, title: np.title) } else { try await api.unlove(artist: np.artist, title: np.title) }
                loved[key] = love
                Log.write((love ? "Loved: " : "Unloved: ") + np.description)
                Notifier.shared.show(love ? L("\u{2665} Loved on Last.fm") : L("Removed from your loved tracks"), np.description)
                updateUi()
            } catch {
                Log.write((love ? "Love" : "Unlove") + " failed: \(error)")
                Notifier.shared.show(love ? L("Couldn't love this song") : L("Couldn't remove the love"), error.localizedDescriptionIfUseful)
            }
        }
    }

    private var currentShortcut: LoveShortcut { LoveShortcut(rawValue: settings.loveShortcut) ?? .standard }

    private func updateLoveShortcut() {
        loveHotKey = nil
        let shortcut = currentShortcut
        loveHotKey = HotKey.love(shortcut) { [weak self] in MainActor.assumeIsolated { self?.loveFromShortcut() } }
        if shortcut != .off && loveHotKey == nil {
            Log.write("The love shortcut \(shortcut.description) is used by another app; pick another one in Options")
        }
        // Show the shortcut next to the love item, only when it works.
        loveItem.keyEquivalent = loveHotKey == nil ? "" : "l"
        loveItem.keyEquivalentModifierMask = loveHotKey == nil ? [] : shortcut.menuModifiers
        loveShortcutMenu.removeAllItems()
        for choice in LoveShortcut.allCases {
            let item = NSMenuItem(title: choice.description, action: #selector(chooseLoveShortcut(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice.rawValue
            item.state = choice == shortcut ? .on : .off
            loveShortcutMenu.addItem(item)
        }
    }

    @objc private func chooseLoveShortcut(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        settings.loveShortcut = raw
        Log.write("Love shortcut: \((LoveShortcut(rawValue: raw) ?? .standard).description)")
        updateLoveShortcut()
    }

    @objc private func toggleNowPlayingNotification() {
        settings.nowPlayingNotification.toggle()
        Log.write(settings.nowPlayingNotification ? "Now playing notifications turned on" : "Now playing notifications turned off")
        updateUi()
    }

    /// The optional "now playing" notification, with album art when Apple's catalog has it.
    private func showNowPlaying(_ np: NowPlaying) {
        guard settings.nowPlayingNotification else { return }
        Task {
            var image: URL?
            for _ in 0..<8 {
                let (ready, links) = artwork.tryGet(artist: np.artist, title: np.title, album: np.album)
                if ready {
                    if let art = links?.artworkUrl, let url = URL(string: art), let (file, _) = try? await Http.download(url) {
                        let named = FileManager.default.temporaryDirectory.appendingPathComponent("now-playing-\(UUID().uuidString).jpg")
                        if (try? FileManager.default.moveItem(at: file, to: named)) != nil { image = named }
                    }
                    break
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            Notifier.shared.show(np.title, np.album.isEmpty ? np.artist : "\(np.artist) \u{2014} \(np.album)", image: image)
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

    @objc private func toggleCatchUp() {
        if settings.catchUp {
            settings.catchUp = false
            Log.write("Catch-up turned off")
            updateUi()
            return
        }
        let alert = NSAlert()
        alert.messageText = L("Catch up on plays from other devices?")
        alert.informativeText = L("Songs you play on your iPhone or iPad are recorded in your Music library and synced to this Mac through iCloud. Every 15 minutes the app looks for plays it didn't see here and that aren't on Last.fm yet, and scrobbles them with the time you played them. It starts with the last 24 hours.\n\n\u{2022} Only songs in your library count, and only the latest play of each song.\n\u{2022} It needs access to Music, and your Mac has to be on.\n\u{2022} If you use Scan in the Last.fm iPhone app, use one or the other: the same plays could be sent twice.")
        alert.addButton(withTitle: L("Turn On"))
        alert.addButton(withTitle: L("Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        settings.catchUp = true
        settings.catchUpSince = Date().addingTimeInterval(-24 * 3600)
        Log.write("Catch-up turned on (from the last 24 hours)")
        updateUi()
        Task {
            if reader.access != .granted { _ = await reader.requestAccess() }
            await catchUp()
        }
    }

    /// Finds plays from other devices in Music's history and queues the ones Last.fm doesn't have.
    private func catchUp() async {
        guard settings.catchUp, !settings.paused, !catchingUp, reader.access == .granted, !settings.username.isEmpty else { return }
        catchingUp = true
        defer { catchingUp = false }
        let now = Date()
        let since = max(settings.catchUpSince, now.addingTimeInterval(-CatchUp.maxAge))
        guard let plays = await reader.recentLibraryPlays(since: since) else { return }
        let candidates = CatchUp.missedPlays(plays, since: since, now: now, sightings: sightings, onLastFm: [], alreadySent: sentByCatchUp)
        guard let earliest = candidates.map(\.started).min() else { return }
        do {
            let onLastFm = try await api.recentTracks(user: settings.username, from: earliest.addingTimeInterval(-3600), to: now)
            let missed = CatchUp.missedPlays(plays, since: since, now: now, sightings: sightings, onLastFm: onLastFm, alreadySent: sentByCatchUp)
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            for play in missed {
                let queued = !dryRun && scrobbler.enqueueMissedPlay(play)
                let what = dryRun ? "[dry run] Would catch up: " : queued ? "Caught up: " : "Not catching up (ignored artist): "
                Log.write(what + "\(play.artist) - \(play.title), played \(formatter.string(from: play.started)) on another device")
                if !dryRun { sentByCatchUp.append(CatchUp.Sighting(key: play.key, first: play.playedDate, last: play.playedDate)) }
            }
            sentByCatchUp = sentByCatchUp.filter { now.timeIntervalSince($0.last) < 14 * 24 * 3600 }
            saveCatchUpState()
        } catch {
            Log.write("Catch-up skipped, couldn't read your Last.fm history: \(error.localizedDescriptionIfUseful)")
        }
    }

    private func saveCatchUpState() {
        lastSightingsSave = Date()
        guard !dryRun, let data = try? JSONEncoder().encode(CatchUpState(sightings: sightings, sent: sentByCatchUp)) else { return }
        try? FileManager.default.createDirectory(at: AppInfo.dataFolder, withIntermediateDirectories: true)
        try? data.write(to: Self.catchUpFile, options: .atomic)
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
        alert.informativeText = L("Scrobbles the Music app on your Mac to Last.fm.\nNot affiliated with Apple or Last.fm.")
        alert.addButton(withTitle: L("OK"))
        if !AppInfo.repoUrl.isEmpty { alert.addButton(withTitle: L("Open Project Page")) }
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
                if manual { Notifier.shared.show(L("You're up to date"), L("%@ %@ is the latest version.", AppInfo.name, AppInfo.version)) }
                return
            }
            update = release
            updateItem.title = L("\u{2B06} Update Available: %@", release.tag)
            updateItem.isHidden = false
            if manual || settings.updateNotifiedFor != release.tag {
                Log.write("Update available: \(release.tag)")
                settings.updateNotifiedFor = release.tag
                Notifier.shared.show(L("Update available"), L("%@ %@ is out. Click to install it.", AppInfo.name, release.tag), action: "install-update")
            }
        } catch {
            Log.write("Update check failed: \(error.localizedDescription)")
            if manual { Notifier.shared.show(L("Couldn't check for updates"), error.localizedDescription) }
        }
    }

    private func onAuthProblem() {
        if authWarningShown { return }
        authWarningShown = true
        Notifier.shared.show(L("Last.fm needs you to reconnect"),
                             L("Click the menu bar icon and choose Options › Switch Last.fm Account. Your scrobbles are saved until then."))
    }
}
