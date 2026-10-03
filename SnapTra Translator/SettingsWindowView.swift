//
//  SettingsWindowView.swift
//  KakuTra
//
//  Settings window with unified 5-tab interface:
//  General, Dictionary, Anki, Learning, and About.
//

import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case dictionary = "Dictionary"
    case anki = "Anki"
    case learning = "Learning"
    case about = "About"
}

extension Notification.Name {
    static let switchSettingsTab = Notification.Name("switchSettingsTab")
}

enum SettingsWindowLayout {
    static let defaultContentWidth: CGFloat = 520
    static let dictionaryContentWidth: CGFloat = 520
    static let ankiContentWidth: CGFloat = 520
    static let learningContentWidth: CGFloat = 620
    static let aboutContentWidth: CGFloat = 520

    static let generalContentHeight: CGFloat = 520
    static let dictionaryContentHeight: CGFloat = 460
    static let ankiContentHeight: CGFloat = 560
    static let learningContentHeight: CGFloat = 540
    static let aboutContentHeight: CGFloat = 400
    static let aboutContentHeightWithChannelSelector: CGFloat = 500
    static let outerPadding: CGFloat = 16
    static let animationDuration: TimeInterval = 0.24

    static func contentWidth(for tab: SettingsTab) -> CGFloat {
        switch tab {
        case .learning:
            return learningContentWidth
        case .about:
            return aboutContentWidth
        default:
            return defaultContentWidth
        }
    }

    @MainActor static func contentHeight(for tab: SettingsTab) -> CGFloat {
        switch tab {
        case .general:
            return generalContentHeight
        case .dictionary:
            return dictionaryContentHeight
        case .anki:
            return ankiContentHeight
        case .learning:
            return learningContentHeight
        case .about:
            if UpdateChecker.shared.isGitHubRelease {
                return aboutContentHeightWithChannelSelector
            }
            #if DEBUG
            if SettingsStore.shared.debugShowChannelSelector {
                return aboutContentHeightWithChannelSelector
            }
            #endif
            return aboutContentHeight
        }
    }

    @MainActor static func windowContentSize(for tab: SettingsTab) -> CGSize {
        CGSize(
            width: contentWidth(for: tab) + (outerPadding * 2),
            height: contentHeight(for: tab) + (outerPadding * 2)
        )
    }
}

