import Foundation
import NaturalLanguage

public struct NameSuggestion: Identifiable, Sendable, Equatable {
    public var id: String { "\(passageID)-\(name.lowercased())" }
    public let name: String
    public let evidence: String
    public let time: Double
    public let passageID: UUID
}

public enum NameSuggestions {
    public static func find(in passages: [Passage]) -> [NameSuggestion] {
        // Only self-introductions are eligible. Other named entities are not speaker identities.
        let expression = try! NSRegularExpression(pattern: "(?i)(?:^|[.!?]\\s+|\\bhello[,!]?\\s+|\\bhi[,!]?\\s+)(?:my name is|i am|i['’]m)\\s+")
        var found: [NameSuggestion] = []
        var seen = Set<String>()
        for passage in passages {
            let text = passage.text
            let tagger = NLTagger(tagSchemes: [.nameType])
            tagger.string = text
            let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                guard let range = Range(match.range, in: text), range.upperBound < text.endIndex else { continue }
                let start = range.upperBound
                let (tag, tokenRange) = tagger.tag(at: start, unit: .word, scheme: .nameType)
                guard tag == .personalName else { continue }
                var nameRange = tokenRange
                tagger.enumerateTags(in: start..<text.endIndex, unit: .word, scheme: .nameType,
                                     options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
                    if range.lowerBound == start && tag == .personalName { nameRange = range }
                    return false
                }
                let name = String(text[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, name.count <= 80, seen.insert(name.lowercased()).inserted else { continue }
                found.append(NameSuggestion(name: name, evidence: TextPolicy.clean(text), time: passage.start, passageID: passage.id))
            }
        }
        return found
    }
}
