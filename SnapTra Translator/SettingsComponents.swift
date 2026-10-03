import SwiftUI

struct SettingsSectionCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
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
    }
}

struct HotkeyKeycapSelector: View {
    @Binding var selectedKey: SingleKey

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                button(for: SingleKey.leftShift)

                Text(L("Hotkey"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)

                button(for: SingleKey.rightShift)
            }

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    button(for: SingleKey.fn)
                    button(for: SingleKey.leftControl)
                    button(for: SingleKey.leftOption)
                    button(for: SingleKey.leftCommand)
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    button(for: SingleKey.rightCommand)
                    button(for: SingleKey.rightOption)
                    button(for: SingleKey.rightControl)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func button(for key: SingleKey) -> some View {
        Button {
            selectedKey = key
        } label: {
            HotkeyKeycapButton(
                symbol: symbol(for: key),
                tooltip: tooltip(for: key),
                isSelected: selectedKey == key
            )
        }
        .buttonStyle(.plain)
    }

    private func symbol(for key: SingleKey) -> String {
        switch key {
        case .leftShift, .rightShift:
            return "⇧"
        case .leftControl, .rightControl:
            return "⌃"
        case .leftOption, .rightOption:
            return "⌥"
        case .leftCommand, .rightCommand:
            return "⌘"
        case .fn:
            return "Fn"
        }
    }

    private func tooltip(for key: SingleKey) -> String {
        switch key {
        case .leftShift:
            return L("Left Shift")
        case .rightShift:
            return L("Right Shift")
        case .leftControl:
            return L("Left Control")
        case .rightControl:
            return L("Right Control")
        case .leftOption:
            return L("Left Option")
        case .rightOption:
            return L("Right Option")
        case .leftCommand:
            return L("Left Command")
        case .rightCommand:
            return L("Right Command")
        case .fn:
            return "Fn"
        }
    }
}

private struct HotkeyKeycapButton: View {
    let symbol: String
    let tooltip: String
    let isSelected: Bool

    @State private var isHovering = false
    @State private var showTooltip = false
    @State private var hoverWorkItem: DispatchWorkItem?

    var body: some View {
        Text(symbol)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .overlay(alignment: .top) {
                if showTooltip {
                    Text(tooltip)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: true, vertical: false)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(nsColor: .windowBackgroundColor))
                                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        )
                        .offset(y: -26)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isSelected)
            .onHover { hovering in
                isHovering = hovering
                hoverWorkItem?.cancel()
                if hovering {
                    let workItem = DispatchWorkItem {
                        if isHovering {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showTooltip = true
                            }
                        }
                    }
                    hoverWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
                } else {
                    showTooltip = false
                }
            }
    }
}

