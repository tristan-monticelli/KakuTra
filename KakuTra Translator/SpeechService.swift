import AVFoundation
import Combine
import Foundation

@MainActor
protocol SpeechAudioOutput: AnyObject {
    func stop()
    func playApple(text: String, language: String?, gender: VoiceGenderPreference)
}

@MainActor
protocol SpeechAudioStartObserving: AnyObject {
    func setAppleDidStartHandler(_ handler: @escaping @MainActor () -> Void)
}

@MainActor
protocol SpeechAudioLifecycleObserving: AnyObject {
    func setLifecycleHandlers(
        didStart: @escaping @MainActor () -> Void,
        didFinish: @escaping @MainActor () -> Void,
        didFail: @escaping @MainActor () -> Void
    )
}

@MainActor
final class AVFoundationSpeechAudioOutput: NSObject, SpeechAudioOutput, SpeechAudioStartObserving, SpeechAudioLifecycleObserving {
    private let synthesizer = AVSpeechSynthesizer()
    private var nextAppleDidStartHandler: (@MainActor () -> Void)?
    private var appleDidStartHandlers: [ObjectIdentifier: @MainActor () -> Void] = [:]
    private var lifecycleDidStart: (@MainActor () -> Void)?
    private var lifecycleDidFinish: (@MainActor () -> Void)?
    private var lifecycleDidFail: (@MainActor () -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        appleDidStartHandlers.removeAll()
        nextAppleDidStartHandler = nil
        lifecycleDidStart = nil
        lifecycleDidFinish = nil
        lifecycleDidFail = nil
    }

    func setAppleDidStartHandler(_ handler: @escaping @MainActor () -> Void) {
        nextAppleDidStartHandler = handler
    }

    func setLifecycleHandlers(
        didStart: @escaping @MainActor () -> Void,
        didFinish: @escaping @MainActor () -> Void,
        didFail: @escaping @MainActor () -> Void
    ) {
        lifecycleDidStart = didStart
        lifecycleDidFinish = didFinish
        lifecycleDidFail = didFail
    }

    func playApple(text: String, language: String?, gender: VoiceGenderPreference) {
        let utterance = AVSpeechUtterance(string: text)
        let resolvedLanguage: String = {
            if let language, !language.isEmpty { return language }
            return LanguageClassificationService.classify(text).bcp47Code
        }()
        utterance.voice = Self.resolveAppleVoice(for: resolvedLanguage, gender: gender)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        if let handler = nextAppleDidStartHandler {
            appleDidStartHandlers[ObjectIdentifier(utterance)] = handler
        }
        nextAppleDidStartHandler = nil
        synthesizer.speak(utterance)
    }

    static func resolveAppleVoice(for languageCode: String, gender: VoiceGenderPreference) -> AVSpeechSynthesisVoice? {
        let normalized = languageCode.replacingOccurrences(of: "_", with: "-").lowercased()
        let baseLanguage = normalized.split(separator: "-").first.map(String.init) ?? normalized
        let matchingVoices = AVSpeechSynthesisVoice.speechVoices().filter { voice in
            let voiceLanguage = voice.language.lowercased()
            return voiceLanguage == normalized
                || voiceLanguage.hasPrefix("\(baseLanguage)-")
                || voiceLanguage == baseLanguage
        }

        switch gender {
        case .female:
            if let voice = matchingVoices.first(where: { $0.gender == .female }) { return voice }
        case .male:
            if let voice = matchingVoices.first(where: { $0.gender == .male }) { return voice }
        case .system:
            break
        }

        return matchingVoices.first ?? AVSpeechSynthesisVoice(language: languageCode)
    }

    private func handleAppleDidStart(identifier: ObjectIdentifier) {
        let handler = appleDidStartHandlers.removeValue(forKey: identifier)
        handler?()
        lifecycleDidStart?()
    }
}

extension AVFoundationSpeechAudioOutput: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.handleAppleDidStart(identifier: identifier)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.lifecycleDidFinish?()
        }
    }
}

enum SpeechPlaybackState: Equatable {
    case idle
    case loading(requestID: UUID)
    case playing(requestID: UUID)
    case failed(requestID: UUID)

    var requestID: UUID? {
        switch self {
        case .idle:
            return nil
        case .loading(let requestID), .playing(let requestID), .failed(let requestID):
            return requestID
        }
    }
}

@MainActor
final class SpeechService: ObservableObject {
    private let output: any SpeechAudioOutput
    private var requestGeneration: UInt64 = 0
    private var activeRequestID: UUID?

    @Published private(set) var playbackState: SpeechPlaybackState = .idle

    convenience init() {
        self.init(output: AVFoundationSpeechAudioOutput())
    }

    init(output: any SpeechAudioOutput) {
        self.output = output
    }

    func speak(
        _ text: String,
        language: String?,
        gender: VoiceGenderPreference = .female,
        performance: LookupPerformanceContext? = nil,
        requestID: UUID = UUID()
    ) {
        requestGeneration &+= 1
        let generation = requestGeneration
        output.stop()
        activeRequestID = requestID
        playbackState = .loading(requestID: requestID)
        performance?.begin(.ttsStart)

        if let observer = output as? any SpeechAudioStartObserving {
            observer.setAppleDidStartHandler { [weak self] in
                guard let self, self.isCurrent(generation, requestID: requestID) else { return }
                performance?.end(.ttsStart, outcome: .succeeded)
                performance?.markAudioStart(.appleDidStart)
            }
        }

        if let observer = output as? any SpeechAudioLifecycleObserving {
            observer.setLifecycleHandlers(
                didStart: { [weak self] in
                    guard let self, self.isCurrent(generation, requestID: requestID) else { return }
                    self.playbackState = .playing(requestID: requestID)
                },
                didFinish: { [weak self] in
                    guard let self, self.isCurrent(generation, requestID: requestID) else { return }
                    self.activeRequestID = nil
                    self.playbackState = .idle
                },
                didFail: { [weak self] in
                    guard let self, self.isCurrent(generation, requestID: requestID) else { return }
                    self.playbackState = .failed(requestID: requestID)
                }
            )
        }

        output.playApple(text: text, language: language, gender: gender)
        if !(output is any SpeechAudioLifecycleObserving) {
            playbackState = .playing(requestID: requestID)
        }
        if !(output is any SpeechAudioStartObserving) {
            performance?.end(.ttsStart, outcome: .succeeded)
            performance?.markAudioStart(.appleSubmissionProxy)
        }
    }

    func stopSpeaking() {
        requestGeneration &+= 1
        output.stop()
        activeRequestID = nil
        playbackState = .idle
    }

    private func isCurrent(_ generation: UInt64, requestID: UUID) -> Bool {
        requestGeneration == generation && activeRequestID == requestID
    }
}
