//
//  YomitanSettingsSection.swift
//  KakuTra
//
//  Embedded Japanese immersion dictionary settings:
//  Displays local SQLite status (551,000+ entries), language preference,
//  and allows importing custom Yomitan .zip archives.
//

import AppKit
import SwiftUI

struct YomitanSettingsSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var isImporting = false
    @State private var importMessage: String? = nil
    @State private var importErrorMessage: String? = nil

    private var totalEntriesFormatted: String {
        let count = model.japaneseDictionaryService.totalEntriesCount
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    var body: some View {
        SettingsSectionCard(title: L("Japanese Dictionaries"), icon: "character.book.closed") {
            VStack(alignment: .leading, spacing: 14) {
                // Status Header
                HStack(alignment: .center, spacing: 10) {
                    if model.japaneseDictionaryService.isDatabaseInstalled {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 18))
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 18))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.japaneseDictionaryService.isDatabaseInstalled ? L("Moteur SQLite KakuTra Actif") : L("Base SQLite non installée"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text("\(totalEntriesFormatted) entrées actives · < 0,3 ms · 100% Hors-ligne · Zéro extension")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        Task { await model.refreshYomitanStatus() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help(L("Actualiser"))
                }

                Divider().opacity(0.6)

                // Installed Dictionaries List
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Dictionnaires intégrés :"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    if model.japaneseDictionaryService.installedDictionaries.isEmpty {
                        Text(L("Aucun dictionnaire installé."))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.japaneseDictionaryService.installedDictionaries, id: \.self) { dictName in
                            HStack(spacing: 8) {
                                Image(systemName: "book.pages")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.accentColor)

                                Text(dictName)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.primary)

                                Spacer()

                                Text(dictBadge(for: dictName))
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                                    .foregroundStyle(Color.accentColor)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                // Actions: Import & Open Folder
                HStack(spacing: 10) {
                    Button {
                        importDictionaryFile()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                            Text(L("Importer un dictionnaire (.zip)…"))
                        }
                    }
                    .controlSize(.small)
                    .disabled(isImporting)

                    Button {
                        model.japaneseDictionaryService.openDatabaseFolder()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "folder")
                            Text(L("Ouvrir le dossier"))
                        }
                    }
                    .controlSize(.small)

                    if isImporting {
                        ProgressView().controlSize(.small)
                        Text(L("Importation en cours…"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                    if let message = importMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(message)
                                .font(.system(size: 11))
                                .foregroundStyle(.primary)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    }

                    if let error = importErrorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundStyle(.primary)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }

    private func dictBadge(for name: String) -> String {
        if name.contains("Français") {
            return L("Français")
        } else if name.contains("English") {
            return L("Anglais & Argot")
        } else {
            return L("Personnalisé")
        }
    }

    private func importDictionaryFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = L("Sélectionnez une archive de dictionnaire Yomitan (.zip)")

        if panel.runModal() == .OK, let url = panel.url {
            isImporting = true
            importMessage = nil
            importErrorMessage = nil

            Task {
                do {
                    let result = try await model.japaneseDictionaryService.importYomitanZip(at: url)
                    await MainActor.run {
                        self.isImporting = false
                        self.importMessage = L("Dictionnaire « %@ » importé avec succès (%lld entrées ajoutées).", result.dictionaryName, Int64(result.count))
                    }
                    await model.refreshYomitanStatus()
                } catch {
                    await MainActor.run {
                        self.isImporting = false
                        self.importErrorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
}
