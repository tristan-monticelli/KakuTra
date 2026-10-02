//
//  YomitanSettingsSection.swift
//  KakuTra
//
//  Clean language-based dictionary settings:
//  The user chooses their preferred definition language (English or French),
//  sees the installed language files, and can open the folder or import files.
//  Zero internal package jargon.
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
        SettingsSectionCard(title: L("Dictionnaires"), icon: "character.book.closed") {
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
                        Text(model.japaneseDictionaryService.isDatabaseInstalled ? L("Dictionnaire actif") : L("Aucune base installée"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text("\(totalEntriesFormatted) définitions actives · < 0,3 ms · 100% Hors-ligne")
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

                // Language Selection (Clean & Simple)
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Langue des définitions"))
                            .font(.system(size: 12, weight: .medium))
                        Text(L("Choisissez la langue à afficher lors du survol d'un mot."))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    Picker("", selection: $model.settings.yomitanPreferredGlossaryLanguage) {
                        Text(L("Anglais (Recommandé)")).tag("en")
                        Text(L("Français")).tag("fr")
                        Text(L("Toutes les langues")).tag("all")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                Divider().opacity(0.6)

                // Installed Language Files List
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Fichiers de langues installés :"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    if model.japaneseDictionaryService.installedLanguages.isEmpty {
                        Text(L("Aucun fichier de langue trouvé."))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.japaneseDictionaryService.installedLanguages) { lang in
                            HStack(spacing: 8) {
                                Image(systemName: "globe")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.accentColor)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(lang.displayName)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.primary)
                                    Text("\(formattedCount(lang.entriesCount)) définitions · \(lang.filename)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(lang.badge)
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

                Divider().opacity(0.6)

                // Actions: Open Folder & Import File
                HStack(spacing: 10) {
                    Button {
                        model.japaneseDictionaryService.openDatabaseFolder()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "folder")
                            Text(L("Ouvrir le dossier des langues"))
                        }
                    }
                    .controlSize(.small)

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

    private func formattedCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    private func importDictionaryFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = L("Sélectionnez une archive de dictionnaire (.zip)")

        if panel.runModal() == .OK, let url = panel.url {
            isImporting = true
            importMessage = nil
            importErrorMessage = nil

            Task {
                do {
                    let result = try await model.japaneseDictionaryService.importYomitanZip(at: url)
                    await MainActor.run {
                        self.isImporting = false
                        self.importMessage = L("Dictionnaire « %@ » importé avec succès (%lld définitions ajoutées).", result.dictionaryName, Int64(result.count))
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
