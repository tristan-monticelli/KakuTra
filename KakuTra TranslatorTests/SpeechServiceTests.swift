import XCTest
@testable import KakuTra

@MainActor
final class SpeechServiceTests: XCTestCase {
    func testSpeakUsesAppleVoiceAndTracksPlayback() {
        let output = SpeechAudioOutputSpy()
        let service = SpeechService(output: output)
        let requestID = UUID()

        service.speak("こんにちは", language: "ja", gender: .system, requestID: requestID)

        XCTAssertEqual(output.text, "こんにちは")
        XCTAssertEqual(output.language, "ja")
        XCTAssertEqual(output.gender, .system)
        XCTAssertEqual(service.playbackState, .playing(requestID: requestID))
    }

    func testStopSpeakingClearsPlaybackState() {
        let output = SpeechAudioOutputSpy()
        let service = SpeechService(output: output)

        service.speak("hello", language: "en")
        service.stopSpeaking()

        XCTAssertEqual(service.playbackState, .idle)
        XCTAssertEqual(output.stopCount, 2)
    }
}

@MainActor
private final class SpeechAudioOutputSpy: SpeechAudioOutput {
    private(set) var text: String?
    private(set) var language: String?
    private(set) var gender: VoiceGenderPreference?
    private(set) var stopCount = 0

    func stop() {
        stopCount += 1
    }

    func playApple(text: String, language: String?, gender: VoiceGenderPreference) {
        self.text = text
        self.language = language
        self.gender = gender
    }
}
