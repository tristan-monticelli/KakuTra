//
//  YomitanSettingsSection.swift
//  KakuTra
//
//  Pure Japanese-to-English immersion dictionary settings.
//  Zero unnecessary UI, zero language pickers.
//  1.1M+ definitions (Jitendex + JMnedict), sub-0.1ms offline search.
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
        SettingsSectionCard(title: L("Dictionnaire"), icon: "character.book.closed") {
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

                        Text("\(totalEntriesFormatted) définitions actives · < 0,1 ms · 100% Hors-ligne")
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

                // Dictionary Content Summary
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Bases d'immersion actives (routage automatique) :"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 6) {
                        ForEach(model.japaneseDictionaryService.installedDictionaries, id: \.self) { dictName in
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

                        HStack(alignment: .center, spacing: 8) {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)

                            Text(L("Dictionnaires Système Apple (Repli automatique autres langues)"))
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(.secondary)

                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
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
                            Text(L("Ouvrir le dossier"))
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
