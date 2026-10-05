//
//  Snap_TranslateApp.swift
//  Snap Translate
//
//  Created by 杨玉杰 on 2026/1/12.
//

import AppKit
import Combine
import SwiftUI
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
    private var backgroundActivityToken: NSObjectProtocol?
    @MainActor lazy var model: AppModel = {
        AppModel()
    }()
    private var cancellables = Set<AnyCancellable>()
    private var statusItem: NSStatusItem?
    private weak var activeModeMenuItem: NSMenuItem?
    private var manualSettingsWindow: NSWindow?
    private var visibilityTask: Task<Void, Never>?
    private var isManualWindowOpen = false
    private var hasCompletedInitialLanguageAvailabilityCheck = false
    private var hasCompletedInitialSetup = UserDefaults.standard.bool(forKey: AppSettingKey.hasCompletedInitialSetup)

    override init() {
        super.init()
    }

    var settingsWindow: NSWindow? {
        if let manualSettingsWindow {
            return manualSettingsWindow
        }
        return NSApp.windows.first { window in
            !(window is NSPanel) &&
            !String(describing: type(of: window)).contains("StatusBar") &&
            (window.contentView is NSHostingView<SettingsWindowView> ||
             window.identifier?.rawValue.contains("Settings") == true ||
             window.title.contains("Settings") ||
             window.title == L("Settings"))
        }
    }

    // Store menu items that need state updates
    private weak var wordPronunciationMenuItem: NSMenuItem?
    private weak var listeningMenuItem: NSMenuItem?
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
        let oldStoreDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("KakuTra", isDirectory: true)
        for suffix in ["default.store", "default.store-shm", "default.store-wal"] {
            if let oldStoreDirectory {
                try? FileManager.default.removeItem(at: oldStoreDirectory.appendingPathComponent(suffix))
            }
        }
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

        model.$activeTranslationMode
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateDynamicMenuItems()
                }
            }
            .store(in: &cancellables)

        model.settings.$playWordPronunciation
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

        // Inter-process debug preview listener for visual validation & screenshots
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("kakuTraDebugPreview"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            let word = (note.userInfo?["word"] as? String) ?? (note.object as? String) ?? "猫"
            Task { @MainActor in
                await self?.model.showPreviewWordOverlay(word: word)
            }
        }

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
        if let closedWindow = notification.object as? NSWindow,
           closedWindow == manualSettingsWindow {
            manualSettingsWindow = nil
        }
        hideDockIcon()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window == settingsWindow else { return }
        isManualWindowOpen = true
    }

    @MainActor private func configureStatusItem() {
        guard model.settings.showMenuBarIcon else { return }
        
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = item.button {
            button.image = makeStatusBarImage()
            button.title = model.activeTranslationMode.statusItemTitle
            button.imagePosition = .imageLeading
            button.toolTip = L(model.isListening ? "KakuTra · Listening" : "KakuTra · Paused")
        }

        let menu = createStatusBarMenu()
        item.menu = menu

        statusItem = item
        updateDynamicMenuItems()
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

        let modeItem = NSMenuItem(
            title: model.activeTranslationMode.menuStatusTitle,
            action: nil,
            keyEquivalent: ""
        )
        modeItem.isEnabled = false
        menu.addItem(modeItem)
        self.activeModeMenuItem = modeItem

        menu.addItem(.separator())
        
        // Status section - toggle items with checkmarks
        // Explicit live listening toggle; listening always starts paused on launch.
        let listeningItem = NSMenuItem(
            title: statusBarModeActionTitle,
            action: #selector(toggleListening),
            keyEquivalent: ""
        )
        listeningItem.target = self
        menu.addItem(listeningItem)
        self.listeningMenuItem = listeningItem

        // Pronunciation toggle
        let pronunciationItem = NSMenuItem(
            title: L("Play Pronunciation"),
            action: #selector(toggleWordPronunciation),
            keyEquivalent: ""
        )
        pronunciationItem.target = self
        menu.addItem(pronunciationItem)
        self.wordPronunciationMenuItem = pronunciationItem

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
        wordPronunciationMenuItem?.state = model.settings.playWordPronunciation ? .on : .off

        listeningMenuItem?.title = statusBarModeActionTitle
        listeningMenuItem?.state = model.activeTranslationMode == .inactive ? .off : .on
        activeModeMenuItem?.title = model.activeTranslationMode.menuStatusTitle
        statusItem?.button?.title = model.activeTranslationMode.statusItemTitle
        statusItem?.button?.toolTip = model.activeTranslationMode.menuStatusTitle
        
        #if DEBUG
        // Update debug menu item state
        debugShowChannelMenuItem?.state = model.settings.debugShowChannelSelector ? .on : .off
        #endif
    }

    @MainActor private var statusBarModeActionTitle: String {
        switch model.activeTranslationMode {
        case .inactive: L("Start word tracking")
        case .word: L("Stop word tracking")
        case .screen: L("Stop screen translation")
        }
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

    @MainActor @objc private func toggleListening() {
        model.performStatusBarModeAction()
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
            NotificationCenter.default.post(name: .switchSettingsTab, object: initialTab)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let contentSize = SettingsWindowLayout.windowContentSize(for: initialTab)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L("Settings")
        window.identifier = NSUserInterfaceItemIdentifier("KakuTra.Settings")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: SettingsWindowView(initialTab: initialTab)
                .environmentObject(model)
        )
        manualSettingsWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
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

        // Accessibility only augments the Direct single-press lookup. OCR is
        // the fallback, so an Accessibility grant must never block setup.
        if !model.permissions.status.screenRecording {
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
        
        if !hasCompletedInitialSetup
            && model.permissions.status.screenRecording
        {
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
