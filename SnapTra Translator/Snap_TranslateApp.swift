//
//  Snap_TranslateApp.swift
//  Snap Translate
//
//  Created by 杨玉杰 on 2026/1/12.
//

import AppKit
import Combine
import SwiftUI
import SwiftData
import Translation
import os.log

@main
struct Snap_TranslateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsWindowView()
                .environmentObject(appDelegate.model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private static let logger = Logger(subsystem: "com.tristanmonticelli.KakuTra", category: "AppDelegate")
    private let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    private let modelContainer: ModelContainer
    private let modelContainerDidFallBackToMemory: Bool
    private var backgroundActivityToken: NSObjectProtocol?
    @MainActor lazy var model: AppModel = {
        AppModel(modelContext: modelContainer.mainContext)
    }()
    private var cancellables = Set<AnyCancellable>()
    private var statusItem: NSStatusItem?
    private var visibilityTask: Task<Void, Never>?
    private var isManualWindowOpen = false
    private var hasCompletedInitialLanguageAvailabilityCheck = false
    private var hasCompletedInitialSetup = UserDefaults.standard.bool(forKey: AppSettingKey.hasCompletedInitialSetup)

    override init() {
        let schema = Schema([WordRecord.self])
        let storeDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("KakuTra", isDirectory: true)
        let persistentConfiguration = ModelConfiguration(
            schema: schema,
            url: storeDirectory.appendingPathComponent("default.store")
        )
        do {
            try FileManager.default.createDirectory(
                at: storeDirectory,
                withIntermediateDirectories: true
            )
            modelContainer = try ModelContainer(for: schema, configurations: [persistentConfiguration])
            modelContainerDidFallBackToMemory = false
        } catch {
            // Avoid crashing on disk / migration / quota failures (especially under
            // App Store sandbox). Fall back to an in-memory store so the app keeps
            // running; the user just won't have persistent learning history this
            // session. We surface this through Logger and the About screen later.
            Self.logger.error("Persistent SwiftData container failed: \(error.localizedDescription, privacy: .public). Falling back to in-memory store.")
            do {
                let memoryConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                modelContainer = try ModelContainer(for: schema, configurations: [memoryConfiguration])
                modelContainerDidFallBackToMemory = true
            } catch {
                // If even the in-memory container can't be created, we genuinely
                // cannot continue — but log first so crash reports are actionable.
                Self.logger.fault("In-memory SwiftData container also failed: \(error.localizedDescription, privacy: .public)")
                fatalError("Failed to initialize SwiftData model container: \(error)")
            }
        }
        super.init()
    }

    var settingsWindow: NSWindow? {
        NSApp.windows.first { window in
            !(window is NSPanel) &&
            !String(describing: type(of: window)).contains("StatusBar") &&
            (window.contentView is NSHostingView<SettingsWindowView> ||
             window.identifier?.rawValue.contains("Settings") == true ||
             window.title.contains("Settings") ||
             window.title == L("Settings"))
        }
    }

    // Store menu items that need state updates
    private weak var pronunciationMenuItem: NSMenuItem?
    private weak var wordPronunciationMenuItem: NSMenuItem?
    private weak var sentencePronunciationMenuItem: NSMenuItem?
    private weak var listeningMenuItem: NSMenuItem?
    private weak var providerInfoMenuItem: NSMenuItem?
    #if DEBUG
    private weak var debugShowChannelMenuItem: NSMenuItem?
    #endif

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    func application(_ app: NSApplication, shouldSaveApplicationState coder: NSCoder) -> Bool {
        false
    }

    func application(_ app: NSApplication, shouldRestoreApplicationState coder: NSCoder) -> Bool {
        false
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !isRunningTests else { return }
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": false])
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame com_apple_SwiftUI_Settings_window")
        if model.settings.showDockIcon {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningTests else { return }

        // Keep the menu bar utility alive even when it has no visible windows.
        // `disableAutomaticTermination` blocks Cocoa's "automatic termination"
        // path; `disableSuddenTermination` is also required so the system does
        // not SIGKILL us under memory pressure / logout / idle conditions —
        // this is the dominant cause of App Store users seeing the app
        // disappear in the background.
        ProcessInfo.processInfo.disableAutomaticTermination("KakuTra is a menu bar utility that must remain running")
        ProcessInfo.processInfo.disableSuddenTermination()

        // Hold a long-lived activity assertion so App Nap doesn't freeze our
        // global hotkey monitor / OCR pipeline while the app sits idle in the
        // menu bar. We pair this with `endActivity` in
        // `applicationWillTerminate`.
        backgroundActivityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "KakuTra menu bar agent"
        )

        if modelContainerDidFallBackToMemory {
            Self.logger.warning("Running with in-memory SwiftData store; learning history will not persist this session.")
        }

        MemoryMonitor.shared.start()
        configureStatusItem()
        checkPermissionGrantRestart()

        model.permissions.$status
            .sink { [weak self] _ in
                self?.scheduleVisibilityUpdate()
            }
            .store(in: &cancellables)

        model.$isListening
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateDynamicMenuItems()
                }
            }
            .store(in: &cancellables)

        model.settings.$playWordPronunciation
            .combineLatest(model.settings.$playSentencePronunciation)
            .combineLatest(model.settings.$wordTTSProvider)
            .combineLatest(model.settings.$sentenceTTSProvider)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateDynamicMenuItems()
                }
            }
            .store(in: &cancellables)

        model.settings.$sourceLanguage
            .combineLatest(model.settings.$targetLanguage)
            .sink { [weak self] _, _ in
                self?.scheduleVisibilityUpdate()
            }
            .store(in: &cancellables)

        model.settings.$showMenuBarIcon
            .sink { [weak self] show in
                Task { @MainActor in
                    self?.updateStatusItemVisibility(show: show)
                }
            }
            .store(in: &cancellables)

        model.settings.$menuBarIconStyle
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateStatusItemImage()
                }
            }
            .store(in: &cancellables)

        model.settings.$showDockIcon
            .sink { [weak self] show in
                Task { @MainActor in
                    self?.updateDockIconVisibility(show: show)
                }
            }
            .store(in: &cancellables)

        // Listen for language changes to update menu
        NotificationCenter.default.publisher(for: .languageChanged)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateMenuLanguage()
                }
            }
            .store(in: &cancellables)

        #if DEBUG
        // Listen for debugShowChannelSelector changes to refresh settings window size
        model.settings.$debugShowChannelSelector
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshSettingsWindowSize()
                }
            }
            .store(in: &cancellables)
        #endif

        // Initialize localization manager with saved language
        LocalizationManager.shared.setLanguage(model.settings.appLanguage)

        // Initialize Sparkle auto-updater
        UpdateChecker.shared.initialize()
        UpdateChecker.shared.startAutoCheckIfNeeded()

        // Load initial setup state from UserDefaults
        hasCompletedInitialSetup = UserDefaults.standard.bool(forKey: AppSettingKey.hasCompletedInitialSetup)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            guard let window = notification.object as? NSWindow else { return }
            if window == self.settingsWindow {
                Task { @MainActor in
                    self.hideDockIcon()
                }
            }
        }

        Task {
            await refreshAndUpdateVisibility()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let token = backgroundActivityToken {
            ProcessInfo.processInfo.endActivity(token)
            backgroundActivityToken = nil
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings(initialTab: .general)
        return true
    }

    @MainActor func windowWillClose(_ notification: Notification) {
        hideDockIcon()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window == settingsWindow else { return }
        isManualWindowOpen = true
    }

    @MainActor private func configureStatusItem() {
        guard model.settings.showMenuBarIcon else { return }
        
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = item.button {
            button.image = makeStatusBarImage()
            button.imagePosition = .imageOnly
            button.toolTip = L(model.isListening ? "KakuTra · Listening" : "KakuTra · Paused")
        }

        let menu = createStatusBarMenu()
        item.menu = menu

        statusItem = item
    }

    @MainActor private func updateStatusItemVisibility(show: Bool) {
        if show {
            if statusItem == nil {
                configureStatusItem()
            } else {
                updateStatusItemImage()
            }
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        }
    }

    @MainActor private func updateStatusItemImage() {
        statusItem?.button?.image = makeStatusBarImage()
    }

    @MainActor private func createStatusBarMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        
        // Header section - KakuTra title (styled as header, not disabled item)
        let titleItem = createHeaderMenuItem(title: "KakuTra")
        menu.addItem(titleItem)
        
        menu.addItem(.separator())
        
        // Status section - toggle items with checkmarks
        // Explicit live listening toggle; listening always starts paused on launch.
        let listeningItem = NSMenuItem(
            title: L(model.isListening ? "Pause Listening" : "Resume Listening"),
            action: #selector(toggleListening),
            keyEquivalent: ""
        )
        listeningItem.target = self
        menu.addItem(listeningItem)
        self.listeningMenuItem = listeningItem

        // Pronunciation submenu
        let pronunciationSubmenu = NSMenu()
        
        let wordPronunciationItem = NSMenuItem(
            title: L("Word"),
            action: #selector(toggleWordPronunciation),
            keyEquivalent: ""
        )
        wordPronunciationItem.target = self
        pronunciationSubmenu.addItem(wordPronunciationItem)
        self.wordPronunciationMenuItem = wordPronunciationItem
        
        let sentencePronunciationItem = NSMenuItem(
            title: L("Sentence"),
            action: #selector(toggleSentencePronunciation),
            keyEquivalent: ""
        )
        sentencePronunciationItem.target = self
        pronunciationSubmenu.addItem(sentencePronunciationItem)
        self.sentencePronunciationMenuItem = sentencePronunciationItem
        
        // Provider info in submenu
        let providerItem = NSMenuItem(
            title: "",
            action: nil,
            keyEquivalent: ""
        )
        providerItem.isEnabled = false
        providerItem.indentationLevel = 1
        pronunciationSubmenu.addItem(providerItem)
        self.providerInfoMenuItem = providerItem
        
        let pronunciationMenuItem = NSMenuItem(
            title: L("Pronunciation"),
            action: nil,
            keyEquivalent: ""
        )
        pronunciationMenuItem.submenu = pronunciationSubmenu
        menu.addItem(pronunciationMenuItem)
        self.pronunciationMenuItem = pronunciationMenuItem

        // Actions section
        // Settings
        let settingsItem = NSMenuItem(
            title: L("Settings..."),
            action: #selector(openSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        // About
        let aboutItem = NSMenuItem(
            title: L("About KakuTra"),
            action: #selector(openAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        #if DEBUG
        // Debug section
        menu.addItem(.separator())

        // Debug: Show Update Channel Selector
        let debugShowChannelItem = NSMenuItem(
            title: "GitHub Release",
            action: #selector(toggleDebugShowChannelSelector),
            keyEquivalent: ""
        )
        debugShowChannelItem.target = self
        menu.addItem(debugShowChannelItem)
        self.debugShowChannelMenuItem = debugShowChannelItem
        #endif

        // Quit
        let quitItem = NSMenuItem(
            title: L("Quit"),
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        
        // Update dynamic menu item states
        updateDynamicMenuItems()
        
        return menu
    }
    
    /// Creates a header-style menu item that looks like a title rather than a disabled item
    private func createHeaderMenuItem(title: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false
        
        // Use attributed string for better visual hierarchy
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        item.attributedTitle = NSAttributedString(string: title, attributes: attributes)
        
        return item
    }

    @MainActor private func updateDynamicMenuItems() {
        // Update pronunciation submenu item states
        wordPronunciationMenuItem?.state = model.settings.playWordPronunciation ? .on : .off
        sentencePronunciationMenuItem?.state = model.settings.playSentencePronunciation ? .on : .off

        listeningMenuItem?.title = L(model.isListening ? "Pause Listening" : "Resume Listening")
        listeningMenuItem?.state = model.isListening ? .on : .off
        statusItem?.button?.toolTip = L(model.isListening ? "KakuTra · Listening" : "KakuTra · Paused")
        
        // Update provider info item to show both Word and Sentence providers
        let wordProvider = model.settings.wordTTSProvider
        let sentenceProvider = model.settings.sentenceTTSProvider
        let wordName = wordProvider == .apple ? L("System") : wordProvider.displayName
        let sentenceName = sentenceProvider == .apple ? L("System") : sentenceProvider.displayName
        let providerTitle = "\(L("Word")): \(wordName)  ·  \(L("Sentence")): \(sentenceName)"
        
        // Style the provider info with secondary color
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        providerInfoMenuItem?.attributedTitle = NSAttributedString(
            string: providerTitle,
            attributes: attributes
        )
        
        #if DEBUG
        // Update debug menu item state
        debugShowChannelMenuItem?.state = model.settings.debugShowChannelSelector ? .on : .off
        #endif
    }

    @MainActor private func updateMenuLanguage() {
        // Recreate menu with new language
        if let item = statusItem {
            let menu = createStatusBarMenu()
            item.menu = menu
        }
    }

    // MARK: - NSMenuDelegate

    @MainActor func menuWillOpen(_ menu: NSMenu) {
        // Update menu item states before showing
        updateDynamicMenuItems()
    }

    // This method is kept for compatibility but no longer used
    // When statusItem.menu is set, the system handles menu display automatically
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {}

    @MainActor @objc private func toggleWordPronunciation() {
        model.settings.playWordPronunciation.toggle()
    }

    @MainActor @objc private func toggleSentencePronunciation() {
        model.settings.playSentencePronunciation.toggle()
    }

    @MainActor @objc private func toggleListening() {
        model.setListening(!model.isListening)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @MainActor @objc private func openAbout() {
        openSettings(initialTab: .about)
    }

    @MainActor @objc func openSettingsWindow() {
        openSettings(initialTab: .general)
    }

    @MainActor
    func openSettings(initialTab: SettingsTab = .general) {
        isManualWindowOpen = true
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .switchSettingsTab, object: initialTab)
        if let window = settingsWindow, window.isVisible {
            DispatchQueue.main.async {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        } else {
            DispatchQueue.main.async {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    self.settingsWindow?.makeKeyAndOrderFront(nil)
                }
            }
        }
    }

    @MainActor private func makeStatusBarImage() -> NSImage? {
        guard let sourceImage = NSImage(named: "StatusBarIcon") ?? NSApp.applicationIconImage else {
            return nil
        }

        let size = NSSize(width: 18, height: 18)
        switch model.settings.menuBarIconStyle {
        case .auto:
            guard let image = sourceImage.copy() as? NSImage else { return nil }
            image.size = size
            image.isTemplate = true
            return image
        case .black:
            return fixedStatusBarImage(from: sourceImage, color: .black, size: size)
        case .white:
            return fixedStatusBarImage(from: sourceImage, color: .white, size: size)
        }
    }

    private func fixedStatusBarImage(from sourceImage: NSImage, color: NSColor, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(origin: .zero, size: size)
        sourceImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        color.setFill()
        rect.fill(using: .sourceAtop)
        image.isTemplate = false
        return image
    }

    private func checkPermissionGrantRestart() {
        let currentStatus = CGPreflightScreenCaptureAccess()
        UserDefaults.standard.set(currentStatus, forKey: AppSettingKey.lastScreenRecordingStatus)
    }

    private func refreshAndUpdateVisibility() async {
        await model.permissions.refreshStatusAsync()
        await updateVisibilityFromCurrentState()
    }

    private func scheduleVisibilityUpdate() {
        visibilityTask?.cancel()
        visibilityTask = Task { [weak self] in
            await self?.updateVisibilityFromCurrentState()
        }
    }

    @MainActor
    private func updateVisibilityFromCurrentState() async {
        if hasCompletedInitialSetup {
            return
        }

        let needsScreenRecording = !model.permissions.status.screenRecording

        if needsScreenRecording {
            openSettings(initialTab: .general)
        } else {
            hasCompletedInitialSetup = true
            UserDefaults.standard.set(true, forKey: AppSettingKey.hasCompletedInitialSetup)
            if !isManualWindowOpen {
                hideDockIcon()
            }
        }
    }

    @MainActor func hideDockIcon() {
        isManualWindowOpen = false
        settingsWindow?.orderOut(nil)
        if !model.settings.showDockIcon {
            NSApp.setActivationPolicy(.accessory)
        }
        
        if !hasCompletedInitialSetup && model.permissions.status.screenRecording {
            hasCompletedInitialSetup = true
            UserDefaults.standard.set(true, forKey: AppSettingKey.hasCompletedInitialSetup)
        }
    }

    @MainActor
    private func updateDockIconVisibility(show: Bool) {
        if show {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    #if DEBUG
    @objc private func toggleDebugShowChannelSelector() {
        model.settings.debugShowChannelSelector.toggle()
        updateDynamicMenuItems()
    }

    @MainActor
    private func refreshSettingsWindowSize() {
        guard let window = settingsWindow, window.isVisible else { return }
        NotificationCenter.default.post(name: .switchSettingsTab, object: SettingsTab.about)
    }
    #endif
}

@available(macOS 15.0, *)
class TranslationServiceWindowHolder {
    static let shared = TranslationServiceWindowHolder()
    var window: NSWindow?
    private init() {}
}
