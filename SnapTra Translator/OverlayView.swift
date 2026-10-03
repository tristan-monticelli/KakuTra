import AppKit
import SwiftUI
import SwiftData

struct OverlayView: View {
    let paragraphOverlayMaxHeightOverride: CGFloat?
    let paragraphOverlayScrollingEnabledOverride: Bool?

    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var localizationManager = LocalizationManager.shared
    @State private var isParagraphHeaderHovered = false
    @State private var isParagraphHeaderDragging = false
    @State private var isParagraphOriginalEditorExpanded = false
    private let wordOverlayWidth: CGFloat = 380
    private let paragraphOverlayWidth: CGFloat = 520
    private let paragraphHeaderHeight: CGFloat = 34
    private let compactSectionMinHeight: CGFloat = 28
    private let paragraphTextHorizontalPadding: CGFloat = 18
    private let wordHeaderHorizontalPadding: CGFloat = 18
    private let wordHeaderControlGroupWidth: CGFloat = 132
    private let wordHeaderControlGap: CGFloat = 12

    init(
        paragraphOverlayMaxHeightOverride: CGFloat? = nil,
        paragraphOverlayScrollingEnabledOverride: Bool? = nil
    ) {
        self.paragraphOverlayMaxHeightOverride = paragraphOverlayMaxHeightOverride
        self.paragraphOverlayScrollingEnabledOverride = paragraphOverlayScrollingEnabledOverride
    }

    private var overlayWidth: CGFloat {
        if let preferred = model.overlayPreferredWidth {
            return preferred
        }
        switch model.overlayState {
        case .paragraphLoading, .paragraphResult:
            return paragraphOverlayWidth
        default:
            return wordOverlayWidth
        }
    }

    private var showsParagraphOverlayControls: Bool {
        switch model.overlayState {
        case .paragraphLoading, .paragraphResult:
            return true
        default:
            return !model.settings.continuousTranslation
        }
    }

    private var showsWordOverlayControls: Bool {
        !model.settings.continuousTranslation || model.isTapKeptOverlayPresented
    }

    private var useSelectableWordText: Bool {
        WordOverlayTextSelectionPolicy.usesSelectableText(
            isWordOverlayMode: isWordOverlayMode,
            showsWordOverlayControls: showsWordOverlayControls
        )
    }

    private var isWordOverlayMode: Bool {
        !isParagraphOverlayMode
    }

    private var isParagraphOverlayMode: Bool {
        switch model.overlayState {
        case .paragraphLoading, .paragraphResult:
            return true
        default:
            return false
        }
    }

    private var showsParagraphOverlayPinButton: Bool {
        ParagraphOverlayControlPolicy.showsPinButton(
            isParagraphOverlayMode: isParagraphOverlayMode,
            isParagraphOverlayPinned: model.isParagraphOverlayPinned,
            isTapKeptOverlay: model.isTapKeptOverlayPresented
        )
    }

    private var canDragPinnedParagraphOverlay: Bool {
        isParagraphOverlayMode && model.isParagraphOverlayPinned
    }

    private var isVisible: Bool {
        if case .idle = model.overlayState { return false }
        return true
    }

    private var paragraphBodyMaxHeight: CGFloat? {
        guard isParagraphOverlayMode,
              let overlayMaxHeight = paragraphOverlayMaxHeightOverride else {
            return nil
        }
        return max(1, overlayMaxHeight - paragraphHeaderHeight)
    }

    private var paragraphBodyUsesScrollView: Bool {
        paragraphOverlayScrollingEnabledOverride ?? false
    }

    private var showsExtendedDictionaryDetails: Bool {
        !model.settings.targetLanguage.hasPrefix("zh")
    }

    var body: some View {
        Group {
            if isVisible {
                overlayContent
            }
        }
    }

