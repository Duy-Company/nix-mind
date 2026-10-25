import Foundation

enum TopicSearchScope: String, CaseIterable, Sendable { case sheet = "This sheet", workbook = "All sheets" }

struct TopicSearchResult: Identifiable, Sendable {
    var id: String { "\(sheetID.utf16.count):\(sheetID)\(topicID)" }
    let sheetID: String
    let topicID: String
    let title: String
    let titlePreview: String
    let titleHighlights: [NSRange]
    let notePreview: String
    let noteHighlights: [NSRange]
    let breadcrumb: String
    let isFuzzy: Bool
}

struct TopicSearchResponse: Sendable {
    var results: [TopicSearchResult] = []
    var total = 0
}

/// Immutable snapshots are searched off the main thread. Highlight offsets are UTF-16,
/// mapped back to original graphemes so accents, emoji and expanding folds stay intact.
struct TopicSearchIndex: Sendable {
    private struct Entry: Sendable {
        let sheetID: String, topicID: String, title: String, note: String, breadcrumb: String
        let foldedTitle: String, foldedNote: String
    }
    private struct Match {
        var score: Int
        var ranges: [NSRange]
        var fuzzy = false
    }
    private struct Candidate {
        let entry: Int, score: Int, order: Int
        let title: [NSRange], note: [NSRange]
        let fuzzy: Bool
    }
    private let entries: [Entry]
    private static let wordPattern = try! NSRegularExpression(pattern: "[\\p{L}\\p{N}]+")
    private static let foldingLocale = Locale(identifier: "en_US_POSIX")

    init(book: MindBook, sheetID: String? = nil) {
        var values: [Entry] = []
        for sheet in book.sheets where sheetID == nil || sheet.id == sheetID {
            let topics = Dictionary(uniqueKeysWithValues: sheet.map.topics.map { ($0.id, $0) })
            for topic in sheet.map.topics {
                if Task.isCancelled { break }
                var ancestors: [String] = [], parent = topic.parentID
                // Enough context to distinguish duplicates, without copying an entire deep path.
                while let id = parent, let ancestor = topics[id], ancestors.count < 3 {
                    ancestors.append(String(ancestor.title.prefix(70))); parent = ancestor.parentID
                }
                let path = ([sheet.title] + ancestors.reversed()).joined(separator: " › ")
                values.append(Entry(sheetID: sheet.id, topicID: topic.id, title: topic.title, note: topic.note,
                                    breadcrumb: path, foldedTitle: Self.fold(topic.title), foldedNote: Self.fold(topic.note)))
            }
        }
        entries = values
    }

