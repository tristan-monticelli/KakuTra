import SwiftUI

struct AnkiSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AnkiSettingsSection()
            }
            .padding(20)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

struct AnkiSettingsSection: View {
    @EnvironmentObject private var model: AppModel

    private var isConnected: Bool {
        if case .connected = model.ankiConnectionState { return true }
        return false
    }

    private var isChecking: Bool {
        if case .checking = model.ankiConnectionState { return true }
        return false
    }

    private var requiredRolesAreValid: Bool {
        AnkiFieldRole.allCases
            .filter(\.isRequired)
            .allSatisfy { role in
                guard let mapped = model.settings.ankiFieldMappings[role.rawValue] else { return false }
                return model.ankiModelFieldNames.contains(mapped)
            }
    }

    private var isConfigurationValid: Bool {
        isConnected
            && model.ankiDeckNames.contains(model.settings.ankiDeckName)
            && model.ankiModelNames.contains(model.settings.ankiModelName)
            && requiredRolesAreValid
    }

    var body: some View {
        SettingsSectionCard(title: L("AnkiConnect"), icon: "rectangle.stack.badge.plus") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 9) {
                    connectionIndicator
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connectionTitle)
                            .font(.system(size: 13, weight: .medium))
                        Text(connectionDetail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(L("Check")) {
                        Task { await model.refreshAnkiConfiguration() }
                    }
                    .controlSize(.small)
                    .disabled(isChecking)
                }

                Link(L("AnkiConnect setup guide"), destination: URL(string: "https://github.com/FooSoft/anki-connect")!)
                    .font(.system(size: 11, weight: .medium))

                if isConnected {
                    Divider()
                    selectionPicker(title: L("Deck"), value: $model.settings.ankiDeckName, placeholder: L("Choose a deck"), options: model.ankiDeckNames)
                    selectionPicker(
                        title: L("Note type"),
                        value: Binding(
                            get: { model.settings.ankiModelName },
                            set: { model.setAnkiModelName($0) }
                        ),
                        placeholder: L("Choose a note type"),
                        options: model.ankiModelNames
                    )

                    if !model.settings.ankiModelName.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("Field mapping"))
                                .font(.system(size: 12, weight: .semibold))
                            ForEach(AnkiFieldRole.allCases) { role in
                                fieldPicker(for: role)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(L("Anki tags"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextField("kakutra", text: $model.settings.ankiTags)
                            .textFieldStyle(.roundedBorder)
                    }

                    Label(
                        isConfigurationValid ? L("Anki configuration ready") : L("Map the required term and definition fields"),
                        systemImage: isConfigurationValid ? "checkmark.circle.fill" : "info.circle"
                    )
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isConfigurationValid ? Color.green : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(L("Choose a deck and note type after AnkiConnect is available."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(L("This screen only checks configuration. KakuTra will never add or change a note from here."))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var connectionIndicator: some View {
        switch model.ankiConnectionState {
        case .checking:
            ProgressView().controlSize(.small).frame(width: 16, height: 16)
        case .connected:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .notConnected:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    private var connectionTitle: String {
        switch model.ankiConnectionState {
        case .checking: return L("Checking AnkiConnect…")
        case .connected(let version): return "AnkiConnect · \(version)"
        case .notConnected: return L("AnkiConnect not connected")
        case .failed: return L("AnkiConnect could not be checked")
        }
    }

    private var connectionDetail: String {
        switch model.ankiConnectionState {
        case .checking: return L("Checking the local AnkiConnect service on this Mac.")
        case .connected: return L("Anki and AnkiConnect are available on this Mac.")
        case .notConnected: return L("Open Anki and enable the AnkiConnect add-on.")
        case .failed(let message): return message
        }
    }

    private func selectionPicker(title: String, value: Binding<String>, placeholder: String, options: [String]) -> some View {
        HStack {
            Text(title).font(.system(size: 12, weight: .medium))
            Spacer()
            Picker(title, selection: value) {
                Text(placeholder).tag("")
                if !value.wrappedValue.isEmpty && !options.contains(value.wrappedValue) {
                    Text(L("Missing from Anki")).tag(value.wrappedValue)
                }
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
            .frame(width: 220)
        }
    }

    private func fieldPicker(for role: AnkiFieldRole) -> some View {
        let current = model.settings.ankiFieldMappings[role.rawValue] ?? ""
        return HStack {
            Text(role.title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            if role.isRequired {
                Text(L("Required"))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Picker(role.title, selection: Binding(
                get: { model.settings.ankiFieldMappings[role.rawValue] ?? "" },
                set: { model.setAnkiFieldMapping($0, for: role) }
            )) {
                Text(L("Not assigned")).tag("")
                if !current.isEmpty && !model.ankiModelFieldNames.contains(current) {
                    Text(L("Missing from Anki")).tag(current)
                }
                ForEach(model.ankiModelFieldNames, id: \.self) { field in
                    Text(field).tag(field)
                }
            }
            .labelsHidden()
            .frame(width: 175)
            .disabled(model.ankiModelFieldNames.isEmpty)
        }
    }
}
