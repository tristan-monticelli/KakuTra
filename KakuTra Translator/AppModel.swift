import AppKit
import Combine
import Foundation
import NaturalLanguage
import OSLog
import SwiftUI
import Translation
import UserNotifications

struct OverlayContent: Equatable {
    var word: String
    var phonetic: String?
    var sourceLanguageIdentifier: String?
    var dictionaryLookupState: DictionaryLookupState
    var contextSentence: String?
    var contextTranslationState: ParagraphOverlayTranslationState?

    init(
        word: String,
        phonetic: String?,
        sourceLanguageIdentifier: String? = nil,
        dictionaryLookupState: DictionaryLookupState = .notRequested,
        contextSentence: String? = nil,
        contextTranslationState: ParagraphOverlayTranslationState? = nil
    ) {
        self.word = word
        self.phonetic = phonetic
        self.sourceLanguageIdentifier = sourceLanguageIdentifier
        self.dictionaryLookupState = dictionaryLookupState
        self.contextSentence = contextSentence
        self.contextTranslationState = contextTranslationState
    }


}

enum DictionaryLookupState: Equatable {
    case notRequested
    case loading
    case noResults
    case results([DictionaryTermResult])
    case failed(String)
}

struct AnkiCardConfirmationDraft: Identifiable, Equatable {
    let id = UUID()
    var term: String
    var reading: String
    var definition: String
    var contextSentence: String
    var sourceDictionary: String
    var tags: String
    var deckName: String
    var modelName: String

    var isCheckingDuplicate: Bool = false
    var isDuplicate: Bool = false
    var duplicateCheckError: String? = nil

    var isAdding: Bool = false
    var createdNoteID: Int64? = nil
    var additionError: String? = nil
    var configurationError: String? = nil
}

enum OverlayPronunciationKind: Equatable {
    case word
    case sentence
}

enum ActiveTranslationMode: String {
    case inactive
    case word
    case screen

    var title: String {
        switch self {
        case .inactive: return L("Inactive")
        case .word: return L("Word under cursor")
        case .screen: return L("Active screen")
        }
    }

    var menuStatusTitle: String {
        let gesture = switch self {
        case .inactive:
            L("1 press: toggle word under cursor") + " · " + L("2 presses: toggle full-screen translation")
        case .word:
            L("1 press: toggle word under cursor")
        case .screen:
            L("2 presses: toggle full-screen translation")
                + " · " + L("Press Esc to stop full-screen translation.")
        }
        return "\(L("Active mode")): \(title) — \(gesture)"
    }

    var statusItemTitle: String {
        switch self {
        case .inactive: return "KakuTra"
        case .word: return "1 · \(L("Word"))"
        case .screen: return "2 · \(L("Screen"))"
        }
    }
}

struct OverlayPronunciationRequest: Equatable {
    let id: UUID
    let kind: OverlayPronunciationKind
    let text: String
    let languageIdentifier: String?
}

nonisolated struct OverlayStatePublicationDecision: Equatable, Sendable {
    let shouldUpdateState: Bool
    let shouldEndFirstPresentation: Bool

    static func make(isStateChanged: Bool, wasWindowVisible: Bool) -> Self {
        Self(
            shouldUpdateState: isStateChanged,
            shouldEndFirstPresentation: wasWindowVisible
        )
    }
}

struct ParagraphOverlayContent: Equatable {
    var originalText: String?
    var translationState: ParagraphOverlayTranslationState
    var bodyFontSize: CGFloat
    var useFixedFontSize: Bool
    var isRetranslating: Bool
    var isManualInputFallback: Bool

    init(
        originalText: String? = nil,
        translationState: ParagraphOverlayTranslationState,
        bodyFontSize: CGFloat = 13,
        useFixedFontSize: Bool = false,
        isRetranslating: Bool = false,
        isManualInputFallback: Bool = false
    ) {
        self.originalText = originalText
        self.translationState = translationState
        self.bodyFontSize = bodyFontSize
        self.useFixedFontSize = useFixedFontSize
        self.isRetranslating = isRetranslating
        self.isManualInputFallback = isManualInputFallback
    }
}

enum ParagraphOverlayTranslationState: Equatable {
    case loading
    case ready(String)
    case failed(String)
}

enum OverlayState: Equatable {
    case idle
    case loading(String?)
    case result(OverlayContent)
    case paragraphLoading
    case paragraphResult(ParagraphOverlayContent)
    case error(String)
    case noWord
}

private enum CachedLanguageAvailabilityStatus: String {
    case installed
    case supported
    case unsupported

    @available(macOS 15.0, *)
    init(_ status: LanguageAvailability.Status) {
        switch status {
        case .installed:
            self = .installed
        case .supported:
            self = .supported
        case .unsupported:
            self = .unsupported
        @unknown default:
            self = .unsupported
        }
    }

    @available(macOS 15.0, *)
    var translationStatus: LanguageAvailability.Status {
        switch self {
        case .installed:
            return .installed
        case .supported:
            return .supported
        case .unsupported:
            return .unsupported
        }
    }
}



private enum ActiveLookupMode {
    case word
    case selectedTextSentence
}

enum ParagraphOutsideClickDismissalPolicy {
    private static let protectedInset: CGFloat = 8

    static func shouldDismiss(
        mouseLocation: CGPoint,
        isSentenceTranslationPresented: Bool,
        isParagraphOverlayPinned: Bool,
        protectedFrames: [CGRect?]
    ) -> Bool {
        guard isSentenceTranslationPresented,
              isParagraphOverlayPinned else {
            return false
        }

        return !protectedFrames.contains { frame in
            guard let frame, !frame.isNull, !frame.isEmpty else { return false }
            return frame.insetBy(dx: -protectedInset, dy: -protectedInset).contains(mouseLocation)
        }
    }
}

enum TapKeptOverlayPersistencePolicy {
    private static let protectedInset: CGFloat = 16

    static func shouldDismissOnMouseMove(
        startLocation: CGPoint?,
        currentLocation: CGPoint,
        overlayFrame: CGRect?,
        movementThreshold: CGFloat
    ) -> Bool {
        if let overlayFrame,
           !overlayFrame.isNull,
           !overlayFrame.isEmpty,
           overlayFrame.insetBy(dx: -protectedInset, dy: -protectedInset).contains(currentLocation) {
            return false
        }

        guard let startLocation else {
            return false
        }

        let dx = currentLocation.x - startLocation.x
        let dy = currentLocation.y - startLocation.y
        return hypot(dx, dy) >= movementThreshold
    }
}

enum OverlayEscapeDismissalPolicy {
    private static let escapeKeyCode: UInt16 = 53

    static func shouldMonitor(
        isParagraphOverlayPresented: Bool,
        isTapKeptOverlayPresented: Bool
    ) -> Bool {
        isParagraphOverlayPresented || isTapKeptOverlayPresented
    }

    static func shouldDismiss(
        keyCode: UInt16,
        isParagraphOverlayPresented: Bool,
        isTapKeptOverlayPresented: Bool
    ) -> Bool {
        keyCode == escapeKeyCode
            && shouldMonitor(
                isParagraphOverlayPresented: isParagraphOverlayPresented,
                isTapKeptOverlayPresented: isTapKeptOverlayPresented
            )
    }
}

enum ParagraphOverlayControlPolicy {
    static func showsPinButton(
        isParagraphOverlayMode: Bool,
        isParagraphOverlayPinned: Bool,
        isTapKeptOverlay: Bool
    ) -> Bool {
        isParagraphOverlayMode && !isParagraphOverlayPinned && !isTapKeptOverlay
    }
}

enum PersistentOverlayApplicationActivationPolicy {
    static func shouldDismiss(
        isPersistentOverlayPresented: Bool,
        sourceApplicationProcessIdentifier: pid_t?,
        activatedApplicationProcessIdentifier: pid_t,
        ownApplicationProcessIdentifier: pid_t
    ) -> Bool {
        guard isPersistentOverlayPresented else { return false }
        guard activatedApplicationProcessIdentifier != ownApplicationProcessIdentifier else { return false }
        guard activatedApplicationProcessIdentifier != sourceApplicationProcessIdentifier else { return false }
        return true
    }
}

private struct OcrWordCandidate: Sendable {
    let text: String
    let contextSentence: String?
}

private enum OcrWordCandidateLoadResult: Sendable {
    case missingScreenRecordingPermission
    case captureFailed
    case noWord
    case word(OcrWordCandidate)
    case failed(message: String)
    case cancelled
}

