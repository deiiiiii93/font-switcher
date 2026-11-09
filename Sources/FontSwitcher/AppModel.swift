import AppKit
import CoreText
import FontSwitcherCore
import Observation
import UniformTypeIdentifiers

/// Where the app reads and writes. `FONTSWITCHER_HOME` (spec A7) redirects both the target
/// configs and the app's own state, so smoke tests never touch the real home.
struct AppPaths: Sendable {
    let home: URL
    let supportDir: URL
    let backupsDir: URL
    let stateFile: URL

    static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) -> AppPaths {
        let home: URL
        if let override = environment["FONTSWITCHER_HOME"], !override.isEmpty {
            home = URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser
        }
        let support = home.appendingPathComponent("Library/Application Support/FontSwitcher", isDirectory: true)
        return AppPaths(home: home, supportDir: support,
                        backupsDir: support.appendingPathComponent("backups", isDirectory: true),
                        stateFile: support.appendingPathComponent("state.json"))
    }
}

/// A transient result line shown in the main window and the menu bar panel.
struct Banner: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isError: Bool
}

@MainActor @Observable
final class AppModel {
    let paths: AppPaths
    let switcher: Switcher

    private(set) var state: AppState
    private(set) var families: [FontFamily] = []
    private(set) var fontsLoaded = false
    private(set) var isLoadingFonts = false
    private(set) var targetsLoaded = false
    private(set) var detected: Set<TargetID> = []
    private(set) var runningTargets: Set<TargetID> = []
    private(set) var currentFonts: [TargetID: FontChoice] = [:]
    private(set) var busyCount = 0
    var lastMessage: Banner?
    /// Display only: how many apps failed in the most recent apply (0 when it fully succeeded).
    private(set) var lastApplyFailures = 0
    /// Family selected in the Fonts view (kept here so it survives sidebar switches).
    var selectedFamilyName: String?

    @ObservationIgnored private let store: StateStore
    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private var fontReload: Task<Void, Never>?
    @ObservationIgnored private var fontGeneration = 0
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    init(paths: AppPaths = .resolve()) {
        self.paths = paths
        let store = StateStore(url: paths.stateFile)
        self.store = store
        self.state = store.load()
        self.switcher = Switcher(home: paths.home, backupsDir: paths.backupsDir,
                                 signaler: RunningAppSignaler(),
                                 isInstalled: Switcher.launchServicesIsInstalled)
        installStarterProfilesIfNeeded()
        observeSystem()
        Task {
            await refreshTargets()
            await reloadFonts()
        }
    }

    // MARK: - Derived

    var isBusy: Bool { busyCount > 0 }

    /// Targets that receive applies: the user's explicit set, else every detected target (spec D8).
    var enabledTargets: Set<TargetID> { state.enabledTargets ?? detected }

    var activeProfile: Profile? { state.profiles.first { $0.id == state.activeProfileID } }

    var monospacedNames: [String] { families.filter(\.isMonospaced).map(\.name) }

    /// Favorites that are still installed. A favorite removed elsewhere (Font Book, Finder) must never
    /// be written into configs by Fresh Day.
    var installedFavorites: [String] {
        let installed = Set(families.map(\.name))
        return state.favorites.filter { installed.contains($0) }
    }

    var freshDayPool: [String] { FreshDay.pool(favorites: installedFavorites, monospaced: monospacedNames) }

    var freshDayUsesFavorites: Bool { Set(installedFavorites).count >= 2 }

    /// Today's Fresh Day family, if one was applied today.
    var freshDayToday: String? {
        state.freshDay.lastDay == FreshDay.dayKey(Date(), calendar: .current) ? state.freshDay.lastFamily : nil
    }

    /// The family and size most enabled apps are on right now (for the menu bar summary).
    var currentSummary: FontChoice? {
        let fonts = TargetID.allCases.filter(enabledTargets.contains).compactMap { currentFonts[$0] }
        func dominant<T: Hashable>(_ values: [T]) -> T? {
            var counts: [T: Int] = [:]
            var best: (value: T, count: Int)?
            for v in values {
                let c = counts[v, default: 0] + 1
                counts[v] = c
                if c > best?.count ?? 0 { best = (v, c) }
            }
            return best?.value
        }
        let family = dominant(fonts.compactMap(\.family)) ?? activeProfile?.family
        let size = dominant(fonts.compactMap(\.size)) ?? activeProfile?.size
        return family == nil && size == nil ? nil : FontChoice(family: family, size: size)
    }

    /// True when the apps are currently on today's Fresh Day pick (not a profile or a manual choice).
    var isOnFreshDayFont: Bool {
        guard activeProfile == nil, let today = freshDayToday else { return false }
        return currentSummary?.family == today
    }