    static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: foldingLocale)
            .lowercased().replacingOccurrences(of: "đ", with: "d")
    }

    func search(_ query: String, limit: Int = 80) -> TopicSearchResponse {
        let phrase = Self.fold(String(query.prefix(128))).trimmingCharacters(in: .whitespacesAndNewlines)
        let terms = Array(Set(phrase.split(whereSeparator: \.isWhitespace).map(String.init))).sorted()
        guard !terms.isEmpty, limit > 0 else { return TopicSearchResponse() }
        var candidates: [Candidate] = []
        for (order, entry) in entries.enumerated() {
            if Task.isCancelled { return TopicSearchResponse() }
            var score = 0, title: [NSRange] = [], note: [NSRange] = [], fuzzy = false, accepted = true
            for term in terms {
                if let match = Self.match(term, in: entry.foldedTitle, fuzzy: true) {
                    score += match.score; title += match.ranges; fuzzy = fuzzy || match.fuzzy
                } else if let match = Self.match(term, in: entry.foldedNote, fuzzy: false) {
                    score += match.score / 3; note += match.ranges
                } else { accepted = false; break }
            }
            if accepted {
                if entry.foldedTitle == phrase { score += 2000 }
                else if entry.foldedTitle.range(of: phrase) != nil { score += 400 }
                candidates.append(Candidate(entry: order, score: score, order: order, title: title, note: note, fuzzy: fuzzy))
            }
        }
        candidates.sort { $0.score == $1.score ? $0.order < $1.order : $0.score > $1.score }
        let results = candidates.prefix(limit).map { candidate in
            let entry = entries[candidate.entry]
            let title = Self.preview(entry.title, ranges: Self.originalRanges(candidate.title, in: entry.title), length: 180)
            let note = candidate.note.isEmpty ? ("", [NSRange]()) : Self.preview(entry.note, ranges: Self.originalRanges(candidate.note, in: entry.note), length: 170)
            return TopicSearchResult(sheetID: entry.sheetID, topicID: entry.topicID, title: entry.title,
                                     titlePreview: title.0, titleHighlights: title.1,
                                     notePreview: note.0, noteHighlights: note.1,
                                     breadcrumb: entry.breadcrumb, isFuzzy: candidate.fuzzy)
        }
        return TopicSearchResponse(results: results, total: candidates.count)
    }

    private static func match(_ term: String, in text: String, fuzzy: Bool) -> Match? {
        let ns = text as NSString
        guard ns.length > 0 else { return nil }
        var start = 0, ranges: [NSRange] = [], score = 0
        while start < ns.length && ranges.count < 64 {
            let range = ns.range(of: term, range: NSRange(location: start, length: ns.length - start))
            if range.location == NSNotFound { break }
            let previousIsLetter = range.location > 0 && UnicodeScalar(ns.character(at: range.location - 1)).map { CharacterSet.alphanumerics.contains($0) } == true
            let boundary = !previousIsLetter
            score = max(score, text == term ? 1000 : (range.location == 0 ? 850 : (boundary ? 750 : 550)))
            ranges.append(range); start = NSMaxRange(range)
        }
        if !ranges.isEmpty { return Match(score: score, ranges: ranges) }
        guard fuzzy, term.count >= 2, term.count <= 64 else { return nil }
        let words = wordPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).map(\.range)
        // Acronyms and compact subsequences support "mcp" → "Model Context Protocol".
        if term.count <= 16 {
            let initials = words.map { ns.substring(with: $0).prefix(1) }.joined()
            if let found = initials.range(of: term) {
                let offset = initials.distance(from: initials.startIndex, to: found.lowerBound)
                let selected = words.dropFirst(offset).prefix(term.count).map { NSRange(location: $0.location, length: 1) }
                return Match(score: 430, ranges: selected, fuzzy: true)
            }
        }
        if term.count >= 4 {
            let allowed = term.count >= 8 ? 2 : 1
            var best: Match?
            for word in words where abs(word.length - term.utf16.count) <= allowed && word.length <= 64 {
                let distance = editDistance(Array(term), Array(ns.substring(with: word)), maximum: allowed)
                if distance <= allowed {
                    let match = Match(score: 400 - distance * 45 + (word.length == ns.length ? 150 : 0), ranges: [word], fuzzy: true)
                    if best == nil || match.score > best!.score { best = match }
                }
            }
            if let best { return best }
        }
        // Bound the span to avoid extremely loose matches in long topic titles.
        if term.count <= 16 {
            let wanted = Array(term.utf16)
            for word in words where word.length <= 64 {
                let units = Array(ns.substring(with: word).utf16)
                var positions: [Int] = [], cursor = 0
                for unit in wanted {
                    guard let next = units[cursor...].firstIndex(of: unit) else { break }
                    positions.append(next); cursor = next + 1
                }
                if positions.count == wanted.count, positions.first == 0, let last = positions.last, last <= wanted.count * 2 {
                    return Match(score: 250 - last, ranges: positions.map { NSRange(location: word.location + $0, length: 1) }, fuzzy: true)
                }
            }
        }
        return nil
    }

    /// Bounded Damerau-Levenshtein: insert/delete/replace and adjacent transposition.
    private static func editDistance(_ a: [Character], _ b: [Character], maximum: Int) -> Int {
        guard abs(a.count - b.count) <= maximum else { return maximum + 1 }
        var previous = Array(0...b.count), older = previous
        for i in 1...a.count {
            var row = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                row[j] = min(previous[j] + 1, row[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                if i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1] { row[j] = min(row[j], older[j - 2] + 1) }
            }
            if row.min()! > maximum { return maximum + 1 }
            older = previous; previous = row
        }
        return previous[b.count]
    }

    private static func originalRanges(_ ranges: [NSRange], in original: String) -> [NSRange] {
        guard !ranges.isEmpty else { return [] }
        let lastMatchEnd = ranges.map { NSMaxRange($0) }.max()!
        var result: [NSRange] = [], foldedOffset = 0, originalOffset = 0
        for character in original {
            if foldedOffset >= lastMatchEnd || Task.isCancelled { break }
            let value = String(character), foldedLength = fold(value).utf16.count
            let foldedRange = NSRange(location: foldedOffset, length: foldedLength)
            if ranges.contains(where: { NSIntersectionRange($0, foldedRange).length > 0 }) {
                let range = NSRange(location: originalOffset, length: value.utf16.count)
                if let last = result.last, NSMaxRange(last) == range.location { result[result.count - 1].length += range.length }
                else { result.append(range) }
            }
            foldedOffset += foldedLength; originalOffset += value.utf16.count
        }
        return result
    }

    private static func preview(_ text: String, ranges: [NSRange], length: Int) -> (String, [NSRange]) {
        guard text.count > length else { return (text, ranges) }
        let match = ranges.first.flatMap { Range($0, in: text) }?.lowerBound ?? text.startIndex
        let start = text.index(match, offsetBy: -45, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(start, offsetBy: length, limitedBy: text.endIndex) ?? text.endIndex
        let prefix = start == text.startIndex ? "" : "…"
        let window = NSRange(start..<end, in: text)
        let highlights = ranges.compactMap { range -> NSRange? in
            let intersection = NSIntersectionRange(range, window)
            guard intersection.length > 0 else { return nil }
            return NSRange(location: intersection.location - window.location + prefix.utf16.count, length: intersection.length)
        }
        return (prefix + text[start..<end] + (end == text.endIndex ? "" : "…"), highlights)
    }
}