@MainActor
final class AppModel: ObservableObject {
    private static let screenTranslationLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "KakuTra",
        category: "ScreenTranslation"
    )

    @Published var overlayState: OverlayState = .idle
    var overlayAnchor: CGPoint = .zero
    var activeParagraphRect: CGRect? = nil
    @Published var overlayPreferredWidth: CGFloat? = nil
    @Published var isParagraphOverlayPinned: Bool = false
    @Published var isTapKeptOverlayPresented: Bool = false
    @Published private(set) var isListening = false
    @Published private(set) var activeTranslationMode: ActiveTranslationMode = .inactive
    @Published private(set) var speechPlaybackState: SpeechPlaybackState = .idle
    @Published private(set) var ankiConnectionState: AnkiConnectionState = .checking
    @Published private(set) var ankiDeckNames: [String] = []
    @Published private(set) var ankiModelNames: [String] = []
    @Published private(set) var ankiModelFieldNames: [String] = []
    @Published var ankiConfirmationDraft: AnkiCardConfirmationDraft? = nil
    @Published private(set) var activePronunciationRequest: OverlayPronunciationRequest?

    @Published var settings: SettingsStore
    let permissions: PermissionManager
    let translationBridge: TranslationBridge
    private var _languagePackManager: Any?

    @available(macOS 15.0, *)
    var languagePackManager: LanguagePackManager? {
        get { _languagePackManager as? LanguagePackManager }
        set { _languagePackManager = newValue }
    }

    private let hotkeyManager = HotkeyManager()
    private let captureService = ScreenCaptureService()
    private let ocrService = OCRService()
    private let selectedTextService = SelectedTextService()
    let localDictionaryService = LocalDictionaryService.shared
    private let ankiConnectClient = AnkiConnectClient()
    private let speechService = SpeechService()
    private let lookupPerformanceReporter: any LookupPerformanceReporting = LookupPerformanceReporter()
    private var cancellables = Set<AnyCancellable>()
    private var lookupTask: Task<Void, Never>?
    private var activeLookupID: UUID?
    private var activeLookupTrace: LookupPerformanceTrace?
    private var isHotkeyActive = false
    private var activeLookupMode: ActiveLookupMode = .word
    private var lastAvailabilityKey: String?
    private var cachedLanguageStatuses: [String: CachedLanguageAvailabilityStatus] = [:]
    private var paragraphTranslationTask: Task<Void, Never>?
    private var screenTranslationTask: Task<Void, Never>?
    private var screenTranslationTasks: [ScreenTranslationCacheKey: Task<Void, Never>] = [:]
    private var screenTranslationPendingKeys = Set<ScreenTranslationCacheKey>()
    private var screenTranslationFailureRetryAfter: [ScreenTranslationCacheKey: Date] = [:]
    private var screenTranslationTextCache = ScreenTranslationTextCache(lifetime: 15 * 60)
    private var screenTranslationObservations: [String: ScreenTranslationObservation] = [:]
    private let screenTranslationTracker = ScreenTranslationTracker()
    private var screenTranslationProtectedTextRects: [CGRect] = []
    private var screenTranslationLastFrameFingerprint: ScreenCaptureFrameFingerprint?
    private var screenTranslationLastFrameDisplayID: CGDirectDisplayID?
    private var screenTranslationUnchangedFrameCount = 0
    private var screenTranslationDisplay: NSScreen?
    private var screenTranslationLastSuccessfulFrameAt: Date?
    private var screenTranslationLastOCRAt: Date?
    private var isScreenTranslationModeActive = false
    private var screenModeWasActiveBeforeHotkey = false

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalOverlayKeyMonitor: Any?
    private var localOverlayKeyMonitor: Any?
    private var globalParagraphMouseMonitor: Any?
    private var localParagraphMouseMonitor: Any?
    private var debounceWorkItem: DispatchWorkItem?
    private var overlayLayoutRefreshWorkItem: DispatchWorkItem?
    private var lastOcrPosition: CGPoint?
    private var tapKeptOverlayReleaseLocation: CGPoint?
    private var translationServiceInitialized = false
    private var persistentOverlaySourceApplicationProcessIdentifier: pid_t?
    private let debounceInterval: TimeInterval = 0.05
    private let overlayLayoutRefreshInterval: TimeInterval = 0.04
    private let positionThreshold: CGFloat = 3.0
    private let tapKeptOverlayMovementThreshold: CGFloat = 16.0

    private let screenTranslationOverlayWindowController = ScreenTranslationOverlayWindowController()
    lazy var overlayWindowController = OverlayWindowController(model: self)
    private let startupLanguageAvailabilityRetryDelays: [UInt64] = [
        1_000_000_000,
        2_000_000_000,
        3_000_000_000,
    ]

    private var supportsSelectedTextTranslation: Bool {
        DistributionChannel.supportsSelectedTextTranslation
    }

    @MainActor
    init(settings: SettingsStore? = nil, permissions: PermissionManager? = nil) {
        let resolvedSettings = settings ?? SettingsStore()
        let resolvedPermissions = permissions ?? PermissionManager()
        self.settings = resolvedSettings
        self.permissions = resolvedPermissions
        self.translationBridge = TranslationBridge()

        // Forward SettingsStore changes to AppModel so SwiftUI redraws
        resolvedSettings.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        speechService.$playbackState
            .sink { [weak self] state in
                self?.speechPlaybackState = state
                if case .idle = state {
                    self?.activePronunciationRequest = nil
                }
            }
            .store(in: &cancellables)

        if #available(macOS 15.0, *) {
            let manager = LanguagePackManager()
            self.languagePackManager = manager
            // Forward LanguagePackManager changes to AppModel so SwiftUI redraws
            manager.objectWillChange
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables)

            manager.$languageStatuses
                .sink { [weak self] statuses in
                    self?.syncCachedLanguageStatuses(statuses)
                }
                .store(in: &cancellables)
        }
        bindSettings()
        resolvedPermissions.$status
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        hotkeyManager.onTrigger = { [weak self] in
            self?.handleHotkeyTrigger()
        }
        hotkeyManager.onTapRelease = { [weak self] in
            self?.handleHotkeyTapRelease()
        }
        hotkeyManager.onDoubleTap = { [weak self] in
            self?.toggleScreenTranslationMode()
        }
        resolvedPermissions.refreshStatus()
        refreshDictionaryStats()
        Task { await refreshAnkiConfiguration() }
    }

    func refreshDictionaryStats() {
        localDictionaryService.refreshStats()
    }

    func refreshAnkiConfiguration() async {
        ankiConnectionState = .checking
        do {
            let configuration = try await ankiConnectClient.configuration()
            let fields: [String]
            if configuration.modelNames.contains(settings.ankiModelName), !settings.ankiModelName.isEmpty {
                fields = try await ankiConnectClient.modelFieldNames(modelName: settings.ankiModelName)
            } else {
                fields = []
            }
            guard !Task.isCancelled else { return }
            ankiDeckNames = configuration.deckNames
            ankiModelNames = configuration.modelNames
            ankiModelFieldNames = fields
            ankiConnectionState = .connected(version: configuration.version)
        } catch is CancellationError {
            return
        } catch {
            if let ankiError = error as? AnkiConnectError,
               case .unavailable = ankiError {
                ankiConnectionState = .notConnected
            } else {
                ankiConnectionState = .failed(error.localizedDescription)
            }
            ankiDeckNames = []
            ankiModelNames = []
            ankiModelFieldNames = []
        }
    }

    func setAnkiModelName(_ name: String) {
        settings.ankiModelName = name
        ankiModelFieldNames = []
        guard !name.isEmpty else { return }
        Task {
            do {
                let fields = try await ankiConnectClient.modelFieldNames(modelName: name)
                guard settings.ankiModelName == name else { return }
                ankiModelFieldNames = fields
            } catch {
                ankiModelFieldNames = []
            }
        }
    }

    func setAnkiFieldMapping(_ fieldName: String, for role: AnkiFieldRole) {
        var mappings = settings.ankiFieldMappings
        if fieldName.isEmpty {
            mappings.removeValue(forKey: role.rawValue)
        } else {
            mappings[role.rawValue] = fieldName
        }
        settings.ankiFieldMappings = mappings
    }

    func prepareAnkiNote(
        term: String,
        reading: String?,
        definition: String,
        source: String,
        contextSentence: String?
    ) {
        overlayWindowController.setInteractive(true)

        var configError: String? = nil
        if case .connected = ankiConnectionState {
            if settings.ankiDeckName.isEmpty || !ankiDeckNames.contains(settings.ankiDeckName) {
                configError = L("Choose a valid Anki deck in Settings.")
            } else if settings.ankiModelName.isEmpty || !ankiModelNames.contains(settings.ankiModelName) {
                configError = L("Choose a valid Anki note type in Settings.")
            } else {
                let termMapped = settings.ankiFieldMappings[AnkiFieldRole.term.rawValue]
                let defMapped = settings.ankiFieldMappings[AnkiFieldRole.definition.rawValue]
                if termMapped == nil || termMapped?.isEmpty == true || !ankiModelFieldNames.contains(termMapped!) {
                    configError = L("Map the required Japanese term field in Settings.")
                } else if defMapped == nil || defMapped?.isEmpty == true || !ankiModelFieldNames.contains(defMapped!) {
                    configError = L("Map the required Definition field in Settings.")
                }
            }
        } else {
            configError = L("AnkiConnect is not connected. Open Anki and enable the AnkiConnect add-on.")
        }

        let draft = AnkiCardConfirmationDraft(
            term: term,
            reading: reading ?? "",
            definition: definition,
            contextSentence: contextSentence ?? "",
            sourceDictionary: source,
            tags: settings.ankiTags,
            deckName: settings.ankiDeckName,
            modelName: settings.ankiModelName,
            isCheckingDuplicate: configError == nil,
            isDuplicate: false,
            configurationError: configError
        )

        ankiConfirmationDraft = draft

        guard configError == nil else { return }

        // Perform duplicate check
        Task {
            do {
                let noteDraft = self.makeAnkiNoteDraft(from: draft)
                let canAdd = try await ankiConnectClient.canAddNotes([noteDraft])
                guard self.ankiConfirmationDraft?.id == draft.id else { return }
                if let canAddFirst = canAdd.first, !canAddFirst {
                    self.ankiConfirmationDraft?.isDuplicate = true
                } else {
                    self.ankiConfirmationDraft?.isDuplicate = false
                }
                self.ankiConfirmationDraft?.isCheckingDuplicate = false
            } catch {
                guard self.ankiConfirmationDraft?.id == draft.id else { return }
                self.ankiConfirmationDraft?.duplicateCheckError = error.localizedDescription
                self.ankiConfirmationDraft?.isCheckingDuplicate = false
            }
        }
    }

    func prepareAnkiNote(for result: DictionaryTermResult, contextSentence: String?) {
        prepareAnkiNote(
            term: result.term,
            reading: result.reading,
            definition: result.glosses.joined(separator: "\n"),
            source: result.dictionary,
            contextSentence: contextSentence
        )
    }

    private func makeAnkiNoteDraft(from draft: AnkiCardConfirmationDraft) -> AnkiNoteDraft {
        var fields: [String: String] = [:]
        for role in AnkiFieldRole.allCases {
            guard let fieldName = settings.ankiFieldMappings[role.rawValue], !fieldName.isEmpty else {
                continue
            }
            switch role {
            case .term:
                fields[fieldName] = draft.term
            case .reading:
                fields[fieldName] = draft.reading
            case .definition:
                fields[fieldName] = draft.definition
            case .context:
                fields[fieldName] = draft.contextSentence
            case .source:
                fields[fieldName] = draft.sourceDictionary
            }
        }
        let tags = draft.tags
            .split(separator: " ")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return AnkiNoteDraft(
            deckName: draft.deckName,
            modelName: draft.modelName,
            fields: fields,
            tags: tags
        )
    }

    func confirmAddAnkiNote() {
        guard var draft = ankiConfirmationDraft,
              !draft.isAdding,
              !draft.isDuplicate,
              draft.configurationError == nil else {
            return
        }

        draft.isAdding = true
        draft.additionError = nil
        ankiConfirmationDraft = draft

        let noteDraft = makeAnkiNoteDraft(from: draft)

        Task {
            do {
                let noteID = try await ankiConnectClient.addNote(noteDraft)
                guard self.ankiConfirmationDraft?.id == draft.id else { return }
                self.ankiConfirmationDraft?.isAdding = false
                self.ankiConfirmationDraft?.createdNoteID = noteID
            } catch {
                guard self.ankiConfirmationDraft?.id == draft.id else { return }
                self.ankiConfirmationDraft?.isAdding = false
                self.ankiConfirmationDraft?.additionError = error.localizedDescription
            }
        }
    }

    func dismissAnkiConfirmation() {
        ankiConfirmationDraft = nil
        overlayWindowController.setInteractive(false)
    }

    func openSettingsTab(_ tab: SettingsTab) {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.openSettings(initialTab: tab)
        } else {
            NotificationCenter.default.post(name: .switchSettingsTab, object: tab)
        }
    }

    func handleHotkeyTrigger() {
        screenModeWasActiveBeforeHotkey = activeTranslationMode == .screen
        stopScreenTranslationMode()
        if #available(macOS 15.0, *) {
            ensureTranslationService()
        }
        isHotkeyActive = true
        activeTranslationMode = .word
        activeLookupMode = .word
        isParagraphOverlayPinned = false
        persistentOverlaySourceApplicationProcessIdentifier = nil
        isTapKeptOverlayPresented = false
        tapKeptOverlayReleaseLocation = nil
        stopOverlayEscapeMonitoring()
        let mouseLocation = NSEvent.mouseLocation
        lastOcrPosition = mouseLocation
        setOverlayAnchor(mouseLocation)
        overlayWindowController.setInteractive(false)
        startMouseTracking()
        updateOverlay(state: .loading(nil), anchor: mouseLocation)
        startLookup(at: mouseLocation)
    }

    func setListening(_ listening: Bool) {
        guard isListening != listening else { return }
        stopScreenTranslationMode()
        isListening = listening
        activeTranslationMode = listening ? .word : .inactive
        if listening {
            if #available(macOS 15.0, *) {
                ensureTranslationService()
            }
            activeLookupMode = .word
            isParagraphOverlayPinned = false
            isTapKeptOverlayPresented = false
            tapKeptOverlayReleaseLocation = nil
                lastOcrPosition = nil
            let position = NSEvent.mouseLocation
            setOverlayAnchor(position)
            overlayWindowController.setInteractive(false)
            startMouseTracking()
            updateOverlay(state: .loading(nil), anchor: position)
            startLookup(at: position)
        } else {
            isHotkeyActive = false
            hotkeyManager.resetState()
            stopMouseTracking()
            cancelActiveLookupWork()
            hideOverlay()
        }
    }

    func performStatusBarModeAction() {
        guard activeTranslationMode != .inactive else {
            setListening(true)
            return
        }

        if isScreenTranslationModeActive {
            stopScreenTranslationMode()
        }
        isListening = false
        isHotkeyActive = false
        activeTranslationMode = .inactive
        activeLookupMode = .word
        hotkeyManager.resetState()
        stopMouseTracking()
        cancelActiveLookupWork()
        dismissOverlay()
    }

    func handleHotkeyTapRelease() {
        if screenModeWasActiveBeforeHotkey {
            screenModeWasActiveBeforeHotkey = false
            isHotkeyActive = false
            setListening(true)
            return
        }

        if activeLookupMode == .word, !isParagraphOverlayPinned {
            setListening(!isListening)
            isHotkeyActive = false
            return
        }
        finishHotkeyRelease()
    }

    private func finishHotkeyRelease() {
        let shouldKeepSentenceOverlayVisible = isParagraphOverlayPinned && isSentenceTranslationPresented

        isHotkeyActive = false
        if isListening {
            return
        }

        if shouldKeepSentenceOverlayVisible {
            stopMouseTracking()
            overlayWindowController.setInteractive(true)
            syncOverlayDismissalMonitoring()
            return
        }

        stopMouseTracking()
        activeLookupMode = .word
        cancelActiveLookupWork()
        hideOverlay()
    }

    private func toggleScreenTranslationMode() {
        if screenModeWasActiveBeforeHotkey {
            screenModeWasActiveBeforeHotkey = false
            stopScreenTranslationMode()
            isHotkeyActive = false
            isListening = false
            activeTranslationMode = .inactive
            stopMouseTracking()
            cancelActiveLookupWork()
            dismissOverlay()
            return
        }
        if isScreenTranslationModeActive {
            stopScreenTranslationMode()
            return
        }

        isHotkeyActive = false
        isListening = false
        stopMouseTracking()
        cancelActiveLookupWork()
        paragraphTranslationTask?.cancel()
        paragraphTranslationTask = nil
        hideOverlay()
        stopParagraphOutsideClickMonitoring()
        isParagraphOverlayPinned = false
        isTapKeptOverlayPresented = false
        screenTranslationLastFrameFingerprint = nil
        screenTranslationLastFrameDisplayID = nil
        screenTranslationUnchangedFrameCount = 0
        screenTranslationLastOCRAt = nil
        screenTranslationTracker.reset()
        isScreenTranslationModeActive = true
        activeTranslationMode = .screen
        startOverlayEscapeMonitoringIfNeeded()
        refreshFullScreenTranslation()
    }

    private func refreshFullScreenTranslation() {
        guard isScreenTranslationModeActive else { return }
        screenTranslationTask?.cancel()
        screenTranslationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.isScreenTranslationModeActive, !Task.isCancelled {
                await self.translateCurrentDisplayFrame()
                do {
                    try await Task.sleep(nanoseconds: 180_000_000)
                } catch {
                    return
                }
            }
        }
    }

    private func translateCurrentDisplayFrame() async {
        guard isScreenTranslationModeActive, !Task.isCancelled else { return }
        if #available(macOS 15.0, *) {
            ensureTranslationService()
        } else {
            return
        }

        guard permissions.status.screenRecording || CGPreflightScreenCaptureAccess() else {
            updateOverlay(state: .error(L("Enable Screen Recording")), anchor: NSEvent.mouseLocation)
            stopScreenTranslationMode()
            return
        }
        guard let capture = await captureService.captureCurrentDisplay(),
              isScreenTranslationModeActive,
              !Task.isCancelled else {
            hideScreenTranslationFrameIfStale()
            return
        }

        let fingerprintStart = ProcessInfo.processInfo.systemUptime
        let fingerprint = ScreenCaptureFrameFingerprint.make(from: capture.image)
        let fingerprintMilliseconds = (ProcessInfo.processInfo.systemUptime - fingerprintStart) * 1_000
        Self.screenTranslationLogger.debug(
            "Frame fingerprint computed durationMs=\(fingerprintMilliseconds, privacy: .public)"
        )
        if let fingerprint,
           fingerprint == screenTranslationLastFrameFingerprint,
           capture.region.displayID == screenTranslationLastFrameDisplayID {
            // Keep existing overlays and translations; only the capture was needed
            // to establish that the display has not changed since the last OCR.
            screenTranslationLastSuccessfulFrameAt = .now
            screenTranslationUnchangedFrameCount += 1
            if screenTranslationUnchangedFrameCount.isMultiple(of: 10) {
                Self.screenTranslationLogger.info(
                    "Skipped Vision OCR for unchanged full display frames count=\(self.screenTranslationUnchangedFrameCount, privacy: .public)"
                )
            }
            return
        }
        screenTranslationUnchangedFrameCount = 0

        // Track the recognized blocks between OCR refreshes. A move or a moderate
        // resize updates patch geometry without re-running text recognition.
        if capture.region.displayID == screenTranslationLastFrameDisplayID,
           let lastOCRAt = screenTranslationLastOCRAt,
           Date.now.timeIntervalSince(lastOCRAt) < 4,
           !screenTranslationObservations.isEmpty,
           let trackedBoxes = await screenTranslationTracker.track(in: capture.image),
           !trackedBoxes.isEmpty {
            let oldObservations = screenTranslationObservations
            for (id, normalizedBox) in trackedBoxes {
                guard var observation = screenTranslationObservations[id] else { continue }
                let previousHeight = observation.rect.height
                let trackedRect = CGRect(
                    x: capture.region.rect.minX + normalizedBox.minX * capture.region.rect.width,
                    y: capture.region.rect.minY + normalizedBox.minY * capture.region.rect.height,
                    width: normalizedBox.width * capture.region.rect.width,
                    height: normalizedBox.height * capture.region.rect.height
                )
                observation.rect = trackedRect
                if previousHeight > 0 {
                    observation.fontSize = min(96, max(8, observation.fontSize * trackedRect.height / previousHeight))
                }
                screenTranslationObservations[id] = observation
            }
            screenTranslationProtectedTextRects = Self.repositionProtectedRects(
                screenTranslationProtectedTextRects,
                from: Array(oldObservations.values),
                to: Array(screenTranslationObservations.values)
            )
            screenTranslationDisplay = capture.region.screen
            screenTranslationLastFrameFingerprint = fingerprint
            screenTranslationLastFrameDisplayID = capture.region.displayID
            screenTranslationLastSuccessfulFrameAt = .now
            renderCurrentScreenTranslations()
            return
        }

        do {
            let recognized = try await ocrService.recognizeParagraphsWithRawLines(
                in: capture.image,
                language: "auto",
                reportsPerformance: true
            )
            guard isScreenTranslationModeActive, !Task.isCancelled else { return }

            screenTranslationProtectedTextRects = recognized.lines.map { line in
                CGRect(
                    x: capture.region.rect.minX + line.boundingBox.minX * capture.region.rect.width,
                    y: capture.region.rect.minY + line.boundingBox.minY * capture.region.rect.height,
                    width: line.boundingBox.width * capture.region.rect.width,
                    height: line.boundingBox.height * capture.region.rect.height
                )
            }
            screenTranslationLastFrameFingerprint = fingerprint
            screenTranslationLastFrameDisplayID = capture.region.displayID

            // Filter OCR lines before paragraph grouping so an eligible CJK line
            // cannot pull adjacent English or other unsupported lines into the
            // same translation request.
            let supportedLinesByLanguage = Dictionary(grouping: recognized.lines.compactMap { line -> (String, RecognizedTextLine)? in
                LanguageClassificationService.supportedOCRLanguage(for: line.text)
                    .map { ($0, line) }
            }, by: \.0)
            let supportedParagraphs = supportedLinesByLanguage.keys.sorted().flatMap { language in
                OCRService.groupParagraphs(from: supportedLinesByLanguage[language, default: []].map(\.1))
                    .map { (language, $0) }
            }

            var occurrenceCounts: [ScreenTranslationCacheKey: Int] = [:]
            var observations: [String: ScreenTranslationObservation] = [:]
            for (sourceIdentifier, paragraph) in supportedParagraphs {
                let cacheKey = ScreenTranslationCacheKey(
                    languageIdentifier: sourceIdentifier,
                    text: paragraph.text
                )
                guard !cacheKey.normalizedText.isEmpty else { continue }
                let occurrence = occurrenceCounts[cacheKey, default: 0]
                occurrenceCounts[cacheKey] = occurrence + 1
                let stableID = "\(cacheKey.stableIdentifier)#\(occurrence)"
                let screenRect = CGRect(
                    x: capture.region.rect.minX + paragraph.boundingBox.minX * capture.region.rect.width,
                    y: capture.region.rect.minY + paragraph.boundingBox.minY * capture.region.rect.height,
                    width: paragraph.boundingBox.width * capture.region.rect.width,
                    height: paragraph.boundingBox.height * capture.region.rect.height
                )
                let style = ScreenTranslationPatchStyleResolver.resolve(
                    captureImage: capture.image,
                    captureRect: capture.region.rect,
                    sourceRect: screenRect
                )
                observations[stableID] = ScreenTranslationObservation(
                    id: stableID,
                    cacheKey: cacheKey,
                    originalText: paragraph.text,
                    rect: screenRect,
                    style: style,
                    fontSize: estimatedDisplayFontSize(from: paragraph.lines, in: capture.region.rect)
                )
            }

            screenTranslationTextCache.removeExpired()
            for observation in observations.values {
                screenTranslationTextCache.refreshLifetime(for: observation.cacheKey)
            }
            screenTranslationFailureRetryAfter = screenTranslationFailureRetryAfter.filter { $0.value > .now }
            screenTranslationObservations = Self.removeOverlappingDuplicateObservations(Array(observations.values))
                .reduce(into: [:]) { $0[$1.id] = $1 }
            screenTranslationTracker.seed(Array(screenTranslationObservations.values), captureRect: capture.region.rect)
            screenTranslationLastOCRAt = .now
            screenTranslationDisplay = capture.region.screen
            screenTranslationLastSuccessfulFrameAt = .now
            renderCurrentScreenTranslations()

            let precedesInReadingOrder: (ScreenTranslationObservation, ScreenTranslationObservation) -> Bool = { lhs, rhs in
                if lhs.rect.maxY != rhs.rect.maxY {
                    return lhs.rect.maxY > rhs.rect.maxY
                }
                if lhs.rect.minX != rhs.rect.minX {
                    return lhs.rect.minX < rhs.rect.minX
                }
                return lhs.cacheKey.stableIdentifier < rhs.cacheKey.stableIdentifier
            }
            let uniqueObservations = Dictionary(
                screenTranslationObservations.values.map { ($0.cacheKey, $0) },
                uniquingKeysWith: { first, candidate in
                    precedesInReadingOrder(first, candidate) ? first : candidate
                }
            ).values.sorted(by: precedesInReadingOrder)
            for observation in uniqueObservations
                where screenTranslationTextCache.translation(for: observation.cacheKey) == nil
                    && screenTranslationPendingKeys.contains(observation.cacheKey) == false
                    && screenTranslationFailureRetryAfter[observation.cacheKey] == nil
            {
                guard screenTranslationPendingKeys.count < 6 else { break }
                startScreenTranslation(for: observation)
            }
        } catch is CancellationError {
            return
        } catch {
            hideScreenTranslationFrameIfStale()
        }
    }

    private func startScreenTranslation(for observation: ScreenTranslationObservation) {
        let key = observation.cacheKey
        guard screenTranslationPendingKeys.insert(key).inserted else { return }
        screenTranslationTasks[key] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.screenTranslationPendingKeys.remove(key)
                self.screenTranslationTasks.removeValue(forKey: key)
            }
            guard self.isScreenTranslationModeActive, !Task.isCancelled else { return }

            do {
                let translated = try await self.translationBridge.translate(
                    text: observation.originalText,
                    source: Locale.Language(identifier: key.languageIdentifier),
                    target: Locale.Language(identifier: "en")
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                guard self.isScreenTranslationModeActive, !Task.isCancelled else { return }
                guard !translated.isEmpty,
                      translated.caseInsensitiveCompare(observation.originalText.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame else {
                    self.screenTranslationFailureRetryAfter[key] = .now.addingTimeInterval(8)
                    return
                }
                self.screenTranslationTextCache.store(translated, for: key)
                self.renderCurrentScreenTranslations()
            } catch {
                guard !Task.isCancelled else { return }
                self.screenTranslationFailureRetryAfter[key] = .now.addingTimeInterval(8)
            }
        }
    }

    private func renderCurrentScreenTranslations() {
        guard isScreenTranslationModeActive, let screen = screenTranslationDisplay else {
            screenTranslationOverlayWindowController.hide()
            return
        }
        let items = screenTranslationObservations.values.compactMap { observation -> ScreenTranslationOverlayItem? in
            guard let translation = screenTranslationTextCache.translation(for: observation.cacheKey) else {
                return nil
            }
            return observation.overlayItem(translation: translation)
        }
        screenTranslationOverlayWindowController.show(
            items: items,
            protectedTextRects: screenTranslationProtectedTextRects,
            on: screen
        )
    }

    private static func removeOverlappingDuplicateObservations(
        _ observations: [ScreenTranslationObservation]
    ) -> [ScreenTranslationObservation] {
        let ordered = observations.sorted { lhs, rhs in
            if lhs.cacheKey.normalizedText != rhs.cacheKey.normalizedText {
                return lhs.cacheKey.normalizedText < rhs.cacheKey.normalizedText
            }
            return lhs.rect.width * lhs.rect.height > rhs.rect.width * rhs.rect.height
        }
        var kept: [ScreenTranslationObservation] = []
        for candidate in ordered {
            let isDuplicate = kept.contains { existing in
                guard existing.cacheKey == candidate.cacheKey else { return false }
                let intersection = existing.rect.intersection(candidate.rect)
                guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return false }
                let smallerArea = min(existing.rect.width * existing.rect.height,
                                      candidate.rect.width * candidate.rect.height)
                return smallerArea > 0 && intersection.width * intersection.height / smallerArea >= 0.72
            }
            if !isDuplicate { kept.append(candidate) }
        }
        return kept
    }

    private static func repositionProtectedRects(
        _ protectedRects: [CGRect],
        from oldObservations: [ScreenTranslationObservation],
        to newObservations: [ScreenTranslationObservation]
    ) -> [CGRect] {
        let newByID = Dictionary(uniqueKeysWithValues: newObservations.map { ($0.id, $0) })
        return protectedRects.map { protectedRect in
            let match = oldObservations
                .filter { $0.rect.intersects(protectedRect) }
                .max { lhs, rhs in
                    lhs.rect.intersection(protectedRect).width * lhs.rect.intersection(protectedRect).height
                        < rhs.rect.intersection(protectedRect).width * rhs.rect.intersection(protectedRect).height
                }
            guard let match, let updated = newByID[match.id], match.rect.width > 0, match.rect.height > 0 else {
                return protectedRect
            }
            let xRatio = (protectedRect.minX - match.rect.minX) / match.rect.width
            let yRatio = (protectedRect.minY - match.rect.minY) / match.rect.height
            let widthRatio = protectedRect.width / match.rect.width
            let heightRatio = protectedRect.height / match.rect.height
            return CGRect(
                x: updated.rect.minX + xRatio * updated.rect.width,
                y: updated.rect.minY + yRatio * updated.rect.height,
                width: widthRatio * updated.rect.width,
                height: heightRatio * updated.rect.height
            )
        }
    }

    private func hideScreenTranslationFrameIfStale(now: Date = .now) {
        guard let lastSuccessful = screenTranslationLastSuccessfulFrameAt,
              now.timeIntervalSince(lastSuccessful) >= 2 else { return }
        screenTranslationObservations.removeAll()
        screenTranslationProtectedTextRects.removeAll()
        screenTranslationLastFrameFingerprint = nil
        screenTranslationLastFrameDisplayID = nil
        screenTranslationUnchangedFrameCount = 0
        screenTranslationLastOCRAt = nil
        screenTranslationTracker.reset()
        screenTranslationDisplay = nil
        screenTranslationOverlayWindowController.hide()
    }

    private func stopScreenTranslationMode() {
        guard isScreenTranslationModeActive else { return }
        isScreenTranslationModeActive = false
        screenTranslationTask?.cancel()
        screenTranslationTask = nil
        for task in screenTranslationTasks.values { task.cancel() }
        screenTranslationTasks.removeAll()
        screenTranslationPendingKeys.removeAll()
        screenTranslationFailureRetryAfter.removeAll()
        screenTranslationObservations.removeAll()
        screenTranslationProtectedTextRects.removeAll()
        screenTranslationLastFrameFingerprint = nil
        screenTranslationLastFrameDisplayID = nil
        screenTranslationUnchangedFrameCount = 0
        screenTranslationLastOCRAt = nil
        screenTranslationTracker.reset()
        screenTranslationDisplay = nil
        screenTranslationLastSuccessfulFrameAt = nil
        screenTranslationOverlayWindowController.hide()
        translationBridge.cancelAllPendingRequests()
        if activeTranslationMode == .screen {
            activeTranslationMode = isListening ? .word : .inactive
        }
        syncOverlayDismissalMonitoring()
    }

    func playOverlayPronunciation(kind: OverlayPronunciationKind) {
        let request: OverlayPronunciationRequest?
        switch kind {
        case .word:
            guard case .result(let content) = overlayState else { return }
            let text: String = {
                if case .results(let entries) = content.dictionaryLookupState,
                   let first = entries.first {
                    if let reading = WordOverlayHeaderLayoutPolicy.displayedDictionaryReading(
                        reading: first.reading,
                        for: content.word,
                        sourceLanguageIdentifier: content.sourceLanguageIdentifier
                    ) {
                        return reading
                    }
                    let term = first.term.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !term.isEmpty { return term }
                }
                return content.word.trimmingCharacters(in: .whitespacesAndNewlines)
            }()
            guard !text.isEmpty else { return }
            request = OverlayPronunciationRequest(
                id: UUID(),
                kind: kind,
                text: text,
                languageIdentifier: LanguageClassificationService.supportedOCRLanguage(for: text)
            )
        case .sentence:
            guard case .paragraphResult(let content) = overlayState,
                  let originalText = content.originalText else { return }
            let text = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            request = OverlayPronunciationRequest(
                id: UUID(),
                kind: kind,
                text: text,
                languageIdentifier: LanguageClassificationService.supportedOCRLanguage(for: text)
            )
        }

        guard let request else { return }
        activePronunciationRequest = request
        speechService.speak(
            request.text,
            language: request.languageIdentifier.flatMap { Locale.Language(identifier: $0).languageCode?.identifier },
            gender: settings.voiceGender,
            requestID: request.id
        )
    }

    func isPronunciationPlaying(kind: OverlayPronunciationKind) -> Bool {
        let requestMatches = activePronunciationRequest?.kind == kind
        let automaticKindMatches: Bool = switch (kind, activeLookupMode) {
        case (.word, .word), (.sentence, .selectedTextSentence):
            true
        default:
            false
        }
        guard requestMatches || (activePronunciationRequest == nil && automaticKindMatches) else { return false }
        switch speechPlaybackState {
        case .loading, .playing:
            return true
        case .idle, .failed:
            return false
        }
    }

    /// 手动关闭气泡（用于非持续翻译模式）
    func dismissOverlay() {
        if isListening {
            cancelActiveLookupWork()
            hideOverlay()
            return
        }
        activeLookupMode = .word
        isHotkeyActive = false
        if !isScreenTranslationModeActive { activeTranslationMode = .inactive }
        isTapKeptOverlayPresented = false
        tapKeptOverlayReleaseLocation = nil
        stopMouseTracking()
        stopOverlayEscapeMonitoring()
        cancelActiveLookupWork()
        hideOverlay()
    }

    func toggleParagraphOverlayPin() {
        isParagraphOverlayPinned.toggle()
        if isParagraphOverlayPinned {
            armPersistentOverlayApplicationMonitoring()
            overlayWindowController.setInteractive(true)
        } else {
            persistentOverlaySourceApplicationProcessIdentifier = nil
        }
        syncOverlayDismissalMonitoring()
    }

    func beginParagraphOverlayDrag() {
        guard isParagraphOverlayPresented, isParagraphOverlayPinned else { return }
        overlayWindowController.beginManualPositioning()
    }

    func endParagraphOverlayDrag() {
        guard isParagraphOverlayPresented, isParagraphOverlayPinned else { return }
        overlayWindowController.endManualPositioning()
        refreshParagraphOverlayLayoutImmediately()
    }

    private func startMouseTracking() {
        guard globalMouseMonitor == nil else { return }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseMoved()
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor in
                self?.handleMouseMoved()
            }
            return event
        }
    }

    private func stopMouseTracking() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        lastOcrPosition = nil
    }

    private func handleMouseMoved() {
        if ankiConfirmationDraft != nil {
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let isInside = overlayWindowController.isMouseInside(point: mouseLocation)

        if isInside {
            // User moved cursor into overlay card: make interactive for tooltips, text selection & buttons
            overlayWindowController.setInteractive(true)
            return
        } else {
            if isTapKeptOverlayPresented {
                handleTapKeptOverlayMouseMoved()
                return
            }
            // Keep the overlay non-interactive while scanning text under the cursor.
            overlayWindowController.setInteractive(false)
        }

        guard isHotkeyActive || isListening else { return }
        guard activeLookupMode == .word else { return }

        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self = self,
                      self.isHotkeyActive || self.isListening else { return }
                guard self.ankiConfirmationDraft == nil else { return }

                let currentPosition = NSEvent.mouseLocation
                guard !self.overlayWindowController.isMouseInside(point: currentPosition) else { return }

                if let lastPosition = self.lastOcrPosition {
                    let distance = hypot(currentPosition.x - lastPosition.x, currentPosition.y - lastPosition.y)
                    if distance < self.positionThreshold {
                        return
                    }
                }

                self.lastOcrPosition = currentPosition
                self.setOverlayAnchor(currentPosition)
                if case .idle = self.overlayState {
                    self.startLookup(
                        at: currentPosition,
                        allowAccessibilitySelection: true
                    )
                } else {
                    self.overlayWindowController.move(to: currentPosition)
                    self.startLookup(
                        at: currentPosition,
                        allowAccessibilitySelection: true
                    )
                }
            }
        }
        debounceWorkItem = workItem

        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func handleTapKeptOverlayMouseMoved() {
        let shouldDismiss = TapKeptOverlayPersistencePolicy.shouldDismissOnMouseMove(
            startLocation: tapKeptOverlayReleaseLocation,
            currentLocation: NSEvent.mouseLocation,
            overlayFrame: overlayWindowController.visibleFrame,
            movementThreshold: tapKeptOverlayMovementThreshold
        )

        guard shouldDismiss else { return }
        dismissOverlay()
    }

    private func startLookup(
        at mouseLocation: CGPoint,
        allowAccessibilitySelection: Bool = true
    ) {
        activeLookupMode = .word
        cancelActiveLookupWork(outcome: .superseded)
        let lookupID = UUID()
        let trace = LookupPerformanceTrace(lookupID: lookupID)
        activeLookupID = lookupID
        activeLookupTrace = trace
        lookupPerformanceReporter.beginLookup(trace)

        let selectedTextEnabled = allowAccessibilitySelection && settings.selectedTextTranslationEnabled
        let hasAccessibilityPermission = permissions.status.accessibility
        let selectedTextProbeRequest = supportsSelectedTextTranslation
            && allowAccessibilitySelection
            && selectedTextEnabled
            && hasAccessibilityPermission
            ? SelectedTextProbeRequest.capture(mouseLocation: mouseLocation)
            : nil
        let request = SinglePressLookupRequest(
            lookupID: lookupID,
            mouseLocation: mouseLocation,
            supportsSelectedText: supportsSelectedTextTranslation && allowAccessibilitySelection,
            selectedTextEnabled: selectedTextEnabled,
            hasAccessibilityPermission: hasAccessibilityPermission,
            selectedTextProbeRequest: selectedTextProbeRequest
        )
        lookupTask = Task { [weak self] in
            await self?.performLookup(request: request)
        }
    }

    func performLookup(request: SinglePressLookupRequest) async {
        let lookupID = request.lookupID
        guard !Task.isCancelled, activeLookupID == lookupID else { return }
        let performance = lookupPerformanceContext(for: lookupID)
        performance?.begin(.routeResolution)
        let selectedTextProbeRequest = request.selectedTextProbeRequest

        let decision = await SinglePressLookupCoordinator.resolve(
            request: request,
            accessibilityProbe: { [weak self] probeRequest in
                guard let self else {
                    return SinglePressLookupResolution(
                        intent: .ocrWord
                    )
                }
                guard let selectedTextProbeRequest else {
                    return SinglePressLookupResolution(
                        intent: .ocrWord
                    )
                }
                performance?.begin(.accessibilityProbe)
                let resolution = await self.resolveSinglePressLookupIntent(
                    request: probeRequest,
                    selectedTextProbeRequest: selectedTextProbeRequest
                )
                let remainsActive = !Task.isCancelled
                    && self.activeLookupID == probeRequest.lookupID
                performance?.end(
                    .accessibilityProbe,
                    outcome: remainsActive ? .succeeded : .cancelled
                )
                return resolution
            },
            loadOCRCandidate: { [weak self] candidateRequest in
                guard let self else { return OcrWordCandidateLoadResult.cancelled }
                return await self.loadOcrWordCandidate(request: candidateRequest)
            },
            routeResolved: { [weak self] route in
                guard let self else { return }
                performance?.end(.routeResolution, outcome: .succeeded)
                guard let trace = performance?.trace else { return }
                switch route {
                case .selectedText:
                    self.lookupPerformanceReporter.recordRoute(
                        .accessibilitySelection,
                        trace: trace
                    )
                case .ocr:
                    self.lookupPerformanceReporter.recordRoute(
                        request.supportsSelectedText ? .directOCR : .appStoreOCR,
                        trace: trace
                    )
                }
            }
        )

        guard !Task.isCancelled, activeLookupID == lookupID else {
            performance?.end(.routeResolution, outcome: .cancelled)
            return
        }

        switch decision {
        case .selectedText(let snapshot):
            activeLookupMode = .selectedTextSentence
            await performSelectedTextSentenceLookup(
                snapshot: snapshot,
                lookupID: lookupID,
                mouseLocation: request.mouseLocation
            )

        case .ocr(let candidate):
            activeLookupMode = .word
            await presentOcrWordCandidate(candidate, request: request)

        case .cancelled:
            performance?.end(.routeResolution, outcome: .cancelled)
        }
    }

    private func loadOcrWordCandidate(
        request: SinglePressLookupRequest
    ) async -> OcrWordCandidateLoadResult {
        let lookupID = request.lookupID
        let mouseLocation = request.mouseLocation
        let performance = lookupPerformanceContext(for: lookupID)
        var hasScreenRecording = permissions.status.screenRecording
        if !hasScreenRecording && CGPreflightScreenCaptureAccess() {
            hasScreenRecording = true
            Task { @MainActor in self.permissions.refreshStatus() }
        }

        guard let capture = await captureService.captureAroundCursor(
            at: mouseLocation,
            performance: performance
        ) else {
            if !hasScreenRecording && !CGPreflightScreenCaptureAccess() {
                return .missingScreenRecordingPermission
            }
            return Task.isCancelled || activeLookupID != lookupID
                ? .cancelled
                : .captureFailed
        }
        if !permissions.status.screenRecording {
            Task { @MainActor in self.permissions.refreshStatus() }
        }
        guard !Task.isCancelled, activeLookupID == lookupID else { return .cancelled }

        let normalizedPoint = normalizedCursorPoint(mouseLocation, in: capture.region.rect)
        do {
            performance?.begin(.ocr)
            let words = try await ocrService.recognizeWords(
                in: capture.image,
                language: settings.sourceLanguage
            )
            guard !Task.isCancelled, activeLookupID == lookupID else {
                performance?.end(.ocr, outcome: .cancelled)
                return .cancelled
            }
            performance?.end(.ocr, outcome: .succeeded)

            guard let selected = selectWord(
                from: words,
                normalizedPoint: normalizedPoint
            ) else {
                return .noWord
            }

            let selectedBox = selected.boundingBox
            let isVertical = selectedBox.height > selectedBox.width * 1.4
            let nearbyText = words.filter { word in
                if isVertical {
                    return abs(word.boundingBox.midX - selectedBox.midX) <= max(selectedBox.width * 0.9, 0.02)
                }
                return abs(word.boundingBox.midY - selectedBox.midY) <= max(selectedBox.height * 0.9, 0.02)
            }.map(\.text).joined()
            let sourceLanguage = LanguageClassificationService.supportedOCRLanguage(
                for: selected.text + nearbyText
            ) ?? LanguageClassificationService.supportedOCRLanguage(for: selected.text)
            let lineWords: [RecognizedWord]
            if isVertical {
                let tolerance = max(selectedBox.width * 0.9, 0.02)
                lineWords = words
                    .filter {
                        abs($0.boundingBox.midX - selectedBox.midX) <= tolerance
                            && Self.contextFragment($0.text, language: sourceLanguage) != nil
                    }
                    .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            } else {
                let tolerance = max(selectedBox.height * 0.9, 0.02)
                lineWords = words
                    .filter {
                        abs($0.boundingBox.midY - selectedBox.midY) <= tolerance
                            && Self.contextFragment($0.text, language: sourceLanguage) != nil
                    }
                    .sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            }
            let contextSentence: String?
            if !lineWords.isEmpty {
                let fragments = lineWords.compactMap {
                    Self.contextFragment($0.text, language: sourceLanguage)
                }
                let rawText = fragments.joined(separator: sourceLanguage == "ja" ? "" : " ")
                let candidate = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                contextSentence = Self.containsOnlyRepeatedSelection(candidate, selected: selected.text)
                    ? nil
                    : candidate
            } else {
                contextSentence = selected.text
            }

            return .word(
                OcrWordCandidate(
                    text: selected.text,
                    contextSentence: contextSentence
                )
            )
        } catch is CancellationError {
            performance?.end(.ocr, outcome: .cancelled)
            return .cancelled
        } catch {
            guard !Task.isCancelled, activeLookupID == lookupID else {
                performance?.end(.ocr, outcome: .cancelled)
                return .cancelled
            }
            performance?.end(.ocr, outcome: .failed)
            return .failed(message: L("Translation failed: \(error.localizedDescription)"))
        }
    }

    private func presentOcrWordCandidate(
        _ result: OcrWordCandidateLoadResult,
        request: SinglePressLookupRequest
    ) async {
        guard !Task.isCancelled, activeLookupID == request.lookupID else { return }

        switch result {
        case .missingScreenRecordingPermission:
            updateOverlay(
                state: .error(L("Enable Screen Recording")),
                anchor: request.mouseLocation
            )

        case .captureFailed:
            updateOverlay(
                state: .error(L("Capture failed")),
                anchor: request.mouseLocation
            )

        case .noWord:
            hideOverlay()

        case .word(let candidate):
            await performResolvedOcrWordLookup(
                word: candidate.text,
                contextSentence: candidate.contextSentence,
                request: request
            )

        case .failed(let message):
            updateOverlay(state: .error(message), anchor: request.mouseLocation)

        case .cancelled:
            return
        }
    }

    func showPreviewWordOverlay(word: String, mouseLocation: CGPoint = CGPoint(x: 600, y: 500)) async {
        isTapKeptOverlayPresented = true
        let request = SinglePressLookupRequest(
            lookupID: UUID(),
            mouseLocation: mouseLocation,
            supportsSelectedText: false,
            selectedTextEnabled: false,
            hasAccessibilityPermission: false
        )
        activeLookupID = request.lookupID
        await performResolvedOcrWordLookup(word: word, request: request)
    }

    private func performResolvedOcrWordLookup(
        word: String,
        contextSentence: String? = nil,
        request: SinglePressLookupRequest
    ) async {
        let lookupID = request.lookupID
        let mouseLocation = request.mouseLocation
        _ = lookupPerformanceContext(for: lookupID)

        guard !Task.isCancelled, activeLookupID == lookupID else { return }

        let trimmedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty else { return }

        let classification = LanguageClassificationService.classify(trimmedWord, context: contextSentence)

        if classification.isJapanese {
            let entries = localDictionaryService.lookup(trimmedWord)
            if !entries.isEmpty {
                await performLocalDictionaryWordLookup(
                    trimmedWord,
                    entries: entries,
                    language: "ja",
                    lookupID: lookupID,
                    mouseLocation: mouseLocation,
                    contextSentence: contextSentence
                )
            } else if settings.translateOCRLineWithWord {
                await performLocalDictionaryWordLookup(
                    trimmedWord,
                    entries: [],
                    language: "ja",
                    lookupID: lookupID,
                    mouseLocation: mouseLocation,
                    contextSentence: contextSentence
                )
            } else {
                hideOverlay()
            }
        } else if classification.script == .simplifiedChinese || classification.script == .traditionalChinese {
            // 1. Search CC-CEDICT first (<0.5ms)
            let zhEntries = localDictionaryService.lookupChinese(trimmedWord)
            if !zhEntries.isEmpty {
                await performLocalDictionaryWordLookup(
                    trimmedWord,
                    entries: zhEntries,
                    language: classification.bcp47Code,
                    lookupID: lookupID,
                    mouseLocation: mouseLocation,
                    contextSentence: contextSentence
                )
            } else if settings.translateOCRLineWithWord {
                await performLocalDictionaryWordLookup(
                    trimmedWord,
                    entries: [],
                    language: classification.bcp47Code,
                    lookupID: lookupID,
                    mouseLocation: mouseLocation,
                    contextSentence: contextSentence
                )
            } else {
                hideOverlay()
            }
        } else if classification.script == .korean {
            // 1. Search KRDICT first (<0.5ms)
            let koEntries = localDictionaryService.lookupKorean(trimmedWord)
            if !koEntries.isEmpty {
                await performLocalDictionaryWordLookup(
                    trimmedWord,
                    entries: koEntries,
                    language: "ko",
                    lookupID: lookupID,
                    mouseLocation: mouseLocation,
                    contextSentence: contextSentence
                )
            } else if settings.translateOCRLineWithWord {
                await performLocalDictionaryWordLookup(
                    trimmedWord,
                    entries: [],
                    language: "ko",
                    lookupID: lookupID,
                    mouseLocation: mouseLocation,
                    contextSentence: contextSentence
                )
            } else {
                hideOverlay()
            }
        } else {
            // Only query the installed Japanese, Chinese, and Korean dictionaries.
            hideOverlay()
        }
    }

    private func performLocalDictionaryWordLookup(
        _ word: String,
        entries: [DictionaryTermResult],
        language: String = "ja",
        lookupID: UUID,
        mouseLocation: CGPoint,
        contextSentence: String? = nil
    ) async {
        guard !Task.isCancelled, activeLookupID == lookupID else { return }

        let initialContent = OverlayContent(
            word: word,
            phonetic: WordOverlayHeaderLayoutPolicy.displayedDictionaryReading(
                reading: entries.first?.reading,
                for: word,
                sourceLanguageIdentifier: language
            ),
            sourceLanguageIdentifier: language,
            dictionaryLookupState: entries.isEmpty ? .noResults : .results(entries),
            contextSentence: contextSentence,
            contextTranslationState: settings.translateOCRLineWithWord && contextSentence != nil
                ? .loading
                : nil
        )
        updateOverlay(state: .result(initialContent), anchor: mouseLocation)

        // Lookup results are transient. Anki is written only from its explicit Add action.

        if settings.playWordPronunciation {
            let speakText = WordOverlayHeaderLayoutPolicy.displayedDictionaryReading(
                reading: entries.first?.reading,
                for: word,
                sourceLanguageIdentifier: language
            ) ?? word
            speechService.speak(
                speakText,
                language: language,
                gender: settings.voiceGender,
            )
        }

        guard settings.translateOCRLineWithWord,
              let contextSentence,
              !contextSentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let languagePair = resolveParagraphLanguagePair(for: contextSentence)
        let translationState = await loadSentenceTranslationState(
            text: contextSentence,
            languagePair: languagePair,
            sourceLanguage: languagePair.sourceLanguage,
            targetLanguage: languagePair.targetLanguage,
            translationBridge: translationBridge
        )
        guard !Task.isCancelled, activeLookupID == lookupID,
              case .result(var content) = overlayState else { return }
        content.contextTranslationState = translationState
        updateOverlay(state: .result(content), anchor: mouseLocation)
    }

    private nonisolated static func contextFragment(_ text: String, language: String?) -> String? {
        let languageCode = language?.lowercased().split(separator: "-").first.map(String.init)
        guard let languageCode else {
            return LanguageClassificationService.supportedOCRLanguage(for: text) == nil ? nil : text
        }

        let punctuationAndNumbers = CharacterSet.punctuationCharacters
            .union(.symbols)
            .union(.decimalDigits)
            .union(.whitespacesAndNewlines)
        let scalars = text.unicodeScalars.compactMap { scalar -> Unicode.Scalar? in
            let value = scalar.value
            let isKana = (0x3040...0x30FF).contains(value) || (0xFF66...0xFF9D).contains(value)
            let isHangul = (0x1100...0x11FF).contains(value)
                || (0x3130...0x318F).contains(value)
                || (0xAC00...0xD7AF).contains(value)
            let isHan = scalar.properties.isIdeographic
            let matchesLanguage: Bool
            switch languageCode {
            case "ja": matchesLanguage = isKana || isHan
            case "zh": matchesLanguage = isHan
            case "ko": matchesLanguage = isHangul || isHan
            default: matchesLanguage = false
            }
            return matchesLanguage || punctuationAndNumbers.contains(scalar) ? scalar : nil
        }
        let fragment = String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard fragment.unicodeScalars.contains(where: { scalar in
            switch languageCode {
            case "ja": return (0x3040...0x30FF).contains(scalar.value) || scalar.properties.isIdeographic
            case "zh": return scalar.properties.isIdeographic
            case "ko":
                return (0x1100...0x11FF).contains(scalar.value)
                    || (0x3130...0x318F).contains(scalar.value)
                    || (0xAC00...0xD7AF).contains(scalar.value)
                    || scalar.properties.isIdeographic
            default: return false
            }
        }) else { return nil }
        return fragment
    }

    private nonisolated static func containsOnlyRepeatedSelection(_ context: String, selected: String) -> Bool {
        func normalized(_ value: String) -> String {
            let dashNormalized = value
                .replacingOccurrences(of: "―", with: "ー")
                .replacingOccurrences(of: "—", with: "ー")
                .replacingOccurrences(of: "ｰ", with: "ー")
            let kanaNormalized = dashNormalized.applyingTransform(.hiraganaToKatakana, reverse: false) ?? dashNormalized
            return String(kanaNormalized.unicodeScalars.filter { scalar in
                scalar.properties.isIdeographic
                    || (0x3040...0x30FF).contains(scalar.value)
                    || (0xFF66...0xFF9D).contains(scalar.value)
                    || (0x1100...0x11FF).contains(scalar.value)
                    || (0x3130...0x318F).contains(scalar.value)
                    || (0xAC00...0xD7AF).contains(scalar.value)
            })
        }

        let line = normalized(context)
        let word = normalized(selected)
        guard !word.isEmpty, line.count > word.count, line.count <= word.count * 4 else { return false }
        return (2...4).contains { count in
            line.count == word.count * count && String(repeating: word, count: count) == line
        }
    }

    private func resolveSinglePressLookupIntent(
        request: SinglePressLookupRequest,
        selectedTextProbeRequest: SelectedTextProbeRequest
    ) async -> SinglePressLookupResolution {
        let mouseLocation = request.mouseLocation
        debugSelectedTextRoute(
            """
            start mouse=\(describe(point: mouseLocation)) \
            selectedTextSupported=\(request.supportsSelectedText) \
            selectedTextEnabled=\(request.selectedTextEnabled) \
            accessibility=\(request.hasAccessibilityPermission) \
            likelySandboxed=\(isLikelySandboxedRuntime()) \
            bundlePath=\(Bundle.main.bundlePath) \
            home=\(NSHomeDirectory()) \
            tmp=\(FileManager.default.temporaryDirectory.path)
            """
        )

        guard request.supportsSelectedText else {
            debugSelectedTextRoute("decision=ocrWord reason=unsupportedChannel")
            return SinglePressLookupResolution(intent: .ocrWord)
        }

        guard request.selectedTextEnabled else {
            debugSelectedTextRoute("decision=ocrWord reason=featureDisabled")
            return SinglePressLookupResolution(intent: .ocrWord)
        }

        guard request.hasAccessibilityPermission else {
            debugSelectedTextRoute("decision=ocrWord reason=missingAccessibility")
            return SinglePressLookupResolution(intent: .ocrWord)
        }

        let selectionSnapshot = await selectedTextService.currentSelectionSnapshot(
            request: selectedTextProbeRequest
        )
        var selectionRejectionReason: String?
        if let selectionSnapshot {
            debugSelectedTextRoute(
                "snapshot text=\"\(truncate(selectionSnapshot.text))\" bounds=\(selectionSnapshot.bounds.map { describe(rect: $0) } ?? "nil") sourceApp=\(selectionSnapshot.sourceAppIdentifier ?? "nil")"
            )
            selectionRejectionReason = SinglePressLookupRouter.selectedTextRejectionReason(
                mouseLocation: mouseLocation,
                selectionSnapshot: selectionSnapshot
            )
            if let rejectionReason = selectionRejectionReason {
                debugSelectedTextRoute("snapshotRejected reason=\(rejectionReason)")
            }
        } else {
            debugSelectedTextRoute("snapshot=nil")
        }

        let intent = SinglePressLookupRouter.resolve(
            mouseLocation: mouseLocation,
            isSelectedTextTranslationSupported: request.supportsSelectedText,
            isSelectedTextTranslationEnabled: true,
            hasAccessibilityPermission: true,
            selectionSnapshot: selectionSnapshot
        )
        switch intent {
        case .selectedTextSentence:
            debugSelectedTextRoute("decision=selectedTextSentence")
        case .ocrWord:
            debugSelectedTextRoute("decision=ocrWord")
        }
        return SinglePressLookupResolution(intent: intent)
    }

    private func performSelectedTextSentenceLookup(
        snapshot: SelectedTextSnapshot,
        lookupID: UUID,
        mouseLocation: CGPoint
    ) async {
        guard LanguageClassificationService.supportedOCRLanguage(for: snapshot.text) != nil else {
            hideOverlay()
            return
        }
        activeParagraphRect = nil
        overlayPreferredWidth = nil

        let languagePair = resolveParagraphLanguagePair(for: snapshot.text)
        let sourceLanguage = languagePair.sourceLanguage
        let targetLanguage = languagePair.targetLanguage

        if settings.playSentencePronunciation {
            let languageCode = sourceLanguage.languageCode?.identifier
            speechService.speak(
                snapshot.text,
                language: languageCode,
            )
        }
        let initialContent = ParagraphOverlayContent(
            originalText: snapshot.text,
            translationState: .loading,
            bodyFontSize: 14,
            useFixedFontSize: true
        )
        updateOverlay(state: .paragraphResult(initialContent), anchor: mouseLocation)


        let translationState = await loadSentenceTranslationState(
            text: snapshot.text,
            languagePair: languagePair,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            translationBridge: translationBridge
        )

        applyParagraphTranslationState(
            translationState,
            lookupID: lookupID,
            anchor: mouseLocation
        )
    }

    private func applyParagraphTranslationState(
        _ state: ParagraphOverlayTranslationState,
        lookupID: UUID,
        anchor: CGPoint
    ) {
        updateParagraphOverlayContent(for: lookupID, anchor: anchor) { content in
            content.translationState = state
            content.isRetranslating = false
        }
    }

    func updateParagraphOriginalText(_ text: String) {
        updateParagraphOverlayContentIgnoringLookup(anchor: overlayAnchor) { content in
            content.originalText = text
        }
    }

    func submitParagraphOriginalText() {
        guard case .paragraphResult(let content) = overlayState,
              let originalText = content.originalText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !originalText.isEmpty else {
            return
        }

        let languagePair = resolveParagraphLanguagePair(for: originalText)

        translateCurrentParagraphOriginal(
            originalText: originalText,
            languagePair: languagePair
        )
    }

    private func translateCurrentParagraphOriginal(
        originalText: String,
        languagePair: LookupLanguagePair
    ) {
        let originalText = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !originalText.isEmpty,
              LanguageClassificationService.supportedOCRLanguage(for: originalText) != nil else { return }

        paragraphTranslationTask?.cancel()
        let lookupID = UUID()
        activeLookupID = lookupID
        let anchor = overlayAnchor
        updateParagraphOverlayContentIgnoringLookup(anchor: anchor) { content in
            content.isRetranslating = true
            content.originalText = originalText
        }

        paragraphTranslationTask = Task { [weak self] in
            guard let self else { return }

            let translationState = await self.loadSentenceTranslationState(
                text: originalText,
                languagePair: languagePair,
                sourceLanguage: languagePair.sourceLanguage,
                targetLanguage: languagePair.targetLanguage,
                translationBridge: self.translationBridge
            )

            self.applyParagraphTranslationState(
                translationState,
                lookupID: lookupID,
                anchor: anchor
            )
        }
    }

    private func loadSentenceTranslationState(
        text: String,
        languagePair: LookupLanguagePair,
        sourceLanguage: Locale.Language,
        targetLanguage: Locale.Language,
        translationBridge: TranslationBridge
    ) async -> ParagraphOverlayTranslationState {
        let sourceText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty,
              LanguageClassificationService.supportedOCRLanguage(for: sourceText) != nil else {
            return .failed("No text selected")
        }

        if languagePair.isSameLanguage {
            return .ready(sourceText)
        }

        if #available(macOS 15.0, *) {
            let status = await languageAvailabilityStatus(for: languagePair)
            guard status == .installed else {
                return .failed(message(for: status))
            }

            do {
                let translatedText = try await translationBridge.translate(
                    text: sourceText,
                    source: sourceLanguage,
                    target: targetLanguage
                ).trimmingCharacters(in: .whitespacesAndNewlines)

                return translatedText.isEmpty ? .failed("No translation result") : .ready(translatedText)
            } catch TranslationError.timeout {
                return .failed("Translation timeout. Please try again.")
            } catch {
                return .failed("Translation failed: \(error.localizedDescription)")
            }
        } else {
            return .failed("Translation requires macOS 15")
        }
    }

    private func updateParagraphOverlayContent(
        for lookupID: UUID,
        anchor: CGPoint,
        mutate: (inout ParagraphOverlayContent) -> Void
    ) {
        guard activeLookupID == lookupID,
              case .paragraphResult(var content) = overlayState else {
            return
        }

        let previousContent = content
        mutate(&content)
        guard content != previousContent else { return }
        updateOverlay(state: .paragraphResult(content), anchor: anchor)
    }

    private func updateParagraphOverlayContentIgnoringLookup(
        anchor: CGPoint,
        mutate: (inout ParagraphOverlayContent) -> Void
    ) {
        guard case .paragraphResult(var content) = overlayState else {
            return
        }

        let previousContent = content
        mutate(&content)
        guard content != previousContent else { return }
        updateOverlay(state: .paragraphResult(content), anchor: anchor)
    }

    func updateOverlay(state: OverlayState, anchor: CGPoint? = nil) {
        guard isHotkeyActive
                || isListening
                || isParagraphOverlayPresented
                || isTapKeptOverlayPresented
                || isScreenTranslationModeActive else { return }

        if let anchor {
            setOverlayAnchor(anchor)
        }

        let wasWindowVisible = overlayWindowController.isVisible

        switch state {
        case .error(let message):
            sendNotification(title: "KakuTra", body: message)
        case .idle:
            break
        case .paragraphLoading, .paragraphResult:
            publishOverlayStateIfNeeded(state, wasWindowVisible: wasWindowVisible)
            if overlayWindowController.isVisible {
                refreshParagraphOverlayLayoutImmediately()
            } else {
                showOverlayWindowForActiveLookup(makeKey: isParagraphOverlayPresented)
            }
            overlayWindowController.setInteractive(true)
        case .result:
            publishOverlayStateIfNeeded(state, wasWindowVisible: wasWindowVisible)
            if overlayWindowController.isVisible {
                scheduleOverlayLayoutRefresh()
            } else {
                showOverlayWindowForActiveLookup(makeKey: isParagraphOverlayPresented)
            }
            // Let AppKit receive hover events over the word card so SwiftUI's
            // native .help tooltips can appear. The panel sits away from the
            // cursor, and mouse tracking makes it transparent again outside it.
            overlayWindowController.setInteractive(true)
        default:
            publishOverlayStateIfNeeded(state, wasWindowVisible: wasWindowVisible)
            if overlayWindowController.isVisible {
                scheduleOverlayLayoutRefresh()
            } else {
                showOverlayWindowForActiveLookup(makeKey: isParagraphOverlayPresented)
            }
        }

        syncOverlayDismissalMonitoring()
    }

    private func publishOverlayStateIfNeeded(
        _ state: OverlayState,
        wasWindowVisible: Bool
    ) {
        let decision = OverlayStatePublicationDecision.make(
            isStateChanged: overlayState != state,
            wasWindowVisible: wasWindowVisible
        )
        if decision.shouldUpdateState {
            overlayState = state
        }

        guard let trace = activeLookupTrace else { return }
        lookupPerformanceReporter.mark(.overlayStatePublished, trace: trace)
        if decision.shouldEndFirstPresentation {
            lookupPerformanceReporter.endFirstPresentation(
                .overlayStatePublished,
                trace: trace,
                outcome: .succeeded
            )
        }
    }

    private func showOverlayWindowForActiveLookup(makeKey: Bool) {
        let trace = activeLookupTrace
        overlayWindowController.show(
            at: overlayAnchor,
            makeKey: makeKey,
            onOrderedFront: { [lookupPerformanceReporter] in
                guard let trace else { return }
                lookupPerformanceReporter.mark(.panelPresentation, trace: trace)
            }
        )
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func bindSettings() {
        settings.$singleKey
            .sink { [weak self] singleKey in
                self?.hotkeyManager.start(singleKey: singleKey)
            }
            .store(in: &cancellables)

        settings.$launchAtLogin
            .sink { value in
                LoginItemManager.setEnabled(value)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            settings.$sourceLanguage,
            settings.$targetLanguage
        )
        .sink { [weak self] _, _ in
            self?.handleTranslationSettingsChanged()
        }
        .store(in: &cancellables)

        permissions.$status
            .sink { [weak self] status in
                if status.screenRecording {
                    self?.restartHotkey()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.restartHotkey()
            }
            .store(in: &cancellables)

        let workspaceNotifications = NSWorkspace.shared.notificationCenter

        workspaceNotifications.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] notification in
                self?.handleApplicationActivation(notification)
            }
            .store(in: &cancellables)

        workspaceNotifications.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in
                self?.handleActiveSpaceChange()
            }
            .store(in: &cancellables)

        workspaceNotifications.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                self?.prepareForSystemSleep()
            }
            .store(in: &cancellables)

        workspaceNotifications.publisher(for: NSWorkspace.screensDidSleepNotification)
            .sink { [weak self] _ in
                self?.prepareForSystemSleep()
            }
            .store(in: &cancellables)

        workspaceNotifications.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                self?.scheduleSystemWakeRecovery()
            }
            .store(in: &cancellables)

        workspaceNotifications.publisher(for: NSWorkspace.screensDidWakeNotification)
            .sink { [weak self] _ in
                self?.scheduleSystemWakeRecovery()
            }
            .store(in: &cancellables)

        workspaceNotifications.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.scheduleSystemWakeRecovery()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.handleScreenConfigurationChange()
            }
            .store(in: &cancellables)
    }

    private func handleActiveSpaceChange() {
        captureService.invalidateCache()

        guard isHotkeyActive || isParagraphOverlayPresented || isTapKeptOverlayPresented else {
            return
        }

        // Reassert the all-Spaces panel after Mission Control changes the
        // active Space. The next OCR result will then be ordered in the new
        // Space instead of being treated as already visible elsewhere.
        overlayWindowController.reassertForActiveSpace()
    }

    private func handleApplicationActivation(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else {
            return
        }

        let shouldDismiss = PersistentOverlayApplicationActivationPolicy.shouldDismiss(
            isPersistentOverlayPresented: isPersistentOverlayPresented,
            sourceApplicationProcessIdentifier: persistentOverlaySourceApplicationProcessIdentifier,
            activatedApplicationProcessIdentifier: application.processIdentifier,
            ownApplicationProcessIdentifier: ProcessInfo.processInfo.processIdentifier
        )
        guard shouldDismiss else { return }
        dismissOverlay()
    }

    private func prepareForSystemSleep() {
        captureService.invalidateCache()
        stopScreenTranslationMode()
        isHotkeyActive = false
        isListening = false
        hotkeyManager.resetState()
        stopMouseTracking()
        cancelActiveLookupWork()
        hideOverlay()
    }

    private func scheduleSystemWakeRecovery() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.recoverAfterSystemWake()
        }
    }

    private func recoverAfterSystemWake() {
        isHotkeyActive = false
        isListening = false
        hotkeyManager.resetState()
        stopMouseTracking()
        cancelActiveLookupWork()
        hideOverlay()
        captureService.invalidateCache()
        restartHotkey()
        permissions.refreshStatus()
    }

    private func handleScreenConfigurationChange() {
        captureService.invalidateCache()
        if isScreenTranslationModeActive {
            screenTranslationObservations.removeAll()
            screenTranslationProtectedTextRects.removeAll()
            screenTranslationLastFrameFingerprint = nil
            screenTranslationLastFrameDisplayID = nil
            screenTranslationUnchangedFrameCount = 0
            screenTranslationLastOCRAt = nil
            screenTranslationTracker.reset()
            screenTranslationDisplay = nil
            screenTranslationLastSuccessfulFrameAt = nil
            screenTranslationOverlayWindowController.hide()
            refreshFullScreenTranslation()
            return
        }
        guard isHotkeyActive || isParagraphOverlayPresented else { return }
        cancelActiveLookupWork()
        hideOverlay()
    }

    private func restartHotkey() {
        guard !isHotkeyActive else { return }
        hotkeyManager.start(singleKey: settings.singleKey)
    }

    private func handleTranslationSettingsChanged() {
        cancelActiveLookupWork()
        lastAvailabilityKey = nil
        cachedLanguageStatuses.removeAll()

        if overlayState != .idle {
            hideOverlay()
        }

    }

    private func resolveLookupLanguagePair(for observedText: String) -> LookupLanguagePair {
        let detectedSource = LanguageClassificationService.supportedOCRLanguage(for: observedText) ?? settings.sourceLanguage
        return LookupLanguagePair.fixed(
            sourceIdentifier: detectedSource,
            targetIdentifier: "en"
        )
    }

    private func resolveParagraphLanguagePair(for text: String) -> LookupLanguagePair {
        resolveLookupLanguagePair(for: text)
    }

    func requiredLanguagePairsForCurrentSettings() -> [LookupLanguagePair] {
        ["ja", "zh-Hans", "ko"].map {
            LookupLanguagePair.fixed(sourceIdentifier: $0, targetIdentifier: "en")
        }
    }

    private func languageAvailabilityStatus(
        for pair: LookupLanguagePair,
        useCache: Bool = true
    ) async -> CachedLanguageAvailabilityStatus {
        if pair.isSameLanguage {
            cachedLanguageStatuses[pair.key] = .installed
            return .installed
        }

        if useCache, let cached = cachedLanguageStatuses[pair.key] {
            return cached
        }

        let status: CachedLanguageAvailabilityStatus
        if #available(macOS 15.0, *) {
            status = await refreshLanguageAvailabilityStatus(for: pair)
        } else {
            status = .unsupported
        }

        cachedLanguageStatuses[pair.key] = status
        return status
    }

    @available(macOS 15.0, *)
    func refreshLanguageAvailabilityStatus(
        from sourceIdentifier: String,
        to targetIdentifier: String,
        showLoading: Bool = false
    ) async -> LanguageAvailability.Status {
        let pair = LookupLanguagePair.fixed(
            sourceIdentifier: sourceIdentifier,
            targetIdentifier: targetIdentifier
        )
        let status = await refreshLanguageAvailabilityStatus(
            for: pair,
            showLoading: showLoading
        )
        return status.translationStatus
    }

    @available(macOS 15.0, *)
    private func refreshedLanguageAvailabilityStatuses(
        for pairs: [LookupLanguagePair],
        retrySupportedStatuses: Bool
    ) async -> [String: CachedLanguageAvailabilityStatus] {
        var statusesByKey: [String: CachedLanguageAvailabilityStatus] = [:]

        for pair in pairs {
            statusesByKey[pair.key] = await refreshLanguageAvailabilityStatus(for: pair)
        }

        guard retrySupportedStatuses else {
            return statusesByKey
        }

        let supportedPairs = pairs.filter { statusesByKey[$0.key] == .supported }
        guard !supportedPairs.isEmpty else {
            return statusesByKey
        }

        try? await Task.sleep(nanoseconds: 1_000_000_000)

        for pair in supportedPairs {
            statusesByKey[pair.key] = await refreshLanguageAvailabilityStatus(for: pair)
        }

        return statusesByKey
    }

    @available(macOS 15.0, *)
    private func refreshLanguageAvailabilityStatus(
        for pair: LookupLanguagePair,
        showLoading: Bool = false
    ) async -> CachedLanguageAvailabilityStatus {
        if pair.isSameLanguage {
            cachedLanguageStatuses[pair.key] = .installed
            return .installed
        }

        let status: CachedLanguageAvailabilityStatus
        if let manager = languagePackManager {
            let systemStatus: LanguageAvailability.Status
            if showLoading {
                systemStatus = await manager.checkLanguagePair(
                    from: pair.sourceIdentifier,
                    to: pair.targetIdentifier
                )
            } else {
                systemStatus = await manager.checkLanguagePairQuiet(
                    from: pair.sourceIdentifier,
                    to: pair.targetIdentifier
                )
            }
            status = CachedLanguageAvailabilityStatus(systemStatus)
        } else {
            let availability = LanguageAvailability()
            let systemStatus = await availability.status(from: pair.sourceLanguage, to: pair.targetLanguage)
            status = CachedLanguageAvailabilityStatus(systemStatus)
        }

        cachedLanguageStatuses[pair.key] = status
        return status
    }

    @available(macOS 15.0, *)
    private func syncCachedLanguageStatuses(_ statuses: [String: LanguageAvailability.Status]) {
        for (key, status) in statuses {
            cachedLanguageStatuses[key] = CachedLanguageAvailabilityStatus(status)
        }
    }

    private func message(for status: CachedLanguageAvailabilityStatus) -> String {
        switch status {
        case .installed:
            return ""
        case .supported:
            return L("Language pack required. Please download in System Settings > General > Language & Region > Translation.")
        case .unsupported:
            return L("Translation not supported for this language pair.")
        }
    }

    private func normalizedCursorPoint(_ mouseLocation: CGPoint, in rect: CGRect) -> CGPoint {
        let x = (mouseLocation.x - rect.minX) / rect.width
        let y = (mouseLocation.y - rect.minY) / rect.height
        return CGPoint(x: x, y: y)
    }

    private func screenRect(for normalizedRect: CGRect, in captureRect: CGRect) -> CGRect {
        CGRect(
            x: captureRect.minX + normalizedRect.minX * captureRect.width,
            y: captureRect.minY + normalizedRect.minY * captureRect.height,
            width: normalizedRect.width * captureRect.width,
            height: normalizedRect.height * captureRect.height
        )
    }

    private func estimatedDisplayFontSize(from lines: [RecognizedTextLine], in captureRect: CGRect) -> CGFloat {
        guard !lines.isEmpty else { return 14 }
        let averageHeight = lines.map(\.boundingBox.height).reduce(0, +) / CGFloat(lines.count)
        return max(11, averageHeight * captureRect.height * 0.75)
    }

    private func selectWord(
        from words: [RecognizedWord],
        normalizedPoint: CGPoint
    ) -> RecognizedWord? {
        OCRService.selectWord(from: words, normalizedPoint: normalizedPoint)
    }

    private func lookupPerformanceContext(for lookupID: UUID) -> LookupPerformanceContext? {
        guard let trace = activeLookupTrace, trace.lookupID == lookupID else { return nil }
        return LookupPerformanceContext(reporter: lookupPerformanceReporter, trace: trace)
    }

    private func cancelActiveLookupWork(
        outcome: LookupPerformanceOutcome = .cancelled
    ) {
        if let trace = activeLookupTrace {
            lookupPerformanceReporter.finishLookup(trace, outcome: outcome)
            activeLookupTrace = nil
        }
        lookupTask?.cancel()
        lookupTask = nil
        activeLookupID = nil
        speechService.stopSpeaking()
        translationBridge.cancelAllPendingRequests()
        cancelPendingOverlayLayoutRefresh()
    }

    private func hideOverlay() {
        activeLookupMode = .word
        isParagraphOverlayPinned = false
        persistentOverlaySourceApplicationProcessIdentifier = nil
        isTapKeptOverlayPresented = false
        tapKeptOverlayReleaseLocation = nil
        stopOverlayEscapeMonitoring()
        cancelPendingOverlayLayoutRefresh()
        speechService.stopSpeaking()
        cachedLanguageStatuses.removeAll(keepingCapacity: false)
        if overlayState != .idle {
            overlayState = .idle
        }
        ankiConfirmationDraft = nil
        activeParagraphRect = nil
        overlayPreferredWidth = nil
        overlayWindowController.setInteractive(false)
        overlayWindowController.hide()
    }

    @available(macOS 15.0, *)
    private func ensureTranslationService() {
        guard !translationServiceInitialized else { return }
        translationServiceInitialized = true
        createTranslationServiceWindowIfNeeded()
        warmupTranslationService()
    }

    @available(macOS 15.0, *)
    private func createTranslationServiceWindowIfNeeded() {
        guard TranslationServiceWindowHolder.shared.window == nil else { return }

        let translationView = TranslationBridgeView(bridge: translationBridge)
        let hostingView = NSHostingView(rootView: translationView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 1, height: 1)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.setIsVisible(false)
        CaptureExclusionRegistry.shared.register(window)

        TranslationServiceWindowHolder.shared.window = window
    }

    @available(macOS 15.0, *)
    private func warmupTranslationService() {
        Task { @MainActor in
            let sourceLanguage = Locale.Language(identifier: settings.sourceLanguage)
            let targetLanguage = Locale.Language(identifier: settings.targetLanguage)

            _ = try? await translationBridge.translate(
                text: "hello",
                source: sourceLanguage,
                target: targetLanguage,
                timeout: 10.0
            )
        }
    }

    private func setOverlayAnchor(_ anchor: CGPoint) {
        guard overlayAnchor != anchor else { return }
        overlayAnchor = anchor
    }

    private func scheduleOverlayLayoutRefresh() {
        guard overlayWindowController.isVisible else { return }

        cancelPendingOverlayLayoutRefresh()

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.overlayLayoutRefreshWorkItem = nil
                guard let self else { return }
                guard self.overlayWindowController.isVisible else { return }
                self.refreshParagraphOverlayLayout(animated: false)
            }
        }

        overlayLayoutRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + overlayLayoutRefreshInterval, execute: workItem)
    }

    private func cancelPendingOverlayLayoutRefresh() {
        overlayLayoutRefreshWorkItem?.cancel()
        overlayLayoutRefreshWorkItem = nil
    }

    private func refreshParagraphOverlayLayoutImmediately() {
        guard overlayWindowController.isVisible else { return }

        cancelPendingOverlayLayoutRefresh()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.overlayWindowController.isVisible else { return }
            self.refreshParagraphOverlayLayout(animated: true)
        }
    }

    private func refreshParagraphOverlayLayout(animated: Bool) {
        if overlayWindowController.isManualParagraphPositioningActive {
            return
        }

        if overlayWindowController.hasManualParagraphPosition {
            overlayWindowController.refreshLayoutIfNeeded(at: overlayAnchor)
            return
        }

        if let sentenceRect = activeParagraphRect {
            overlayWindowController.alignToSentenceRect(sentenceRect, animated: animated)
        } else {
            overlayWindowController.refreshLayoutIfNeeded(at: overlayAnchor)
        }
    }

    private var isParagraphOverlayPresented: Bool {
        switch overlayState {
        case .paragraphLoading, .paragraphResult:
            return true
        default:
            return false
        }
    }

    private var isSentenceTranslationPresented: Bool {
        isParagraphOverlayPresented
    }

    private var isPersistentOverlayPresented: Bool {
        (isSentenceTranslationPresented && isParagraphOverlayPinned) || isTapKeptOverlayPresented
    }

    private func armPersistentOverlayApplicationMonitoring() {
        persistentOverlaySourceApplicationProcessIdentifier =
            NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    private func syncOverlayDismissalMonitoring() {
        if isScreenTranslationModeActive || OverlayEscapeDismissalPolicy.shouldMonitor(
            isParagraphOverlayPresented: isSentenceTranslationPresented,
            isTapKeptOverlayPresented: isTapKeptOverlayPresented
        ) {
            startOverlayEscapeMonitoringIfNeeded()
        } else {
            stopOverlayEscapeMonitoring()
        }

        if isSentenceTranslationPresented && isParagraphOverlayPinned {
            startParagraphOutsideClickMonitoringIfNeeded()
        } else {
            stopParagraphOutsideClickMonitoring()
        }
    }

    private func startOverlayEscapeMonitoringIfNeeded() {
        guard globalOverlayKeyMonitor == nil, localOverlayKeyMonitor == nil else { return }

        globalOverlayKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                _ = self?.handleOverlayEscapeKey(event)
            }
        }

        localOverlayKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let handled = MainActor.assumeIsolated {
                self.handleOverlayEscapeKey(event)
            }
            return handled ? nil : event
        }
    }

    private func stopOverlayEscapeMonitoring() {
        if let monitor = globalOverlayKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalOverlayKeyMonitor = nil
        }

        if let monitor = localOverlayKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localOverlayKeyMonitor = nil
        }

        stopParagraphOutsideClickMonitoring()
    }

    @discardableResult
    private func handleOverlayEscapeKey(_ event: NSEvent) -> Bool {
        if isScreenTranslationModeActive, event.keyCode == 53 {
            stopScreenTranslationMode()
            return true
        }
        guard OverlayEscapeDismissalPolicy.shouldDismiss(
            keyCode: event.keyCode,
            isParagraphOverlayPresented: isSentenceTranslationPresented,
            isTapKeptOverlayPresented: isTapKeptOverlayPresented
        ) else { return false }

        dismissOverlay()
        return true
    }

    private func startParagraphOutsideClickMonitoringIfNeeded() {
        guard globalParagraphMouseMonitor == nil, localParagraphMouseMonitor == nil else { return }
        let eventMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        globalParagraphMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] _ in
            Task { @MainActor in
                _ = self?.handleParagraphOutsideMouseDown()
            }
        }

        localParagraphMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            guard let self else { return event }
            let handled = MainActor.assumeIsolated {
                self.handleParagraphOutsideMouseDown()
            }
            return handled ? nil : event
        }
    }

    private func stopParagraphOutsideClickMonitoring() {
        if let monitor = globalParagraphMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalParagraphMouseMonitor = nil
        }

        if let monitor = localParagraphMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localParagraphMouseMonitor = nil
        }
    }

    @discardableResult
    private func handleParagraphOutsideMouseDown() -> Bool {
        let shouldDismiss = ParagraphOutsideClickDismissalPolicy.shouldDismiss(
            mouseLocation: NSEvent.mouseLocation,
            isSentenceTranslationPresented: isSentenceTranslationPresented,
            isParagraphOverlayPinned: isParagraphOverlayPinned,
            protectedFrames: [
                overlayWindowController.visibleFrame,
                activeParagraphRect,
            ]
        )

        guard shouldDismiss else { return false }
        dismissOverlay()
        return true
    }

    private func debugSelectedTextRoute(_ message: @autoclosure () -> String) {
#if DEBUG
        print("[SelectedTextRoute] \(message())")
#endif
    }

    private func isLikelySandboxedRuntime() -> Bool {
        NSHomeDirectory().contains("/Library/Containers/")
    }

    private func describe(point: CGPoint) -> String {
        "(\(format(point.x)), \(format(point.y)))"
    }

    private func describe(rect: CGRect) -> String {
        "x=\(format(rect.origin.x)) y=\(format(rect.origin.y)) w=\(format(rect.width)) h=\(format(rect.height))"
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }

    private func truncate(_ text: String, limit: Int = 120) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "..."
    }
}