    func isFavorite(_ name: String) -> Bool { state.favorites.contains(name) }

    func family(named name: String?) -> FontFamily? {
        guard let name else { return nil }
        return families.first { $0.name == name }
    }

    // MARK: - System triggers

    private func observeSystem() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.checkFreshDay() }
        })
        observers.append(center.addObserver(forName: Notification.Name(kCTFontManagerRegisteredFontsChangedNotification as String),
                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleFontReload() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                                           object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.checkFreshDay() }
        })
    }

    /// Runs config-touching operations one at a time, in order.
    private func enqueue(_ operation: @escaping @MainActor @Sendable () async -> Void) {
        let previous = queue
        queue = Task { @MainActor [weak self] in
            await previous?.value
            self?.busyCount += 1
            await operation()
            self?.busyCount -= 1
        }
    }

    // MARK: - Fonts

    /// Coalesces bursts of font-registration notifications into one catalog reload.
    func scheduleFontReload() {
        fontReload?.cancel()
        fontReload = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await self?.reloadFonts()
        }
    }

    /// Loads the font catalog off the main actor (CoreText enumeration of ~700 families is slow).
    func reloadFonts() async {
        fontGeneration += 1
        let generation = fontGeneration
        isLoadingFonts = true
        let loaded = await Task.detached(priority: .userInitiated) { FontCatalog.families() }.value
        guard generation == fontGeneration else { return }
        families = loaded
        isLoadingFonts = false
        if selectedFamilyName == nil || family(named: selectedFamilyName) == nil {
            selectedFamilyName = activeProfile?.family ?? loaded.first(where: \.isMonospaced)?.name ?? loaded.first?.name
        }
        if !fontsLoaded {
            fontsLoaded = true
            checkFreshDay()
        }
    }

    func toggleFavorite(_ name: String) {
        if let i = state.favorites.firstIndex(of: name) {
            state.favorites.remove(at: i)
        } else {
            state.favorites.append(name)
        }
        persist()
    }

    func presentInstallPanel() {
        let panel = NSOpenPanel()
        panel.title = "Install Fonts"
        panel.prompt = "Install"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.font]
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        installFonts(panel.urls)
    }

    /// Copies font files into ~/Library/Fonts; fontd registers them and the catalog reloads.
    func installFonts(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let dir = FontCatalog.userFontsDir
        enqueue { [weak self] in
            let results = await Task.detached { FontInstaller.install(urls, into: dir) }.value
            var installed = 0
            var skipped: [String] = []
            for r in results {
                switch r {
                case .installed: installed += 1
                case let .skipped(url, reason): skipped.append("\(url.lastPathComponent): \(reason)")
                }
            }
            var parts: [String] = []
            if installed > 0 { parts.append("Installed \(installed) font file\(installed == 1 ? "" : "s")") }
            if !skipped.isEmpty { parts.append("Skipped " + skipped.joined(separator: ", ")) }
            self?.show(parts.joined(separator: " · "), isError: installed == 0)
            await self?.reloadFonts()
            // fontd registers copied files asynchronously; reload again shortly in case the
            // registered-fonts-changed notification doesn't arrive.
            if installed > 0 {
                // Outside the serial queue so Reroll/apply aren't blocked while we wait.
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    self?.scheduleFontReload()
                }
            }
        }
    }

    /// Moves a user-installed family's files to the Trash (the view confirms first).
    func removeFamily(_ family: FontFamily) {
        guard family.isUserInstalled else {
            show("\(family.name) is not a user-installed font and can't be removed here.", isError: true)
            return
        }
        let catalog = families
        let dir = FontCatalog.userFontsDir
        enqueue { [weak self] in
            do {
                try await Task.detached {
                    try FontInstaller.remove(family: family, catalog: catalog, userFontsDir: dir) {
                        try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
                    }
                }.value
                if let self, let i = self.state.favorites.firstIndex(of: family.name) {
                    self.state.favorites.remove(at: i)
                    self.persist()
                }
                self?.show("Moved \(family.name) to the Trash", isError: false)
            } catch let error as FontInstallerError {
                switch error {
                case .notUserInstalled:
                    self?.show("\(family.name) has files outside ~/Library/Fonts and can't be removed here.", isError: true)
                case let .sharedFile(other):
                    self?.show("\(family.name) shares a font file with \(other); remove it in Font Book instead.", isError: true)
                }
            } catch {
                self?.show("Could not remove \(family.name): \(error.localizedDescription)", isError: true)
            }
            await self?.reloadFonts()
        }
    }

    // MARK: - Targets

    /// Re-reads detection and current fonts (small config reads, done off the main actor anyway).
    func refreshTargets() async {
        let runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        runningTargets = Set(TargetID.allCases.filter {
            runningBundleIDs.contains(TargetSpec.spec(for: $0).bundleID)
        })
        let switcher = self.switcher
        let info = await Task.detached {
            TargetID.allCases.map { ($0, switcher.isDetected($0), switcher.currentFont(for: $0)) }
        }.value
        detected = Set(info.filter(\.1).map(\.0))
        currentFonts = Dictionary(uniqueKeysWithValues: info.compactMap { t, _, c in c.map { (t, $0) } })
        targetsLoaded = true
    }

    func configPath(for target: TargetID) -> String {
        Format.abbreviate(switcher.configURL(for: target).path, home: paths.home.path)
    }

    func toggleTarget(_ target: TargetID) {
        guard targetsLoaded else { return }
        var set = enabledTargets
        if set.contains(target) { set.remove(target) } else { set.insert(target) }
        state.enabledTargets = set
        persist()
    }

    // MARK: - Applying

    func apply(_ profile: Profile) {
        enqueue { [weak self] in
            guard let self else { return }
            let results = await self.runApply(profile.choices(for: self.enabledTargets))
            if results.contains(where: { if case .failed = $0.outcome { false } else { true } }) {
                self.state.activeProfileID = profile.id
                self.persist()
            }
            self.report(results, prefix: profile.name)
        }
    }

    func applyFamily(_ family: String, size: Double?) {
        enqueue { [weak self] in
            guard let self else { return }
            let choice = FontChoice(family: family, size: size)
            let results = await self.runApply(Dictionary(uniqueKeysWithValues: self.enabledTargets.map { ($0, choice) }))
            self.state.activeProfileID = nil
            self.persist()
            self.report(results, prefix: nil)
        }
    }

    /// Undo skipped apps whose settings changed after the switch. Never leave that silent:
    /// ask whether to overwrite the later edits from the backup or keep the current files.
    private func resolveUndoConflict(sequence: Int, targets: [TargetID]) async {
        let names = Self.names(targets)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(names) \(targets.count == 1 ? "was" : "were") not restored"
        alert.informativeText = """
            \(names) changed \(targets.count == 1 ? "its" : "their") settings file after the font switch \
            (for example, a setting you changed in the app), so Undo left \(targets.count == 1 ? "it" : "them") \
            on the new font to avoid wiping those changes.

            Restore Anyway puts back the file from before the switch. Any edits made since then are lost.
            Keep Current leaves the file as it is. To get the old font back, set it in the app or apply a profile.
            """
        alert.addButton(withTitle: "Keep Current")
        let restore = alert.addButton(withTitle: "Restore Anyway")
        restore.hasDestructiveAction = true
        NSApp.activate()
        let choice = alert.runModal()

        let switcher = self.switcher
        if choice == .alertSecondButtonReturn {
            do {
                let forced = try await Task.detached { try switcher.forceRestore(sequence: sequence, targets: targets) }.value
                var parts = ["Restored " + Self.names(forced.restored) + " (later edits overwritten)"]
                if !forced.failed.isEmpty { parts.append("failed: " + Self.names(forced.failed)) }
                show("Undo · " + parts.joined(separator: " · "), isError: !forced.failed.isEmpty)
            } catch {
                show("Restore failed: \(error.localizedDescription)", isError: true)
            }
        } else {
            await Task.detached { switcher.discardUndo(sequence: sequence, targets: targets) }.value
            show("Undo · \(names) kept as \(targets.count == 1 ? "is" : "they are"); set \(targets.count == 1 ? "its" : "their") font by hand or apply a profile",
                 isError: true)
        }
    }

    func undo() {
        enqueue { [weak self] in
            guard let self else { return }
            let switcher = self.switcher
            do {
                let result = try await Task.detached { try switcher.undoLast() }.value
                var parts: [String] = []
                parts.append(result.restored.isEmpty ? "Nothing restored" : "Restored " + Self.names(result.restored))
                if !result.skippedModified.isEmpty {
                    parts.append("left alone (edited since the switch): " + Self.names(result.skippedModified))
                }
                if !result.failed.isEmpty { parts.append("failed: " + Self.names(result.failed)) }
                self.state.activeProfileID = nil
                self.persist()
                self.show("Undo · " + parts.joined(separator: " · "),
                          isError: !result.failed.isEmpty || !result.skippedModified.isEmpty || result.restored.isEmpty)
                if let sequence = result.pendingSequence, !result.skippedModified.isEmpty {
                    await self.resolveUndoConflict(sequence: sequence, targets: result.skippedModified)
                }
            } catch SwitcherError.nothingToUndo {
                self.show("Nothing to undo", isError: false)
            } catch {
                self.show("Undo failed: \(error.localizedDescription)", isError: true)
            }
            await self.refreshTargets()
        }
    }

    private func runApply(_ choices: [TargetID: FontChoice]) async -> [ApplyResult] {
        guard !choices.isEmpty else { return [] }
        let switcher = self.switcher
        let results = await Task.detached { switcher.apply(choices) }.value
        await refreshTargets()
        return results
    }

    /// "Applied to 5 apps · Ghostty: … · VS Code failed: …"
    private func report(_ results: [ApplyResult], prefix: String?) {
        guard !results.isEmpty else {
            show("No apps are enabled — turn some on in the strip below or in Apps.", isError: true)
            return
        }
        var written = 0, unchanged = 0
        var notes: [String] = []
        var problems: [String] = []
        for r in results {
            switch r.outcome {
            case .written:
                written += 1
                if let note = TargetSpec.spec(for: r.target).note { notes.append("\(r.target.displayName): \(note)") }
            case .unchanged: unchanged += 1
            case let .skipped(reason): problems.append("\(r.target.displayName) skipped: \(reason)")
            case let .failed(message): problems.append("\(r.target.displayName) failed: \(message)")
            }
        }
        lastApplyFailures = results.count { if case .failed = $0.outcome { true } else { false } }
        var parts: [String] = []
        if let prefix { parts.append(prefix) }
        if written > 0 { parts.append("Applied to \(written) app\(written == 1 ? "" : "s")") }
        if unchanged > 0 { parts.append("\(unchanged) already set") }
        parts += problems + notes
        show(parts.joined(separator: " · "), isError: results.contains { if case .failed = $0.outcome { true } else { false } })
    }

    private static func names(_ targets: [TargetID]) -> String {
        targets.map(\.displayName).joined(separator: ", ")
    }

    func show(_ text: String, isError: Bool) {
        lastMessage = Banner(text: text, isError: isError)
    }

    // MARK: - Profiles

    private func installStarterProfilesIfNeeded() {
        guard !state.starterProfilesInstalled else { return }
        let existingNames = Set(state.profiles.map { $0.name.lowercased() })
        state.profiles.append(contentsOf: StarterProfiles.all.filter {
            !existingNames.contains($0.name.lowercased())
        })
        state.starterProfilesInstalled = true
        persist()
    }

    @discardableResult
    func saveProfile(name: String, family: String, size: Double?) -> Profile {
        let profile = Profile(name: name, family: family, size: size)
        state.profiles.append(profile)
        persist()
        return profile
    }

    func updateProfile(_ profile: Profile) {
        guard let i = state.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        state.profiles[i] = profile
        persist()
    }

    func deleteProfile(_ id: UUID) {
        state.profiles.removeAll { $0.id == id }
        if state.activeProfileID == id { state.activeProfileID = nil }
        persist()
    }

    // MARK: - Fresh Day (spec D10/A10)

    func setFreshDayEnabled(_ enabled: Bool) {
        state.freshDay.enabled = enabled
        persist()
        if enabled { checkFreshDay() }
    }

    /// Applies today's pick if Fresh Day is on and hasn't run today. Every trigger funnels through here.
    func checkFreshDay() {
        enqueue { [weak self] in await self?.runFreshDay(reroll: false) }
    }

    func rerollFreshDay() {
        enqueue { [weak self] in await self?.runFreshDay(reroll: true) }
    }

    private func runFreshDay(reroll: Bool) async {
        guard fontsLoaded, state.freshDay.enabled else { return }
        let pool = freshDayPool
        let now = Date()
        let calendar = Calendar.current
        let decision = reroll
            ? FreshDayEngine.reroll(now: now, calendar: calendar, state: state.freshDay, pool: pool)
            : FreshDayEngine.decide(now: now, calendar: calendar, state: state.freshDay, pool: pool)
        guard let decision else {
            if reroll || pool.isEmpty { show("Fresh Day has no fonts to pick from.", isError: true) }
            return
        }
        let choice = FontChoice(family: decision.family, size: nil)
        let results = await runApply(Dictionary(uniqueKeysWithValues: enabledTargets.map { ($0, choice) }))
        // Recorded even when some targets failed, so wake/day-change triggers don't retry all day.
        FreshDayEngine.record(decision, into: &state.freshDay)
        state.activeProfileID = nil
        persist()
        report(results, prefix: "Fresh Day: \(decision.family)")
    }

    // MARK: - Persistence

    /// Saves after every mutation, synchronously: the state file is a few KB, and a synchronous
    /// write cannot be lost when the user quits right after a change.
    private func persist() {
        do {
            try store.save(state)
        } catch {
            show("Could not save settings: \(error.localizedDescription)", isError: true)
        }
    }
}
