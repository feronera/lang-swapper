import AppKit
import Carbon
import LangSwapperCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let inputSources = InputSources()
    private let store = UserStore()
    private var interceptor: Interceptor!
    private var statusItem: NSStatusItem!
    private var lastCorrectionItem = NSMenuItem(title: "No corrections yet", action: nil, keyEquivalent: "")
    private var permissionItem = NSMenuItem(title: "", action: #selector(openAccessibilitySettings), keyEquivalent: "")
    private var enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
    private var excludeItem = NSMenuItem(title: "", action: #selector(toggleExcludeFrontApp), keyEquivalent: "")
    private var matchLayoutItem = NSMenuItem(title: "Match layout to each app", action: #selector(toggleMatchLayout),
                                             keyEquivalent: "")
    private var loginItem = NSMenuItem(title: "Open at login", action: #selector(toggleOpenAtLogin), keyEquivalent: "")
    /// The last app that wasn't us; opening our menu doesn't change it.
    private var frontApp: NSRunningApplication?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        inputSources.reload()
        interceptor = Interceptor(detector: Dictionaries.makeDetector(), inputSources: inputSources, store: store)
        interceptor.onCorrection = { [weak self] c in
            self?.lastCorrectionItem.title = "Last: \(c.original) → \(c.replacement)"
        }
        buildMenu()
        observeSystem()
        setFrontApp(NSWorkspace.shared.frontmostApplication)
        startWhenTrusted()
    }

    // MARK: - Permissions

    private func startWhenTrusted() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options), interceptor.start() {
            permissionItem.isHidden = true
            return
        }
        permissionItem.title = "Grant Accessibility access…"
        permissionItem.isHidden = false
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self, AXIsProcessTrusted(), self.interceptor.start() else { return }
            timer.invalidate()
            self.permissionItem.isHidden = true
        }
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    // MARK: - Menu

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        enabledItem.target = self
        enabledItem.state = .on
        permissionItem.target = self
        lastCorrectionItem.isEnabled = false
        excludeItem.target = self
        matchLayoutItem.target = self
        matchLayoutItem.state = store.matchLayoutPerApp ? .on : .off
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(enabledItem)
        menu.addItem(excludeItem)
        menu.addItem(matchLayoutItem)
        menu.addItem(loginItem)
        menu.addItem(permissionItem)
        menu.addItem(.separator())
        menu.addItem(lastCorrectionItem)
        let hint = NSMenuItem(title: "⌃⌥Space converts the current word", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit LangSwapper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        refreshTitle()
    }

    private func refreshTitle() {
        let lang = inputSources.currentLanguage()?.shortName ?? "—"
        let active = interceptor.enabled && !store.isExcluded(frontApp?.bundleIdentifier)
        statusItem.button?.title = active ? lang : "\(lang)·off"
        let name = frontApp?.localizedName ?? "this app"
        excludeItem.title = "Disable in \(name)"
        excludeItem.state = store.isExcluded(frontApp?.bundleIdentifier) ? .on : .off
        excludeItem.isHidden = frontApp?.bundleIdentifier == nil
    }

    private func setFrontApp(_ app: NSRunningApplication?) {
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        frontApp = app
        interceptor.frontBundleID = app.bundleIdentifier
        matchLayout(to: app)
        refreshTitle()
    }

    /// Switches to the language the user usually types in `app`.
    private func matchLayout(to app: NSRunningApplication) {
        guard store.matchLayoutPerApp, interceptor.enabled, let id = app.bundleIdentifier, !store.isExcluded(id),
              let language = store.appLanguages.dominant(in: id), language != inputSources.currentLanguage() else { return }
        inputSources.select(language)
        NSLog("LangSwapper: \(app.localizedName ?? id) matched layout to its dominant language (\(language.rawValue))")
    }

    @objc private func toggleMatchLayout() {
        store.matchLayoutPerApp.toggle()
        matchLayoutItem.state = store.matchLayoutPerApp ? .on : .off
    }

    @objc private func toggleOpenAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSLog("LangSwapper: open at login failed: \(error.localizedDescription)")
        }
        loginItem.state = service.status == .enabled ? .on : .off
    }

    @objc private func toggleExcludeFrontApp() {
        guard let id = frontApp?.bundleIdentifier else { return }
        store.setExcluded(id, !store.isExcluded(id))
        interceptor.reset()
        refreshTitle()
    }

    @objc private func toggleEnabled() {
        interceptor.enabled.toggle()
        interceptor.reset()
        enabledItem.state = interceptor.enabled ? .on : .off
        refreshTitle()
    }

    // MARK: - Context changes that end the current word

    private func observeSystem() {
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                                object: nil, queue: .main) { [weak self] _ in
            self?.refreshTitle()
        }
        distributed.addObserver(forName: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
                                object: nil, queue: .main) { [weak self] _ in
            self?.inputSources.reload()
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.interceptor.reset()
            self?.setFrontApp(app)
        }
    }
}

enum Dictionaries {
    /// Looks in the app bundle first, then ./Data for `swift run` during development.
    static func url(for language: Language) -> URL? {
        let name = "\(language.rawValue)_50k"
        if let url = Bundle.main.url(forResource: name, withExtension: "txt") { return url }
        let dev = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Data/\(name).txt")
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }

    static func makeDetector() -> Detector {
        var dicts: [Language: FrequencyDictionary] = [:]
        for language in Language.allCases {
            if let url = url(for: language), let dict = try? FrequencyDictionary(url: url, splitCompounds: language == .thai) {
                dicts[language] = dict
            } else {
                NSLog("LangSwapper: missing dictionary for \(language.rawValue)")
            }
        }
        return Detector(dictionaries: dicts)
    }
}