    @ViewBuilder
    private var overlayContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch model.overlayState {
            case .idle:
                EmptyView()

            case .loading(let word):
                loadingView(word: word)

            case .result(let content):
                resultView(content: content)

            case .paragraphLoading:
                paragraphLoadingView

            case .paragraphResult(let content):
                paragraphResultView(content: content)

            case .error(let message):
                errorView(message: message)

            case .noWord:
                noWordView
            }
        }
        .frame(width: overlayWidth, alignment: .leading)
        .background {
            ZStack {
                // More opaque material so background content doesn't bleed through
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
                // Tint layer to reinforce system appearance over any background
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark
                        ? Color.black.opacity(0.25)
                        : Color.white.opacity(0.25))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .inset(by: 0.5)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [
                                .white.opacity(0.4),
                                .white.opacity(0.15),
                                .white.opacity(0.08),
                            ]
                            : [
                                .black.opacity(0.08),
                                .black.opacity(0.05),
                                .black.opacity(0.03),
                            ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.08), radius: 2, x: 0, y: 1)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.06), radius: 14, x: 0, y: 8)
        .onChange(of: isParagraphOverlayMode) { _, isParagraphMode in
            if !isParagraphMode {
                resetParagraphHeaderInteractionState()
                resetParagraphOriginalEditorState()
            }
        }
        .onChange(of: model.isParagraphOverlayPinned) { _, isPinned in
            if !isPinned {
                resetParagraphOriginalEditorState()
            }
        }
        .onChange(of: model.settings.hideOriginalTextInSentenceOverlay) { _, hidesOriginalText in
            if hidesOriginalText {
                resetParagraphOriginalEditorState()
            }
        }
        .onDisappear {
            resetParagraphHeaderInteractionState()
            resetParagraphOriginalEditorState()
        }
    }

    // MARK: - Loading View

    @ViewBuilder
    private func loadingView(word: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let word {
                Text(word)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .tracking(0.2)
            }
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.85)
                Text(L("Searching…"))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                LoadingDotsView()
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
    }

    // MARK: - Result View

    @ViewBuilder
    private func resultView(content: OverlayContent) -> some View {
        if let draft = model.ankiConfirmationDraft {
            ankiConfirmationOverlay(draft: draft)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                cleanWordHeader(content: content)
                cleanDefinitionsBody(content: content)
            }
            .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func ankiConfirmationOverlay(draft: AnkiCardConfirmationDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "rectangle.stack.badge.plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(L("Add to Anki"))
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Button {
                    model.dismissAnkiConfirmation()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
            }

            if let configError = draft.configurationError {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(configError)
                            .font(.system(size: 11))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button(L("Open Anki Settings")) {
                        model.openSettingsTab(.anki)
                    }
                    .controlSize(.small)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            } else if let noteID = draft.createdNoteID {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(L("Note successfully created in Anki (ID: %lld)", noteID))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    Button(L("Done")) {
                        model.dismissAnkiConfirmation()
                    }
                    .controlSize(.small)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            } else {
                if draft.isCheckingDuplicate {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(L("Checking for duplicate notes in Anki…"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else if draft.isDuplicate {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        Text(L("This note already exists in deck '%@'. KakuTra never overwrites notes silently.", draft.deckName))
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                } else if let dupError = draft.duplicateCheckError {
                    Text(L("Duplicate check warning: %@", dupError))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(draft.term)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                        if !draft.reading.isEmpty && draft.reading != draft.term {
                            Text(draft.reading)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(draft.sourceDictionary)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("Definition"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextEditor(text: Binding(
                            get: { model.ankiConfirmationDraft?.definition ?? "" },
                            set: { model.ankiConfirmationDraft?.definition = $0 }
                        ))
                        .font(.system(size: 11))
                        .frame(minHeight: 44, maxHeight: 70)
                        .padding(4)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    }

                    if !draft.contextSentence.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L("Context Sentence"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            TextEditor(text: Binding(
                                get: { model.ankiConfirmationDraft?.contextSentence ?? "" },
                                set: { model.ankiConfirmationDraft?.contextSentence = $0 }
                            ))
                            .font(.system(size: 11))
                            .frame(minHeight: 36, maxHeight: 60)
                            .padding(4)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }

                    HStack(spacing: 8) {
                        Label(draft.deckName, systemImage: "folder")
                        Label(draft.modelName, systemImage: "doc")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Text(L("Tags:"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextField("kakutra", text: Binding(
                            get: { model.ankiConfirmationDraft?.tags ?? "" },
                            set: { model.ankiConfirmationDraft?.tags = $0 }
                        ))
                        .font(.system(size: 10))
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.mini)
                    }

                    if let addError = draft.additionError {
                        Text(addError)
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                    }
                }

                HStack {
                    Button(L("Cancel")) {
                        model.dismissAnkiConfirmation()
                    }
                    .controlSize(.small)

                    Spacer()

                    Button {
                        model.confirmAddAnkiNote()
                    } label: {
                        HStack(spacing: 4) {
                            if draft.isAdding {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "plus.circle.fill")
                            }
                            Text(L("Add Note"))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(draft.isAdding || draft.isCheckingDuplicate || draft.isDuplicate || draft.term.isEmpty || draft.definition.isEmpty)
                }
            }
        }
        .padding(14)
    }

    struct DuolingoTagView: View {
        let tag: String
        @State private var isHovered = false

        var tagDescription: String {
            switch tag.lowercased() {
            case "noun", "nom", "substantif":
                return "Nom / Substantif"
            case "nom féminin":
                return "Nom féminin"
            case "nom masculin":
                return "Nom masculin"
            case "verb", "verbe":
                return "Verbe"
            case "common":
                return "Mot fréquent dans la langue courante (prioritaire)"
            case "adjective", "adjectif", "adj-i", "adj-na":
                return "Adjectif"
            case "adverb", "adverbe":
                return "Adverbe"
            case "1-dan", "ichidan":
                return "Verbe ichidan (2e groupe en -ru)"
            case "5-dan", "godan":
                return "Verbe godan (1er groupe)"
            case "suru", "suru verb":
                return "Verbe avec auxiliaire suru"
            case "transitive":
                return "Verbe transitif (action directe)"
            case "intransitive":
                return "Verbe intransitif"
            case "archaic":
                return "Terme archaïque / ancien"
            case "slang":
                return "Terme d'argot ou familier"
            default:
                return tag
            }
        }

        var body: some View {
            Text(tag)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(tag == "Common" ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    (tag == "Common" ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06)),
                    in: RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                )
                .underline(true, pattern: .dot, color: (tag == "Common" ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.4)))
                .help(tagDescription)
        }
    }

    struct DuolingoSegmentedDefinitionView: View {
        let index: Int?
        let rawText: String

        var parsed: (main: String, hint: String?, tooltip: String?) {
            let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

            // 1. Parenthetical remarks, e.g. "cat (esp. the domestic cat, Felis catus)"
            if let pStart = text.range(of: "("), let pEnd = text.range(of: ")", range: pStart.upperBound..<text.endIndex) {
                let main = String(text[..<pStart.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let inside = String(text[pStart.upperBound..<pEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)

                if inside.count > 30 {
                    return (main.isEmpty ? inside : main, "détails", inside)
                }

                if let comma = inside.range(of: ",") {
                    let hint = String(inside[..<comma.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let extra = String(inside[comma.upperBound...]).trimmingCharacters(in: .whitespaces)
                    return (main.isEmpty ? inside : main, hint, extra)
                } else {
                    return (main.isEmpty ? inside : main, inside, inside)
                }
            }

            // 2. French gender notation, e.g. "ordinateur m"
            if text.hasSuffix(" m") {
                let main = String(text.dropLast(2)).trimmingCharacters(in: .whitespaces)
                return (main, "masculin", "Nom masculin")
            } else if text.hasSuffix(" f") {
                let main = String(text.dropLast(2)).trimmingCharacters(in: .whitespaces)
                return (main, "féminin", "Nom féminin")
            }

            // 3. Example sentence after period: e.g. "Bâtiment servant d'habitation. Une maison de campagne."
            if let dot = text.range(of: ". ") {
                let main = String(text[..<dot.lowerBound]).trimmingCharacters(in: .whitespaces)
                let ex = String(text[dot.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !ex.isEmpty && ex.count > 3 {
                    return (main, "exemple", ex)
                }
            }

            return (text, nil, nil)
        }

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let index {
                    Text("\(index).")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary.opacity(0.65))
                        .frame(width: 14, alignment: .trailing)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(parsed.main)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.primary)

                    if let hint = parsed.hint {
                        Text(hint)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .underline(true, pattern: .dot, color: .secondary.opacity(0.6))
                            .help(parsed.tooltip ?? hint)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    struct DuolingoVariantsHintView: View {
        let count: Int
        let details: String

        var body: some View {
            HStack(spacing: 4) {
                Image(systemName: "character.book.closed")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)

                Text("\(count) autre\(count > 1 ? "s" : "") lecture\(count > 1 ? "s" : "")")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .underline(true, pattern: .dot, color: .secondary.opacity(0.6))
            }
            .padding(.top, 3)
            .help("Lectures ou formes secondaires :\n\(details)")
        }
    }

    @ViewBuilder
    private func cleanWordHeader(content: OverlayContent) -> some View {
        let firstEntry: DictionaryTermResult? = {
            if case .results(let entries) = content.dictionaryLookupState {
                return entries.first
            }
            return nil
        }()

        let displayHeadword: String = {
            if let term = firstEntry?.term, !term.isEmpty {
                return term
            }
            return content.word
        }()

        let displayReading: String? = {
            if let reading = firstEntry?.reading, !reading.isEmpty, reading != displayHeadword {
                return reading
            }
            if let term = firstEntry?.term, !term.isEmpty, term != content.word {
                return content.word
            }
            return nil
        }()

        HStack(alignment: .center, spacing: 8) {
            // Main Headword + Inline Reading + Audio Speaker
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(displayHeadword)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                // Inline Reading (Furigana / Pinyin / IPA)
                if let reading = displayReading {
                    Text(reading)
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Minimalist Audio Pronunciation Speaker
                if !content.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        model.playOverlayPronunciation(kind: .word)
                    } label: {
                        Image(systemName: model.isPronunciationPlaying(kind: .word) ? "waveform" : "speaker.wave.2")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(model.isPronunciationPlaying(kind: .word) ? Color.accentColor : .secondary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L("Play pronunciation"))
                }
            }

            Spacer(minLength: 8)

            // Header Action Buttons
            HStack(spacing: 4) {
                if let first = firstEntry {
                    Button {
                        model.prepareAnkiNote(for: first, contextSentence: content.contextSentence)
                    } label: {
                        Image(systemName: "plus.rectangle.on.rectangle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(L("Add to Anki"))
                }

                Button {
                    model.dismissOverlay()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(L("Close"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func cleanDefinitionsBody(content: OverlayContent) -> some View {
        switch content.dictionaryLookupState {
        case .notRequested, .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L("Searching…"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)

        case .noResults:
            Text(L("No definition found."))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

        case .failed(let message):
            Text(message.isEmpty ? L("No definition found.") : message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

        case .results(let entries):
            if let primary = entries.first {
                VStack(alignment: .leading, spacing: 7) {
                    // 1. Grammatical & Frequency Tags with Duolingo-style dotted tooltips
                    if !primary.tags.isEmpty {
                        HStack(spacing: 5) {
                            ForEach(primary.tags, id: \.self) { tag in
                                DuolingoTagView(tag: tag)
                            }
                        }
                        .padding(.bottom, 1)
                    }

                    // 2. Interactive segmented definitions (clear keywords + dotted hover hints)
                    if primary.glosses.count == 1 {
                        DuolingoSegmentedDefinitionView(index: nil, rawText: primary.glosses[0])
                    } else {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(Array(primary.glosses.prefix(4).enumerated()), id: \.offset) { idx, gloss in
                                DuolingoSegmentedDefinitionView(index: idx + 1, rawText: gloss)
                            }
                        }
                    }

                    // 3. Variant readings / other forms (strictly NO Japanese in translation body!)
                    let otherEntries = entries.dropFirst().filter { $0.term != primary.term || $0.reading != primary.reading }
                    if !otherEntries.isEmpty {
                        let variantsDetail = otherEntries.compactMap { e -> String in
                            let r = e.reading ?? e.term
                            let t = e.tags.isEmpty ? "" : " (\(e.tags.joined(separator: ", ")))"
                            let g = e.glosses.isEmpty ? "" : " : \(e.glosses.joined(separator: ", "))"
                            return "• \(r)\(t)\(g)"
                        }.joined(separator: "\n")

                        DuolingoVariantsHintView(count: otherEntries.count, details: variantsDetail)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
    }

    private var paragraphLoadingView: some View {
        VStack(alignment: .leading, spacing: 0) {
            paragraphTopBar()

            paragraphBodyContainer {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 10) {
                        ProgressView()
                            .controlSize(.small)

                        Text(L("Detecting text under cursor"))
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary)
                    }

                    Text(L("Détection du texte japonais en cours…"))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 18)
                .padding(.top, 2)
                .padding(.vertical, 14)
            }
        }
    }

    @ViewBuilder
    private func paragraphResultView(content: ParagraphOverlayContent) -> some View {
        let originalText = content.originalText ?? ""
        let hasOriginalText = !originalText.isEmpty
        let hasTranslationOutput = content.showsNativeTranslation || !content.serviceResults.isEmpty
        let originalVisibility = ParagraphOriginalVisibilityPolicy.resolve(
            hasOriginalText: hasOriginalText,
            isParagraphOverlayPinned: model.isParagraphOverlayPinned,
            hidesOriginalTextSetting: model.settings.hideOriginalTextInSentenceOverlay,
            isOriginalEditorExpanded: isParagraphOriginalEditorExpanded,
            isManualInputFallback: content.isManualInputFallback,
            hasTranslationOutput: hasTranslationOutput
        )
        let showsAutoDismissFailure = !hasOriginalText && content.serviceResults.isEmpty && !originalVisibility.showsOriginalTextRegion
        let originalFontSize: CGFloat = if content.useFixedFontSize {
            content.bodyFontSize
        } else {
            ParagraphFontSizing.optimalFontSize(
                preferredFontSize: content.bodyFontSize,
                originalText: content.originalText,
                containerWidth: overlayWidth,
                horizontalPadding: paragraphTextHorizontalPadding
            )
        }
        let translationFontSize: CGFloat = if originalVisibility.usesStableTranslationFont {
            ParagraphFontSizing.stableFontSize(preferredFontSize: content.bodyFontSize)
        } else {
            originalFontSize
        }
        let showsLanguageSelectorInTopBar = !originalVisibility.showsOriginalTextRegion && hasParagraphLanguageSelector(content)

        VStack(alignment: .leading, spacing: 0) {
            if originalVisibility.showsOriginalTextRegion {
                paragraphOriginalTopBar(originalVisibility: originalVisibility, content: content)
            } else {
                paragraphTopBar(
                    originalVisibility: originalVisibility,
                    languageSelectorContent: showsLanguageSelectorInTopBar ? content : nil,
                    pronunciationContent: content
                )
            }

            paragraphBodyContainer {
                if showsAutoDismissFailure,
                   case .failed(let message) = content.translationState {
                    // Auto-dismiss error view for paragraph translation errors with no original text.
                    AutoDismissErrorView(message: L(message), onDismiss: { model.dismissOverlay() })
                        .padding(.horizontal, paragraphTextHorizontalPadding)
                        .padding(.vertical, 18)
                } else {
                    if originalVisibility.showsOriginalTextRegion {
                        VStack(alignment: .leading, spacing: 0) {
                            paragraphOriginalTextView(
                                text: originalText,
                                fontSize: originalFontSize,
                                usesEditableOriginalText: originalVisibility.usesEditableOriginalText
                            )
                            .padding(.top, originalVisibility.usesEditableOriginalText ? 2 : 4)
                        }
                        .padding(.horizontal, paragraphTextHorizontalPadding)
                        .padding(.bottom, 10)
                    }

                    if !showsLanguageSelectorInTopBar && (originalVisibility.showsOriginalTextRegion || hasParagraphLanguageSelector(content)) {
                        paragraphLanguageSelector(content: content)
                            .padding(.horizontal, paragraphTextHorizontalPadding)
                            .padding(.bottom, originalVisibility.usesEditableOriginalText ? 6 : 2)
                    }

                    if content.showsNativeTranslation {
                        // Native Translation Section (System Translation)
                        switch content.translationState {
                        case .loading:
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text(L("Translating"))
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(.secondary)
                                    LoadingDotsView()
                                }
                                .padding(.horizontal, paragraphTextHorizontalPadding)
                                .padding(.vertical, 14)
                            }

                        case .ready(let translatedText):
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .center, spacing: 8) {
                                    Text(paragraphTranslationSectionTitle(for: content))
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)

                                    if content.isRetranslating {
                                        ProgressView()
                                            .controlSize(.small)
                                            .scaleEffect(0.7)
                                    }
                                }

                                paragraphTextContent(
                                    text: translatedText,
                                    font: .systemFont(ofSize: translationFontSize, weight: .semibold),
                                    textColor: content.isRetranslating ? .secondaryLabelColor : .labelColor,
                                    preferredLineHeight: translationFontSize * 1.5
                                )
                            }
                            .padding(.horizontal, paragraphTextHorizontalPadding)
                            .padding(.top, originalVisibility.usesEditableOriginalText ? 12 : 14)
                            .padding(.bottom, 14)

                        case .failed(let message):
                            VStack(alignment: .leading, spacing: 0) {
                                paragraphErrorContent(message: L(message))
                                    .padding(.horizontal, paragraphTextHorizontalPadding)
                                    .padding(.vertical, 14)
                            }
                        }
                    }

                    // Third-party Service Results Section
                    if !content.serviceResults.isEmpty {
                        ForEach(content.serviceResults) { result in
                            Divider()
                                .padding(.horizontal, paragraphTextHorizontalPadding)
                                .opacity(0.6)

                            paragraphServiceResultCard(result: result, fontSize: translationFontSize)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func paragraphOriginalTextView(
        text: String,
        fontSize: CGFloat,
        usesEditableOriginalText: Bool
    ) -> some View {
        if usesEditableOriginalText {
            editableParagraphOriginalTextView(text: text)
        } else {
            if !text.isEmpty {
                paragraphTextContent(
                    text: text,
                    font: .systemFont(ofSize: fontSize, weight: .medium),
                    textColor: .labelColor,
                    preferredLineHeight: fontSize * 1.5
                )
            }
        }
    }

    private func editableParagraphOriginalTextView(text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            EditableParagraphTextView(
                text: text,
                placeholder: L("Type or paste text to translate"),
                font: .systemFont(ofSize: 14.5, weight: .regular),
                textColor: .labelColor,
                placeholderColor: .placeholderTextColor,
                preferredLineHeight: 21,
                onTextChange: { newText in
                    if newText != text {
                        model.updateParagraphOriginalText(newText)
                    }
                },
                onSubmit: { model.submitParagraphOriginalText() }
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(paragraphEditorFillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(paragraphEditorStrokeColor, lineWidth: 1)
            )
            .shadow(color: paragraphEditorShadowColor, radius: 1.5, x: 0, y: 1)

            HStack(spacing: 6) {
                Image(systemName: "return")
                    .font(.system(size: 9.5, weight: .semibold))

                Text(L("Return to translate · Shift-Return for line break"))
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.tertiary)
            .padding(.leading, 2)
        }
    }

    private var paragraphEditorFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.58)
    }

    private var paragraphEditorStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.055)
    }

    private var paragraphEditorShadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.12) : Color.black.opacity(0.025)
    }

    @ViewBuilder
    private func paragraphLanguageSelector(content: ParagraphOverlayContent) -> some View {
        if hasParagraphLanguageSelector(content) {
            HStack {
                Spacer(minLength: 0)

                paragraphLanguageSelectorCapsule(content: content)

                Spacer(minLength: 0)
            }
        } else {
            Divider()
                .opacity(0.6)
        }
    }

    private func hasParagraphLanguageSelector(_ content: ParagraphOverlayContent) -> Bool {
        content.languageOptions.count == 2 && content.selectedTargetLanguageIdentifier != nil
    }

    @ViewBuilder
    private func paragraphLanguageSelectorCapsule(
        content: ParagraphOverlayContent,
        isCompact: Bool = false
    ) -> some View {
        if let selectedTargetIdentifier = content.selectedTargetLanguageIdentifier,
           let sourceLanguageIdentifier = content.sourceLanguageIdentifier,
           content.languageOptions.count == 2 {
            let sourceMinimalID = Locale.Language(identifier: sourceLanguageIdentifier).minimalIdentifier
            let targetMinimalID = Locale.Language(identifier: selectedTargetIdentifier).minimalIdentifier

            let sourceName = content.languageOptions.first {
                Locale.Language(identifier: $0.identifier).minimalIdentifier == sourceMinimalID
            }?.displayName ?? ""

            let targetName = content.languageOptions.first {
                Locale.Language(identifier: $0.identifier).minimalIdentifier == targetMinimalID
            }?.displayName ?? ""

            Button {
                model.translateParagraphOriginal(to: sourceLanguageIdentifier)
            } label: {
                HStack(spacing: 4) {
                    Text(sourceName)
                        .font(.system(size: isCompact ? 10.5 : 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Image(systemName: "arrow.right")
                        .font(.system(size: isCompact ? 8 : 9, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(targetName)
                        .font(.system(size: isCompact ? 10.5 : 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, isCompact ? 8 : 10)
                .padding(.vertical, isCompact ? 3 : 5)
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            .accessibilityLabel(Text(L("Toggle translation direction")))
            .padding(isCompact ? 1 : 2)
            .background(
                Capsule(style: .continuous)
                    .fill(colorScheme == .dark ? .white.opacity(0.075) : .black.opacity(0.04))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
            )
        }
    }

    @ViewBuilder
    private func paragraphServiceResultCard(result: ServiceTranslationResult, fontSize: CGFloat) -> some View {
        switch result.state {
        case .loading:
            VStack(alignment: .leading, spacing: 8) {
                paragraphServiceResultHeader(result: result)

                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L("Translating"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    LoadingDotsView()
                }
            }
            .padding(.horizontal, paragraphTextHorizontalPadding)
            .padding(.vertical, 14)

        case .ready(let translatedText):
            VStack(alignment: .leading, spacing: 8) {
                paragraphServiceResultHeader(result: result)

                paragraphTextContent(
                    text: translatedText,
                    font: .systemFont(ofSize: fontSize, weight: .medium),
                    textColor: .labelColor,
                    preferredLineHeight: fontSize * 1.5
                )
            }
            .padding(.horizontal, paragraphTextHorizontalPadding)
            .padding(.vertical, 14)

        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                paragraphServiceResultHeader(result: result)

                paragraphErrorContent(message: message)
            }
            .padding(.horizontal, paragraphTextHorizontalPadding)
            .padding(.vertical, 14)
        }
    }

    /// Header row shared by all paragraph service result states: provider name,
    /// optional model name for LLM providers, elapsed translation time on the
    /// right.
    @ViewBuilder
    private func paragraphServiceResultHeader(result: ServiceTranslationResult) -> some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(alignment: .center, spacing: 4) {
                Text(result.sourceType.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let modelName = result.modelName, !modelName.isEmpty {
                    Text(verbatim: "·")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.secondary)

                    Text(modelName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let duration = result.duration {
                Text(Self.formatTranslationDuration(duration))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .layoutPriority(1)
                    .help(L("Translation time"))
            }
        }
    }

    private static func formatTranslationDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            let milliseconds = Int((duration * 1000).rounded())
            return "\(milliseconds)ms"
        }
        return String(format: "%.1fs", duration)
    }

    @ViewBuilder
    private func paragraphBodyContainer<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        Group {
            if paragraphBodyUsesScrollView {
                ScrollView {
                    paragraphBodyContent(content: content)
                }
                .frame(maxHeight: paragraphBodyMaxHeight)
            } else {
                paragraphBodyContent(content: content)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func paragraphBodyContent<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func paragraphSectionCard<Content: View>(
        title: String?,
        emphasis: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ParagraphOverlaySectionCard(
            title: title,
            emphasis: emphasis,
            content: content
        )
    }

    @ViewBuilder
    private func paragraphStatusCard(
        title: String?,
        message: String,
        detail: String? = nil,
        systemImage: String,
        showsSpinner: Bool = false
    ) -> some View {
        paragraphSectionCard(title: title) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    if showsSpinner {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(message)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                }

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func paragraphTextContent(
        text: String,
        font: NSFont,
        textColor: NSColor,
        preferredLineHeight: CGFloat
    ) -> some View {
        SelectableTextView(
            text: text,
            font: font,
            textColor: textColor,
            preferredLineHeight: preferredLineHeight
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func wordSelectableText(
        _ text: String,
        font: NSFont,
        textColor: NSColor = .labelColor,
        preferredLineHeight: CGFloat
    ) -> some View {
        if useSelectableWordText {
            SelectableTextView(
                text: text,
                font: font,
                textColor: textColor,
                preferredLineHeight: preferredLineHeight
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(text)
        }
    }

    @ViewBuilder
    private func paragraphErrorContent(message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func paragraphTopBar(
        originalVisibility: ParagraphOriginalVisibilityPolicy.Decision? = nil,
        languageSelectorContent: ParagraphOverlayContent? = nil,
        pronunciationContent: ParagraphOverlayContent? = nil
    ) -> some View {
        let showsLanguageSelector = languageSelectorContent != nil

        ZStack(alignment: .center) {
            paragraphHeaderDragArea()

            if let languageSelectorContent {
                paragraphLanguageSelectorCapsule(content: languageSelectorContent, isCompact: true)
            }

            HStack(spacing: 0) {
                Spacer(minLength: 0)

                if let pronunciationContent {
                    pronunciationControl(
                        kind: .sentence,
                        hasText: !(pronunciationContent.originalText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }

                if let originalVisibility, originalVisibility.showsOriginalEditorToggle {
                    paragraphOriginalEditorToggleButton(isExpanded: originalVisibility.usesEditableOriginalText)
                }

                paragraphRegionSelectionButton()

                paragraphOverlayControlButton()
            }
        }
        .frame(height: showsLanguageSelector ? 24 : 18)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, showsLanguageSelector ? 4 : 6)
    }

    @ViewBuilder
    private func paragraphOriginalTopBar(
        originalVisibility: ParagraphOriginalVisibilityPolicy.Decision,
        content: ParagraphOverlayContent
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            paragraphHeaderDragArea(
                title: paragraphOriginalSectionTitle,
                fillsWidth: false
            )

            pronunciationControl(
                kind: .sentence,
                hasText: !(content.originalText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )

            if originalVisibility.showsOriginalEditorToggle {
                paragraphOriginalEditorToggleButton(isExpanded: originalVisibility.usesEditableOriginalText)
            }

            paragraphRegionSelectionButton()

            paragraphHeaderDragArea()

            paragraphOverlayControlButton()
        }
        .frame(height: 18)
        .padding(.leading, paragraphTextHorizontalPadding)
        .padding(.trailing, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func paragraphOriginalEditorToggleButton(isExpanded: Bool) -> some View {
        paragraphOverlayControlButton(
            systemImage: isExpanded ? "eye.slash" : "pencil",
            helpText: isExpanded ? L("Hide Original Text") : L("Edit Original Text"),
            action: { isParagraphOriginalEditorExpanded.toggle() }
        )
    }

    @ViewBuilder
    private func paragraphRegionSelectionButton() -> some View {
        if isParagraphOverlayMode {
            paragraphOverlayControlButton(
                systemImage: "crop",
                helpText: L("Reselect Region"),
                action: { model.beginManualParagraphRegionSelection() }
            )
        }
    }

    @ViewBuilder
    private func paragraphHeaderDragArea(
        title: String? = nil,
        fillsWidth: Bool = true
    ) -> some View {
        ZStack(alignment: .leading) {
            if canDragPinnedParagraphOverlay {
                paragraphPinnedDragHandle
            } else {
                Color.clear
            }

            if let title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .allowsHitTesting(false)
            }
        }
        .frame(
            maxWidth: fillsWidth ? .infinity : nil,
            maxHeight: .infinity,
            alignment: .leading
        )
        .fixedSize(horizontal: !fillsWidth, vertical: false)
        .allowsHitTesting(canDragPinnedParagraphOverlay)
    }

    @ViewBuilder
    private var paragraphPinnedDragHandle: some View {
        if canDragPinnedParagraphOverlay {
            ParagraphOverlayDragHandle(
                isEnabled: canDragPinnedParagraphOverlay,
                onDragBegin: { model.beginParagraphOverlayDrag() },
                onDragEnd: { model.endParagraphOverlayDrag() }
            )
        }
    }

    @ViewBuilder
    private func paragraphOverlayControlButton() -> some View {
        if showsParagraphOverlayControls {
            if showsParagraphOverlayPinButton {
                paragraphOverlayControlButton(
                    systemImage: "pin",
                    helpText: L("Pin"),
                    action: { model.toggleParagraphOverlayPin() }
                )
            } else {
                paragraphOverlayControlButton(
                    systemImage: "xmark",
                    helpText: L("Close"),
                    action: { model.dismissOverlay() }
                )
            }
        }
    }

    private func paragraphOverlayControlButton(
        systemImage: String,
        helpText: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(
                    Circle()
                        .fill(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.045))
                )
                .overlay(
                    Circle()
                        .stroke(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.06), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private func pronunciationControl(kind: OverlayPronunciationKind, hasText: Bool) -> some View {
        let isAutoPlayEnabled = kind == .word
            ? model.settings.playWordPronunciation
            : model.settings.playSentencePronunciation
        let isActive = model.isPronunciationPlaying(kind: kind)
        let isFailed: Bool = {
            guard model.activePronunciationRequest?.kind == kind else { return false }
            if case .failed = model.speechPlaybackState { return true }
            return false
        }()
        let label = kind == .word ? L("Word") : L("Sentence")
        let playbackHelp = isFailed
            ? L("Pronunciation failed - click to retry")
            : (isActive ? L("Playing - click to restart") : L("Play pronunciation"))

        return HStack(spacing: 0) {
            Button {
                model.playOverlayPronunciation(kind: kind)
            } label: {
                Group {
                    if isActive, case .loading = model.speechPlaybackState {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: isFailed ? "exclamationmark" : (isActive ? "waveform" : "speaker.wave.2"))
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .foregroundStyle(isActive || isFailed ? Color.accentColor : .secondary)
                .frame(width: 26, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(!hasText)
            .opacity(hasText ? 1 : 0.4)
            .help(playbackHelp)
            .accessibilityLabel(Text(hasText ? "\(playbackHelp) \(label)" : "No \(label) text to pronounce"))

            Divider().frame(height: 14)

            Button {
                if kind == .word {
                    model.settings.playWordPronunciation.toggle()
                } else {
                    model.settings.playSentencePronunciation.toggle()
                }
            } label: {
                HStack(spacing: 3) {
                    Text(L("Auto"))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                    Image(systemName: isAutoPlayEnabled ? "circle.fill" : "circle")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(isAutoPlayEnabled ? Color.accentColor : .secondary)
                .frame(width: 42, height: 22)
            }
            .buttonStyle(.plain)
            .help(isAutoPlayEnabled ? L("Pronunciation: On") : L("Pronunciation: Off"))
            .accessibilityLabel(Text(isAutoPlayEnabled ? L("Pronunciation: On") : L("Pronunciation: Off")))
            .accessibilityValue(Text(isAutoPlayEnabled ? L("On") : L("Off")))
        }
        .padding(.horizontal, 3)
        .background(
            Capsule(style: .continuous)
                .fill(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.045))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.07), lineWidth: 0.5)
        )
    }

    private var paragraphOriginalSectionTitle: String {
        L("Original")
    }

    private func paragraphTranslationSectionTitle(for content: ParagraphOverlayContent) -> String {
        if content.imageTranslationUsed {
            return model.settings.imageTranslationSource.provider.displayName
        }

        return SentenceTranslationSource.SourceType.native.displayName
    }

    private var paragraphHeaderDragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                guard canDragPinnedParagraphOverlay else { return }

                if !isParagraphHeaderDragging {
                    isParagraphHeaderDragging = true
                    refreshParagraphHeaderCursor()
                    model.beginParagraphOverlayDrag()
                }

                model.updateParagraphOverlayDrag(translation: value.translation)
            }
            .onEnded { _ in
                guard isParagraphHeaderDragging else { return }
                model.endParagraphOverlayDrag()
                isParagraphHeaderDragging = false
                refreshParagraphHeaderCursor()
            }
    }

    private func updateParagraphHeaderHover(_ hovering: Bool) {
        guard canDragPinnedParagraphOverlay else {
            resetParagraphHeaderInteractionState()
            return
        }

        isParagraphHeaderHovered = hovering
        refreshParagraphHeaderCursor()
    }

    private func refreshParagraphHeaderCursor() {
        guard canDragPinnedParagraphOverlay else {
            NSCursor.arrow.set()
            return
        }

        if isParagraphHeaderDragging {
            NSCursor.closedHand.set()
        } else if isParagraphHeaderHovered {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func resetParagraphHeaderInteractionState() {
        if isParagraphHeaderDragging {
            model.endParagraphOverlayDrag()
        }

        isParagraphHeaderDragging = false
        isParagraphHeaderHovered = false
        NSCursor.arrow.set()
    }

    private func resetParagraphOriginalEditorState() {
        isParagraphOriginalEditorExpanded = false
    }

    @ViewBuilder
    private func headerSection(content: OverlayContent) -> some View {
        let metrics = WordOverlayHeaderLayoutPolicy.resolve(
            panelWidth: overlayWidth,
            horizontalPadding: wordHeaderHorizontalPadding,
            controlGroupWidth: showsWordOverlayControls ? wordHeaderControlGroupWidth : 0,
            gapBetweenIdentityAndControls: showsWordOverlayControls ? wordHeaderControlGap : 0
        )

        HStack(alignment: .top, spacing: showsWordOverlayControls ? wordHeaderControlGap : 0) {
            wordIdentityGroup(content: content, metrics: metrics)
                .frame(maxWidth: metrics.identityGroupMaxWidth, alignment: .leading)

            Spacer(minLength: 0)

            if showsWordOverlayControls {
                wordHeaderControlGroup(content: content)
                    .frame(width: wordHeaderControlGroupWidth, alignment: .trailing)
            }
        }
        .padding(.horizontal, wordHeaderHorizontalPadding)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func wordIdentityGroup(
        content: OverlayContent,
        metrics: WordOverlayHeaderLayoutPolicy.Metrics
    ) -> some View {
        let displayedPhonetic = WordOverlayHeaderLayoutPolicy.displayedPhonetic(content.phonetic)

        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                wordInlineTitleText(content.word)

                if let displayedPhonetic {
                    phoneticBadge(
                        displayedPhonetic,
                        resistsHorizontalCompression: !metrics.allowsPhoneticBadgeHorizontalCompression
                    )
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                wordTitleText(content.word, maxWidth: metrics.titleMaxWidth)

                if let displayedPhonetic {
                    phoneticBadge(
                        displayedPhonetic,
                        resistsHorizontalCompression: !metrics.allowsPhoneticBadgeHorizontalCompression
                    )
                }
            }
        }
    }

    private func wordInlineTitleText(_ word: String) -> some View {
        Text(word)
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .tracking(0.3)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func wordTitleText(_ word: String, maxWidth: CGFloat) -> some View {
        Text(word)
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .tracking(0.3)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: maxWidth, alignment: .leading)
    }

    private func phoneticBadge(
        _ phonetic: String,
        resistsHorizontalCompression: Bool
    ) -> some View {
        Text(phonetic)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: resistsHorizontalCompression, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.secondary.opacity(0.25), lineWidth: 0.5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.secondary.opacity(0.06))
                    )
            )
    }

    private func wordHeaderControlGroup(content: OverlayContent) -> some View {
        HStack(alignment: .center, spacing: 8) {
            pronunciationControl(
                kind: .word,
                hasText: !content.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )

            Button {
                model.dismissOverlay()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(.secondary.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func errorView(message: String) -> some View {
        AutoDismissErrorView(message: message, onDismiss: { model.dismissOverlay() })
    }

    // MARK: - No Word View

    private var noWordView: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            Text(L("No word detected"))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.8))
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
    }
}

// MARK: - Loading Dots Animation

struct LoadingDotsView: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 4.5, height: 4.5)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .opacity(animating ? 0.8 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                        value: animating
                    )
            }
        }
        .onAppear {
            animating = true
        }
    }
}

private extension Array where Element == String {
    mutating func appendIfMissing(_ value: String) {
        if contains(value) == false {
            append(value)
        }
    }
}

enum ParagraphOriginalVisibilityPolicy {
    struct Decision: Equatable {
        let showsOriginalTextRegion: Bool
        let usesEditableOriginalText: Bool
        let showsOriginalEditorToggle: Bool
        let hidesOriginalTextRegion: Bool

        var usesStableTranslationFont: Bool {
            usesEditableOriginalText || hidesOriginalTextRegion
        }
    }

    static func resolve(
        hasOriginalText: Bool,
        isParagraphOverlayPinned: Bool,
        hidesOriginalTextSetting: Bool,
        isOriginalEditorExpanded: Bool,
        isManualInputFallback: Bool = false,
        hasTranslationOutput: Bool = true
    ) -> Decision {
        let shouldHideOriginalText = hidesOriginalTextSetting && hasTranslationOutput
        let canEditOriginalText = isParagraphOverlayPinned
        let showsEditableFallback = canEditOriginalText && !hasOriginalText
        let showsOriginalEditorToggle = canEditOriginalText && shouldHideOriginalText && hasOriginalText && !isManualInputFallback

        let showsOriginalTextRegion: Bool = if shouldHideOriginalText {
            showsEditableFallback || isManualInputFallback || (canEditOriginalText && isOriginalEditorExpanded)
        } else {
            hasOriginalText || canEditOriginalText
        }
        let usesEditableOriginalText = canEditOriginalText && showsOriginalTextRegion

        return Decision(
            showsOriginalTextRegion: showsOriginalTextRegion,
            usesEditableOriginalText: usesEditableOriginalText,
            showsOriginalEditorToggle: showsOriginalEditorToggle,
            hidesOriginalTextRegion: shouldHideOriginalText && !showsOriginalTextRegion
        )
    }
}

enum WordOverlayTextSelectionPolicy {
    static func usesSelectableText(
        isWordOverlayMode: Bool,
        showsWordOverlayControls: Bool
    ) -> Bool {
        true
    }
}

enum WordOverlayHeaderLayoutPolicy {
    struct Metrics: Equatable {
        let identityGroupMaxWidth: CGFloat
        let titleMaxWidth: CGFloat
        let allowsPhoneticBadgeHorizontalCompression: Bool
    }

    static func resolve(
        panelWidth: CGFloat,
        horizontalPadding: CGFloat,
        controlGroupWidth: CGFloat,
        gapBetweenIdentityAndControls: CGFloat
    ) -> Metrics {
        let contentWidth = max(0, panelWidth - horizontalPadding * 2)
        let reservedControlWidth = max(0, controlGroupWidth) + max(0, gapBetweenIdentityAndControls)
        let identityGroupMaxWidth = max(0, contentWidth - reservedControlWidth)

        return Metrics(
            identityGroupMaxWidth: identityGroupMaxWidth,
            titleMaxWidth: identityGroupMaxWidth,
            allowsPhoneticBadgeHorizontalCompression: false
        )
    }

    static func displayedPhonetic(_ phonetic: String?) -> String? {
        guard let phonetic else { return nil }
        let trimmed = phonetic.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum ParagraphFontSizing {
    static let minFontSize: CGFloat = 10
    static let maxFontSize: CGFloat = 22
    static let baseFontSize: CGFloat = 13
    static let preferredUpscaleFactor: CGFloat = 1.15

    static func optimalFontSize(
        preferredFontSize: CGFloat,
        originalText: String?,
        containerWidth: CGFloat,
        horizontalPadding: CGFloat
    ) -> CGFloat {
        let normalizedPreferredFontSize = normalizedPreferredFontSize(preferredFontSize)
        let targetFontSize = min(normalizedPreferredFontSize * preferredUpscaleFactor, maxFontSize)
        guard let fittingFontSize = fittingFontSizeForOriginalText(
            originalText,
            targetFontSize: targetFontSize,
            containerWidth: containerWidth,
            horizontalPadding: horizontalPadding
        ) else {
            return targetFontSize
        }
        return min(max(fittingFontSize, 1), maxFontSize)
    }

    static func normalizedPreferredFontSize(_ preferredFontSize: CGFloat) -> CGFloat {
        guard preferredFontSize.isFinite, preferredFontSize > 0 else {
            return baseFontSize
        }
        return min(max(preferredFontSize, minFontSize), maxFontSize)
    }

    static func stableFontSize(preferredFontSize: CGFloat) -> CGFloat {
        min(normalizedPreferredFontSize(preferredFontSize) * preferredUpscaleFactor, maxFontSize)
    }

    static func fittingFontSizeForOriginalText(
        _ originalText: String?,
        targetFontSize: CGFloat,
        containerWidth: CGFloat,
        horizontalPadding: CGFloat
    ) -> CGFloat? {
        guard let originalText else {
            return nil
        }

        let trimmedText = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }

        let availableWidth = max(1, containerWidth - horizontalPadding * 2)
        let targetFont = NSFont.systemFont(ofSize: targetFontSize, weight: .medium)
        let targetLineWidth = maximumLineWidth(for: trimmedText, font: targetFont)
        guard targetLineWidth > 0 else {
            return targetFontSize
        }

        if targetLineWidth <= availableWidth {
            return targetFontSize
        }

        var lowerBound: CGFloat = 1
        var upperBound = targetFontSize
        var bestFitFontSize = lowerBound

        for _ in 0..<12 {
            let candidateFontSize = (lowerBound + upperBound) / 2
            let candidateFont = NSFont.systemFont(ofSize: candidateFontSize, weight: .medium)
            let candidateWidth = maximumLineWidth(for: trimmedText, font: candidateFont)

            if candidateWidth <= availableWidth {
                bestFitFontSize = candidateFontSize
                lowerBound = candidateFontSize
            } else {
                upperBound = candidateFontSize
            }
        }

        return bestFitFontSize
    }

    static func maximumLineWidth(
        for text: String,
        font: NSFont
    ) -> CGFloat {
        ParagraphTextStructure.fromText(text)
            .blocks
            .map(\.displayText)
            .filter { !$0.isEmpty }
            .map {
                ceil(
                    ($0 as NSString).size(
                        withAttributes: [.font: font]
                    ).width
                )
            }
            .max() ?? 0
    }
}

private struct SelectableTextView: NSViewRepresentable {
    let text: String
    let font: NSFont
    let textColor: NSColor
    let preferredLineHeight: CGFloat

    func makeNSView(context: Context) -> SelectableTextContainerView {
        let textView = SelectableTextContainerView(frame: .zero)
        textView.update(
            text: text,
            font: font,
            textColor: textColor,
            preferredLineHeight: preferredLineHeight
        )
        return textView
    }

    func updateNSView(_ textView: SelectableTextContainerView, context: Context) {
        textView.update(
            text: text,
            font: font,
            textColor: textColor,
            preferredLineHeight: preferredLineHeight
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SelectableTextContainerView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else {
            return CGSize(width: 0, height: font.pointSize)
        }

        return nsView.measuredSize(forWidth: width)
    }
}

private struct EditableParagraphTextView: NSViewRepresentable {
    let text: String
    let placeholder: String
    let font: NSFont
    let textColor: NSColor
    let placeholderColor: NSColor
    let preferredLineHeight: CGFloat
    let onTextChange: (String) -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextChange: onTextChange, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> EditableParagraphTextContainerView {
        let textView = EditableParagraphTextContainerView(frame: .zero)
        textView.update(
            text: text,
            placeholder: placeholder,
            font: font,
            textColor: textColor,
            placeholderColor: placeholderColor,
            preferredLineHeight: preferredLineHeight,
            coordinator: context.coordinator
        )
        textView.focusIfNeeded()
        return textView
    }

    func updateNSView(_ textView: EditableParagraphTextContainerView, context: Context) {
        context.coordinator.onTextChange = onTextChange
        context.coordinator.onSubmit = onSubmit
        textView.update(
            text: text,
            placeholder: placeholder,
            font: font,
            textColor: textColor,
            placeholderColor: placeholderColor,
            preferredLineHeight: preferredLineHeight,
            coordinator: context.coordinator
        )
        textView.focusIfNeeded()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: EditableParagraphTextContainerView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else {
            return CGSize(width: 0, height: preferredLineHeight)
        }

        return nsView.measuredSize(forWidth: width)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onTextChange: (String) -> Void
        var onSubmit: () -> Void

        init(
            onTextChange: @escaping (String) -> Void,
            onSubmit: @escaping () -> Void
        ) {
            self.onTextChange = onTextChange
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if let containerView = textView.superview as? EditableParagraphTextContainerView {
                containerView.handleTextDidChange()
            }
            onTextChange(textView.string)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    return false
                }
                onSubmit()
                return true
            }

            return false
        }
    }
}

private struct ParagraphOverlayDragHandle: NSViewRepresentable {
    let isEnabled: Bool
    let onDragBegin: () -> Void
    let onDragEnd: () -> Void

    func makeNSView(context: Context) -> ParagraphOverlayDragHandleView {
        let view = ParagraphOverlayDragHandleView(frame: .zero)
        view.update(
            isEnabled: isEnabled,
            onDragBegin: onDragBegin,
            onDragEnd: onDragEnd
        )
        return view
    }

    func updateNSView(_ nsView: ParagraphOverlayDragHandleView, context: Context) {
        nsView.update(
            isEnabled: isEnabled,
            onDragBegin: onDragBegin,
            onDragEnd: onDragEnd
        )
    }
}

private final class ParagraphOverlayDragHandleView: NSView {
    private var isEnabled = false
    private var onDragBegin: (() -> Void)?
    private var onDragEnd: (() -> Void)?

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isEnabled else { return nil }
        return bounds.contains(point) ? self : nil
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard isEnabled else { return }
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let window else {
            super.mouseDown(with: event)
            return
        }

        onDragBegin?()
        NSCursor.closedHand.push()
        defer {
            NSCursor.pop()
            onDragEnd?()
        }

        window.performDrag(with: event)
    }

    func update(
        isEnabled: Bool,
        onDragBegin: @escaping () -> Void,
        onDragEnd: @escaping () -> Void
    ) {
        let enabledChanged = self.isEnabled != isEnabled
        self.isEnabled = isEnabled
        self.onDragBegin = onDragBegin
        self.onDragEnd = onDragEnd

        if enabledChanged {
            discardCursorRects()
        }
    }
}

private final class SelectableTextContainerView: NSView {
    private let textView: NSTextView
    private var cachedMeasurement: (width: CGFloat, height: CGFloat)?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        textView = NSTextView(frame: .zero)
        super.init(frame: frameRect)
        configureTextView()
        addSubview(textView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        text: String,
        font: NSFont,
        textColor: NSColor,
        preferredLineHeight: CGFloat
    ) {
        textView.font = font
        textView.textColor = textColor
        textView.textStorage?.setAttributedString(
            makeAttributedString(
                text: text,
                font: font,
                textColor: textColor,
                preferredLineHeight: preferredLineHeight
            )
        )
        cachedMeasurement = nil
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    func measuredSize(forWidth width: CGFloat) -> CGSize {
        let resolvedWidth = max(1, ceil(width))
        let height = measuredHeight(forWidth: resolvedWidth)
        return CGSize(width: resolvedWidth, height: height)
    }

    override var intrinsicContentSize: CGSize {
        let width = bounds.width > 0 ? bounds.width : cachedMeasurement?.width ?? 0
        guard width > 0 else {
            return CGSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }
        return CGSize(width: NSView.noIntrinsicMetric, height: measuredHeight(forWidth: width))
    }

    override func layout() {
        super.layout()

        let width = bounds.width > 0 ? bounds.width : cachedMeasurement?.width ?? 0
        guard width > 0 else { return }

        let height = measuredHeight(forWidth: width)
        let targetFrame = CGRect(x: 0, y: 0, width: width, height: height)
        if textView.frame != targetFrame {
            textView.frame = targetFrame
        }
    }

    private func measuredHeight(forWidth width: CGFloat) -> CGFloat {
        if let cachedMeasurement,
           abs(cachedMeasurement.width - width) <= 0.5 {
            return cachedMeasurement.height
        }

        guard let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else {
            return 0
        }

        let resolvedWidth = max(1, ceil(width))
        textContainer.containerSize = CGSize(
            width: resolvedWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        if textView.frame.width != resolvedWidth {
            textView.frame = CGRect(x: 0, y: 0, width: resolvedWidth, height: textView.frame.height)
        }

        let glyphRange = layoutManager.glyphRange(for: textContainer)
        layoutManager.ensureLayout(for: textContainer)

        let minimumHeight = ceil((textView.font?.ascender ?? 0) - (textView.font?.descender ?? 0))
        var maxLineFragmentY: CGFloat = 0
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in
            maxLineFragmentY = max(maxLineFragmentY, usedRect.maxY)
        }

        if layoutManager.extraLineFragmentTextContainer == textContainer {
            maxLineFragmentY = max(maxLineFragmentY, layoutManager.extraLineFragmentRect.maxY)
        }

        let textHeight = ceil(maxLineFragmentY) + textView.textContainerInset.height * 2
        let resolvedHeight = max(minimumHeight, textHeight)

        cachedMeasurement = (width, resolvedHeight)
        return resolvedHeight
    }

    private func configureTextView() {
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.focusRingType = .none
        textView.textContainerInset = .zero
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.minSize = .zero
        textView.maxSize = CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autoresizingMask = []
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineBreakMode = .byWordWrapping
    }

    private func makeAttributedString(
        text: String,
        font: NSFont,
        textColor: NSColor,
        preferredLineHeight: CGFloat
    ) -> NSAttributedString {
        ParagraphTextAttributedStringBuilder.build(
            text: text,
            font: font,
            textColor: textColor,
            preferredLineHeight: preferredLineHeight
        )
    }
}

private final class EditableParagraphTextContainerView: NSView {
    private let textView: NSTextView
    private let placeholderLabel: NSTextField
    private var cachedMeasurement: (width: CGFloat, height: CGFloat)?
    private var preferredLineHeight: CGFloat = 20
    private var didRequestInitialFocus = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        textView = NSTextView(frame: .zero)
        placeholderLabel = NSTextField(labelWithString: "")
        super.init(frame: frameRect)
        configureTextView()
        configurePlaceholderLabel()
        addSubview(textView)
        addSubview(placeholderLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        text: String,
        placeholder: String,
        font: NSFont,
        textColor: NSColor,
        placeholderColor: NSColor,
        preferredLineHeight: CGFloat,
        coordinator: EditableParagraphTextView.Coordinator
    ) {
        self.preferredLineHeight = preferredLineHeight
        textView.delegate = coordinator
        textView.font = font
        textView.textColor = textColor
        textView.typingAttributes = typingAttributes(
            font: font,
            textColor: textColor,
            preferredLineHeight: preferredLineHeight
        )
        placeholderLabel.stringValue = placeholder
        placeholderLabel.font = font
        placeholderLabel.textColor = placeholderColor

        if textView.string != text {
            textView.textStorage?.setAttributedString(
                makeAttributedString(
                    text: text,
                    font: font,
                    textColor: textColor,
                    preferredLineHeight: preferredLineHeight
                )
            )
        }
        updatePlaceholderVisibility()
        cachedMeasurement = nil
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    func handleTextDidChange() {
        updatePlaceholderVisibility()
        cachedMeasurement = nil
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    func focusIfNeeded() {
        guard !didRequestInitialFocus else { return }
        didRequestInitialFocus = true

        DispatchQueue.main.async { [weak self] in
            self?.focusTextView()
        }
    }

    func measuredSize(forWidth width: CGFloat) -> CGSize {
        let resolvedWidth = max(1, ceil(width))
        let height = measuredHeight(forWidth: resolvedWidth)
        return CGSize(width: resolvedWidth, height: height)
    }

    override var intrinsicContentSize: CGSize {
        let width = bounds.width > 0 ? bounds.width : cachedMeasurement?.width ?? 0
        guard width > 0 else {
            return CGSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }
        return CGSize(width: NSView.noIntrinsicMetric, height: measuredHeight(forWidth: width))
    }

    override func layout() {
        super.layout()

        let width = bounds.width > 0 ? bounds.width : cachedMeasurement?.width ?? 0
        guard width > 0 else { return }

        let height = measuredHeight(forWidth: width)
        textView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        placeholderLabel.frame = CGRect(x: 0, y: 0, width: width, height: preferredLineHeight)
    }

    override func mouseDown(with event: NSEvent) {
        focusTextView()
        textView.mouseDown(with: event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hitView = super.hitTest(point)
        return hitView === placeholderLabel ? self : hitView
    }

    private func measuredHeight(forWidth width: CGFloat) -> CGFloat {
        if let cachedMeasurement,
           abs(cachedMeasurement.width - width) <= 0.5 {
            return cachedMeasurement.height
        }

        guard let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else {
            return preferredLineHeight
        }

        let resolvedWidth = max(1, ceil(width))
        textContainer.containerSize = CGSize(
            width: resolvedWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        if textView.frame.width != resolvedWidth {
            textView.frame = CGRect(x: 0, y: 0, width: resolvedWidth, height: textView.frame.height)
        }

        let glyphRange = layoutManager.glyphRange(for: textContainer)
        layoutManager.ensureLayout(for: textContainer)

        var maxLineFragmentY: CGFloat = 0
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in
            maxLineFragmentY = max(maxLineFragmentY, usedRect.maxY)
        }

        if layoutManager.extraLineFragmentTextContainer == textContainer {
            maxLineFragmentY = max(maxLineFragmentY, layoutManager.extraLineFragmentRect.maxY)
        }

        let resolvedHeight = max(preferredLineHeight, ceil(maxLineFragmentY))
        cachedMeasurement = (width, resolvedHeight)
        return resolvedHeight
    }

    private func configureTextView() {
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.focusRingType = .none
        textView.textContainerInset = .zero
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.minSize = .zero
        textView.maxSize = CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autoresizingMask = []
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineBreakMode = .byWordWrapping
    }

    private func configurePlaceholderLabel() {
        placeholderLabel.isBezeled = false
        placeholderLabel.drawsBackground = false
        placeholderLabel.isEditable = false
        placeholderLabel.isSelectable = false
        placeholderLabel.lineBreakMode = .byTruncatingTail
        placeholderLabel.maximumNumberOfLines = 1
        placeholderLabel.alphaValue = 0.75
        placeholderLabel.isEnabled = false
    }

    private func focusTextView() {
        guard let window else { return }
        window.makeKey()
        window.makeFirstResponder(textView)
    }

    private func makeAttributedString(
        text: String,
        font: NSFont,
        textColor: NSColor,
        preferredLineHeight: CGFloat
    ) -> NSAttributedString {
        ParagraphTextAttributedStringBuilder.build(
            text: text,
            font: font,
            textColor: textColor,
            preferredLineHeight: preferredLineHeight
        )
    }

    private func typingAttributes(
        font: NSFont,
        textColor: NSColor,
        preferredLineHeight: CGFloat
    ) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = preferredLineHeight
        paragraphStyle.maximumLineHeight = preferredLineHeight
        paragraphStyle.lineBreakMode = .byWordWrapping

        return [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
        ]
    }

    private func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !textView.string.isEmpty
    }
}

private struct ParagraphOverlaySectionCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String?
    let emphasis: Bool
    let content: Content

    init(
        title: String?,
        emphasis: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.emphasis = emphasis
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(fillColor)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(strokeColor, lineWidth: 1)
        }
        .shadow(color: shadowColor, radius: 2, x: 0, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var fillColor: Color {
        if colorScheme == .dark {
            return emphasis ? .white.opacity(0.055) : .white.opacity(0.036)
        }

        return emphasis ? .black.opacity(0.025) : .black.opacity(0.016)
    }

    private var strokeColor: Color {
        if colorScheme == .dark {
            return emphasis ? .white.opacity(0.16) : .white.opacity(0.10)
        }

        return emphasis ? .black.opacity(0.10) : .black.opacity(0.06)
    }

    private var shadowColor: Color {
        if colorScheme == .dark {
            return .black.opacity(emphasis ? 0.16 : 0.10)
        }

        return .black.opacity(emphasis ? 0.05 : 0.03)
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: WordRecord.self, configurations: config)
    return OverlayView()
        .environmentObject(AppModel(
            settings: SettingsStore(),
            permissions: PermissionManager(),
            modelContext: container.mainContext
        ))
        .frame(width: 500, height: 300)
        .background(.gray.opacity(0.3))
}

// MARK: - Auto Dismiss Error View

private struct AutoDismissErrorView: View {
    let message: String
    let onDismiss: () -> Void
    @State private var remainingSeconds: Double = 3.0
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(red: 1.0, green: 0.58, blue: 0.0))
                Text(message)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0fs", max(1, remainingSeconds)))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .onAppear {
            startCountdown()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private func startCountdown() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            remainingSeconds -= 0.1
            if remainingSeconds <= 0 {
                timer?.invalidate()
                timer = nil
                onDismiss()
            }
        }
    }
}