struct SettingsWindowView: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedTab: SettingsTab
    @State private var languageRefreshToken = UUID()
    @State private var hidesTabScrollIndicator = false
    @State private var scrollIndicatorResetWorkItem: DispatchWorkItem?
    @State private var window: NSWindow?
    var initialTab: SettingsTab = .general

    init(initialTab: SettingsTab = .general) {
        self.initialTab = initialTab
        _selectedTab = State(initialValue: initialTab)
    }

    private var currentContentWidth: CGFloat {
        SettingsWindowLayout.contentWidth(for: selectedTab)
    }

    private var currentContentHeight: CGFloat {
        SettingsWindowLayout.contentHeight(for: selectedTab)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView(
                hidesScrollIndicator: hidesTabScrollIndicator
            )
            .tabItem {
                Label(L("General"), systemImage: "gear")
            }
            .tag(SettingsTab.general)

            DictionarySettingsView(
                hidesScrollIndicator: hidesTabScrollIndicator
            )
            .tabItem {
                Label(L("Dictionary"), systemImage: "books.vertical")
            }
            .tag(SettingsTab.dictionary)

            AnkiSettingsView()
                .tabItem {
                    Label(L("Anki"), systemImage: "rectangle.stack.badge.plus")
                }
                .tag(SettingsTab.anki)

            LearningSettingsView(
                modelContext: model.modelContext,
                hidesScrollIndicator: hidesTabScrollIndicator
            )
            .tabItem {
                Label(L("Learning"), systemImage: "graduationcap")
            }
            .tag(SettingsTab.learning)

            AboutSettingsView(
                hidesScrollIndicator: hidesTabScrollIndicator
            )
            .tabItem {
                Label(L("About"), systemImage: "info.circle")
            }
            .tag(SettingsTab.about)
        }
        .background(
            SettingsWindowAccessor(window: $window)
        )
        .onReceive(NotificationCenter.default.publisher(for: .switchSettingsTab)) { notification in
            if let tab = notification.object as? SettingsTab {
                selectedTab = tab
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { _ in
            languageRefreshToken = UUID()
        }
        .onAppear {
            updateTabScrollIndicator(for: selectedTab, animated: false)
            resizeWindow(for: selectedTab, animated: false)
        }
        .onChange(of: selectedTab) { _, newValue in
            updateTabScrollIndicator(for: newValue, animated: true)
            resizeWindow(for: newValue, animated: true)
        }
        #if DEBUG
        .onChange(of: model.settings.debugShowChannelSelector) { _, _ in
            if selectedTab == .about {
                resizeWindowWithCurrentHeight(animated: true)
            }
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let closedWindow = notification.object as? NSWindow,
                  closedWindow == window else { return }
            DispatchQueue.main.async {
                (NSApp.delegate as? AppDelegate)?.hideDockIcon()
            }
        }
        .onDisappear {
            scrollIndicatorResetWorkItem?.cancel()
        }
        .id(languageRefreshToken)
        .frame(
            width: currentContentWidth,
            height: currentContentHeight
        )
        .padding(SettingsWindowLayout.outerPadding)
    }

    private func resizeWindow(for tab: SettingsTab, animated: Bool) {
        guard let window else { return }

        let targetContentSize = SettingsWindowLayout.windowContentSize(for: tab)
        var targetFrame = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: targetContentSize)
        )
        let currentFrame = window.frame

        targetFrame.origin.x = currentFrame.midX - targetFrame.width / 2
        targetFrame.origin.y = currentFrame.maxY - targetFrame.height

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = SettingsWindowLayout.animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                window.animator().setFrame(targetFrame, display: true)
            }
        } else {
            window.setFrame(targetFrame, display: true)
        }
    }

    private func resizeWindowWithCurrentHeight(animated: Bool) {
        guard let window else { return }

        let targetContentSize = CGSize(
            width: currentContentWidth + (SettingsWindowLayout.outerPadding * 2),
            height: currentContentHeight + (SettingsWindowLayout.outerPadding * 2)
        )
        var targetFrame = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: targetContentSize)
        )
        let currentFrame = window.frame

        targetFrame.origin.x = currentFrame.midX - targetFrame.width / 2
        targetFrame.origin.y = currentFrame.maxY - targetFrame.height

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = SettingsWindowLayout.animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                window.animator().setFrame(targetFrame, display: true)
            }
        } else {
            window.setFrame(targetFrame, display: true)
        }
    }

    private func updateTabScrollIndicator(for tab: SettingsTab, animated: Bool) {
        scrollIndicatorResetWorkItem?.cancel()
        hidesTabScrollIndicator = true

        let resetItem = DispatchWorkItem { [self] in
            hidesTabScrollIndicator = false
        }
        scrollIndicatorResetWorkItem = resetItem

        let delay: TimeInterval = animated ? (SettingsWindowLayout.animationDuration + 0.05) : 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: resetItem)
    }
}

// MARK: - General Settings View

