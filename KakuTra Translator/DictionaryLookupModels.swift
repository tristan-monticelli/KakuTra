import Foundation

struct DictionaryTermResult: Equatable, Identifiable, Sendable {
    let term: String
    let reading: String?
    let dictionary: String
    let glosses: [String]
    let tags: [String]
    let alternateReadings: [String]

    init(
        term: String,
        reading: String?,
        dictionary: String,
        glosses: [String],
        tags: [String] = [],
        alternateReadings: [String] = []
    ) {
        self.term = term
        self.reading = reading
        self.dictionary = dictionary
        self.glosses = glosses
        self.tags = tags
        self.alternateReadings = alternateReadings
    }

    var id: String {
        "\(dictionary)|\(term)|\(reading ?? "")|\(tags.joined(separator: ","))|\(glosses.joined(separator: "\u{1f}"))|\(alternateReadings.joined(separator: ","))"
    }
}
