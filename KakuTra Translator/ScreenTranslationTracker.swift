import CoreGraphics
import Vision

/// Tracks already recognized text blocks between OCR refreshes. Vision's sequence
/// tracker updates their geometry; it does not recognize or translate text.
final class ScreenTranslationTracker {
    private let handler = VNSequenceRequestHandler()
    private let queue = DispatchQueue(label: "KakuTra.ScreenTranslationTracker", qos: .userInitiated)
    private var requests: [String: VNTrackObjectRequest] = [:]

    func reset() {
        queue.sync { requests.removeAll() }
    }

    func seed(_ observations: [ScreenTranslationObservation], captureRect: CGRect) {
        queue.sync {
            requests.removeAll(keepingCapacity: true)
            // Keep tracking bounded; Vision's revision 2 tracker uses its fast default.
            for observation in observations.prefix(64) {
                let localRect = CGRect(
                    x: (observation.rect.minX - captureRect.minX) / captureRect.width,
                    y: (observation.rect.minY - captureRect.minY) / captureRect.height,
                    width: observation.rect.width / captureRect.width,
                    height: observation.rect.height / captureRect.height
                )
                let seed = VNDetectedObjectObservation(boundingBox: localRect)
                let request = VNTrackObjectRequest(detectedObjectObservation: seed)
                requests[observation.id] = request
            }
        }
    }

    func track(in image: CGImage) async -> [String: CGRect]? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard !self.requests.isEmpty else {
                    continuation.resume(returning: [:])
                    return
                }
                do {
                    try self.handler.perform(Array(self.requests.values), on: image)
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                var tracked: [String: CGRect] = [:]
                for (id, request) in self.requests {
                    guard let result = request.results?.first as? VNDetectedObjectObservation,
                          result.confidence >= 0.45,
                          result.boundingBox.width > 0,
                          result.boundingBox.height > 0 else {
                        continuation.resume(returning: nil)
                        return
                    }
                    request.inputObservation = result
                    tracked[id] = result.boundingBox
                }
                continuation.resume(returning: tracked)
            }
        }
    }
}
