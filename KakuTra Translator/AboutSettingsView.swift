//
//  AboutSettingsView.swift
//  KakuTra
//
//  About tab for the settings window.
//

import SwiftUI

// MARK: - Shared version helper

private func appVersionString() -> String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    return "v\(version)"
}

// MARK: - About Settings Tab

struct AboutSettingsView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var updateChecker = UpdateChecker.shared
    var hidesScrollIndicator: Bool = false

    #if DEBUG
    /// Whether to show the update channel selector
    /// In DEBUG mode, checks both actual GitHub release status and debug override
    private var shouldShowChannelSelector: Bool {
        UpdateChecker.shared.isGitHubRelease || model.settings.debugShowChannelSelector
    }
    #else
    private var shouldShowChannelSelector: Bool {
        UpdateChecker.shared.isGitHubRelease
    }
    #endif

    private func checkForUpdates() {
        UpdateChecker.shared.checkForUpdatesWithUI()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // App Identity
                AppIdentityHeader()
                    .padding(.top, 4)

                // Project link
                VStack(spacing: 0) {
                    AboutLinkRow(
                        icon: "chevron.left.forwardslash.chevron.right",
                        iconColor: .primary,
                        title: "GitHub",
                        url: URL(string: "https://github.com/tristan-monticelli/KakuTra")!
                    )
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.background)
                        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
                        .shadow(color: .black.opacity(0.02), radius: 1, x: 0, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 0.5)
                )

                // Update Channel (GitHub Release only)
                if shouldShowChannelSelector {
                    UpdateChannelSelector()
                }

                // Check for Updates
                Button {
                    checkForUpdates()
                } label: {
                    HStack(spacing: 6) {
                        if updateChecker.isCheckingForUpdates {
                            Image(systemName: "arrow.2.circlepath")
                                .font(.system(size: 12, weight: .medium))
                                .rotationEffect(.degrees(updateChecker.isCheckingForUpdates ? 360 : 0))
                                .animation(
                                    updateChecker.isCheckingForUpdates
                                        ? Animation.linear(duration: 1).repeatForever(autoreverses: false)
                                        : .default,
                                    value: updateChecker.isCheckingForUpdates
                                )
                        } else {
                            Image(systemName: shouldShowChannelSelector ? "arrow.down.circle" : "sparkle")
                                .font(.system(size: 12, weight: .medium))
                        }
                        Text(updateChecker.isCheckingForUpdates
                             ? L("Checking for Updates...")
                             : (shouldShowChannelSelector ? L("Check for GitHub Updates") : L("Check for Updates")))
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(updateChecker.isCheckingForUpdates)

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Shared Sub-components

struct AppIdentityHeader: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)

            Text("KakuTra")
                .font(.system(size: 20, weight: .bold, design: .rounded))

            Text(appVersionString())
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)

            Text(L("Move your cursor over a word and press the shortcut to translate"))
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 20)
        }
    }
}

struct AboutLinkRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 22)

                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct UpdateChannelSelector: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            UpdateChannelRow(channel: .stable, isSelected: model.settings.updateChannel == .stable) {
                model.settings.updateChannel = .stable
            }
            Divider()
                .padding(.horizontal, 14)
                .opacity(0.5)
            UpdateChannelRow(channel: .beta, isSelected: model.settings.updateChannel == .beta) {
                model.settings.updateChannel = .beta
            }
        }
        .background(cardBackground)
        .overlay(cardBorder)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.background)
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
            .shadow(color: .black.opacity(0.02), radius: 1, x: 0, y: 1)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(.quaternary, lineWidth: 0.5)
    }
}

private struct UpdateChannelRow: View {
    let channel: UpdateChannel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                iconView
                textContentView
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var iconView: some View {
        let iconName = isSelected ? "checkmark.circle.fill" : "circle"
        let iconColor: Color = isSelected ? .accentColor : .secondary
        return Image(systemName: iconName)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(iconColor)
            .frame(width: 22)
    }

    private var textContentView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(channel.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)

            Text(channel.description)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}
