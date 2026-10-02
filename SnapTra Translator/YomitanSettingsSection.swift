import SwiftUI

struct YomitanSettingsSection: View {
    @EnvironmentObject private var model: AppModel

    private var dictionaryNames: [String] {
        Array(Set(model.detectedYomitanDictionaries + Array(model.settings.yomitanDictionaryLanguages.keys))).sorted()
    }

    private var assignedLanguages: [YomitanGlossaryLanguage] {
        var assigned = Set(model.settings.yomitanDictionaryLanguages.values)
        if model.settings.yomitanPreferredGlossaryLanguage != "all" {
            assigned.insert(model.settings.yomitanPreferredGlossaryLanguage)
        }
        return YomitanGlossaryLanguage.allCases.filter { assigned.contains($0.rawValue) }
    }

    var body: some View {
        SettingsSectionCard(title: L("Japanese Dictionaries"), icon: "character.book.closed") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    connectionIndicator
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connectionTitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                        Text(connectionDetail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Button(L("Check")) {
                        Task { await model.refreshYomitanStatus() }
                    }
                    .controlSize(.small)
                    .disabled(isChecking)
                }

                Link(L("Yomitan API setup guide"), destination: URL(string: "https://github.com/yomidevs/yomitan-api")!)
                    .font(.system(size: 11, weight: .medium))

                if dictionaryNames.isEmpty {
                    Text(L("No dictionary detected yet. Look up a Japanese word to discover your sources."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                } else {
                    Divider().padding(.vertical, 2)
                    Text(L("Assign each dictionary's glossary language. KakuTra never guesses it from a definition."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(dictionaryNames, id: \.self) { name in
                        HStack(spacing: 8) {
                            Text(name)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                                .help(name)
                            Spacer(minLength: 4)
                            Picker(name, selection: Binding(
                                get: { model.settings.yomitanDictionaryLanguages[name] ?? "" },
                                set: { model.setYomitanGlossaryLanguage($0, for: name) }
                            )) {
                                ForEach(YomitanGlossaryLanguage.allCases) { language in
                                    Text(language.title).tag(language.rawValue)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 150)
                        }
                    }
                }

                Divider().padding(.vertical, 2)
                HStack {
                    Text(L("Preferred glossary"))
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Picker(L("Preferred glossary"), selection: $model.settings.yomitanPreferredGlossaryLanguage) {
                        Text(L("All glossaries")).tag("all")
                        ForEach(assignedLanguages) { language in
                            Text(language.title).tag(language.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 165)
                }
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private var connectionIndicator: some View {
        switch model.yomitanConnectionState {
        case .checking:
            ProgressView().controlSize(.small).frame(width: 16, height: 16)
        case .connected:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 15))
        case .notConnected:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 15))
        }
    }

    private var isChecking: Bool {
        if case .checking = model.yomitanConnectionState { return true }
        return false
    }

    private var connectionTitle: String {
        switch model.yomitanConnectionState {
        case .checking: return L("Checking local API…")
        case .connected(let status):
            if let version = status.extensionVersion, !version.isEmpty {
                return "Yomitan · \(version)"
            }
            return L("Yomitan connected")
        case .notConnected: return L("Yomitan not connected")
        }
    }

    private var connectionDetail: String {
        switch model.yomitanConnectionState {
        case .checking: return L("Checking the local Yomitan service on this Mac.")
        case .connected: return L("Japanese lookups stay on this Mac.")
        case .notConnected: return L("Open your browser, start Yomitan, and enable its API.")
        }
    }
}
