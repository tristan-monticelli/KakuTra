//
//  DictionarySettingsSection.swift
//  KakuTra
//
//  Settings for the installed offline language dictionaries.
//

import AppKit
import SwiftUI

struct DictionarySettingsSection: View {
    @EnvironmentObject private var model: AppModel

    private var totalEntriesFormatted: String {
        let count = model.localDictionaryService.totalEntriesCount
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    var body: some View {
        SettingsSectionCard(title: L("Dictionnaire"), icon: "character.book.closed") {
            VStack(alignment: .leading, spacing: 14) {
                // Status Header
                HStack(alignment: .center, spacing: 10) {
                    if model.localDictionaryService.isDatabaseInstalled {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 18))
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 18))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.localDictionaryService.isDatabaseInstalled ? L("Dictionnaire actif") : L("Aucune base installée"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text("\(totalEntriesFormatted) définitions actives · < 0,1 ms · 100% Hors-ligne")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        model.refreshDictionaryStats()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help(L("Actualiser"))
                }

                Divider().opacity(0.6)

                // Dictionary Content Summary
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Dictionnaires installés :"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 6) {
                        ForEach(model.localDictionaryService.installedDictionaries, id: \.self) { dictName in
                            HStack(alignment: .center, spacing: 8) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.accentColor)

                                Text(dictName)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(.primary)

                                Spacer()

                                Text(L("Actif"))
                                    .font(.system(size: 9.5, weight: .medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                                    .foregroundStyle(Color.accentColor)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }

                Divider().opacity(0.6)

                ToggleRow(
                    title: L("Show alternate readings"),
                    subtitle: L("Show supported Japanese readings as a separate section"),
                    isOn: $model.settings.showAlternateReadings
                )

                Divider().opacity(0.6)

                // Installed dictionaries are discovered and read in place.
                HStack(spacing: 10) {
                    Button {
                        model.localDictionaryService.openDatabaseFolder()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "folder")
                            Text(L("Ouvrir le dossier"))
                        }
                    }
                    .controlSize(.small)

                    Spacer()
                }
            }
        }
    }
}