struct GeneralSettingsView: View {
    @EnvironmentObject var model: AppModel
    var hidesScrollIndicator: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Raccourcis
                SettingsSectionCard(title: L("Shortcuts"), icon: "keyboard") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Touche d'immersion au survol (OCR instantané) :"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        HotkeyKeycapSelector(selectedKey: $model.settings.singleKey)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Immersion et Curseur
                SettingsSectionCard(title: L("Immersion"), icon: "cursorarrow.rays") {
                    VStack(spacing: 12) {
                        ToggleRow(
                            title: L("Listen at Cursor"),
                            subtitle: L("Pause or resume live lookup as you move the pointer"),
                            isOn: Binding(
                                get: { model.isListening },
                                set: { model.setListening($0) }
                            )
                        )

                        Divider().opacity(0.5)

                        ToggleRow(
                            title: L("Keep Translation Bubble After Tap"),
                            subtitle: L("Release the hotkey after one lookup; move the mouse to dismiss"),
                            isOn: $model.settings.keepWordOverlayAfterTap
                        )

                        Divider().opacity(0.5)

                        ToggleRow(
                            title: L("Prononciation vocale automatique"),
                            subtitle: L("Prononce le mot japonais lors du survol"),
                            isOn: $model.settings.playWordPronunciation
                        )

                        if model.settings.playWordPronunciation {
                            Divider().opacity(0.5)

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L("Genre de la voix"))
                                        .font(.system(size: 13))
                                    Text(L("Voix synthétique Apple macOS"))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Picker("", selection: $model.settings.voiceGender) {
                                    Text(L("Système")).tag(VoiceGenderPreference.system)
                                    Text(L("Féminin")).tag(VoiceGenderPreference.female)
                                    Text(L("Masculin")).tag(VoiceGenderPreference.male)
                                }
                                .labelsHidden()
                                .frame(width: 140)
                            }
                        }
                    }
                }

                // Système et Démarrage
                SettingsSectionCard(title: L("System"), icon: "gearshape") {
                    VStack(spacing: 12) {
                        ToggleRow(
                            title: L("Launch at Login"),
                            subtitle: L("Start automatically when you log in"),
                            isOn: $model.settings.launchAtLogin
                        )

                        Divider().opacity(0.5)

                        ToggleRow(
                            title: L("Show Menu Bar Icon"),
                            subtitle: L("Display app icon in the status bar"),
                            isOn: $model.settings.showMenuBarIcon
                        )

                        Divider().opacity(0.5)

                        MenuBarIconStylePickerRow(
                            style: $model.settings.menuBarIconStyle
                        )

                        Divider().opacity(0.5)

                        AppLanguagePickerRow(
                            language: $model.settings.appLanguage
                        )
                    }
                }

                // Autorisations
                SettingsSectionCard(title: L("Permissions"), icon: "lock.shield") {
                    VStack(spacing: 12) {
                        GeneralPermissionRow(
                            icon: "rectangle.dashed.badge.record",
                            title: L("Screen Recording"),
                            subtitle: L("Requis pour la détection OCR des textes japonais à l'écran"),
                            isGranted: model.permissions.status.screenRecording,
                            action: { model.permissions.requestAndOpenScreenRecording() }
                        )
                    }
                }
            }
            .padding()
            .background(
                ScrollViewScrollerConfigurator(
                    hidesVerticalScroller: hidesScrollIndicator
                )
            )
        }
        .scrollIndicators(hidesScrollIndicator ? .hidden : .automatic, axes: .vertical)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            Task { @MainActor in
                await model.permissions.refreshStatusAsync()
            }
        }
    }
}

// MARK: - Helper Rows

struct GeneralPermissionRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isGranted ? .green : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.primary)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(isGranted ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                        .shadow(color: isGranted ? .green.opacity(0.5) : .orange.opacity(0.5), radius: 3)

                    Text(isGranted ? L("Granted") : L("Required"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isGranted ? .green : .orange)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isGranted ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.25), value: isGranted)
    }
}

struct ToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.accentColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct AppLanguagePickerRow: View {
    @Binding var language: AppLanguage

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("App Language"))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                Text(L("Change the display language of the app"))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Picker("", selection: $language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(.accentColor)
            .frame(width: 140, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct MenuBarIconStylePickerRow: View {
    @Binding var style: MenuBarIconStyle

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Menu Bar Icon Style"))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                Text(L("Choose automatic, black, or white status bar icon rendering"))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Picker("", selection: $style) {
                ForEach(MenuBarIconStyle.allCases) { iconStyle in
                    Text(iconStyle.displayName).tag(iconStyle)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(.accentColor)
            .frame(width: 140, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct SettingsWindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.window = view.window
            view.window?.isReleasedWhenClosed = false
            view.window?.isRestorable = false
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if window == nil {
            DispatchQueue.main.async {
                self.window = nsView.window
                nsView.window?.isReleasedWhenClosed = false
                nsView.window?.isRestorable = false
            }
        }
    }
}

struct ScrollViewScrollerConfigurator: NSViewRepresentable {
    let hidesVerticalScroller: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureScrollView(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureScrollView(from: nsView)
        }
    }

    private func configureScrollView(from view: NSView) {
        guard let scrollView = findEnclosingScrollView(for: view) else { return }
        scrollView.hasVerticalScroller = !hidesVerticalScroller
    }

    private func findEnclosingScrollView(for view: NSView) -> NSScrollView? {
        var current: NSView? = view
        while let v = current {
            if let scrollView = v as? NSScrollView {
                return scrollView
            }
            current = v.superview
        }
        return nil
    }
}
