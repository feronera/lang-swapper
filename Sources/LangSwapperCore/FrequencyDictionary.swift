import Foundation

/// Ranked word list in FrequencyWords format: one "word count" pair per line.
public final class FrequencyDictionary: @unchecked Sendable {
    private let counts: [String: Int]
    /// 1 for the most frequent word. Comparable across languages, unlike raw counts:
    /// the Thai corpus is hundreds of times smaller than the English one.
    private let ranks: [String: Int]
    /// Longest entry measured in Unicode scalars, bounds the segmentation search.
    public let maxScalarLength: Int

    public init(contents: String) {
        var counts: [String: Int] = [:]
        var maxLen = 0
        for line in contents.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ")
            guard parts.count >= 2, let n = Int(parts[parts.count - 1]) else { continue }
            let word = parts[0..<(parts.count - 1)].joined(separator: " ").lowercased()
            // Keep the highest count when case-folding merges two entries.
            if n > counts[word, default: 0] { counts[word] = n }
            maxLen = max(maxLen, word.unicodeScalars.count)
        }
        self.counts = counts
        var ranks: [String: Int] = [:]
        for (i, word) in counts.keys.sorted(by: { counts[$0]! > counts[$1]! }).enumerated() { ranks[word] = i + 1 }
        self.ranks = ranks
        self.maxScalarLength = min(maxLen, 24)
    }

    public convenience init(url: URL) throws {
        self.init(contents: try String(contentsOf: url, encoding: .utf8))
    }

    public var isEmpty: Bool { counts.isEmpty }

    public func count(of word: String) -> Int { counts[word.lowercased()] ?? 0 }

    /// 0...1: 1 for the top word, falling with log rank to 0 at the end of the list; 0 if absent.
    public func commonness(of word: String) -> Double {
        guard let rank = ranks[word.lowercased()], ranks.count > 1 else { return 0 }
        return 1 - log(Double(rank)) / log(Double(ranks.count))
    }

    /// Fraction of scalars covered by dictionary words (each at least two scalars long)
    /// in the best segmentation. Used for scripts written without spaces, such as Thai.
    public func segmentCoverage(_ text: String) -> Double {
        let scalars = Array(text.unicodeScalars)
        let n = scalars.count
        guard n > 0 else { return 0 }
        var best = [Int](repeating: 0, count: n + 1)
        for i in 1...n {
            best[i] = best[i - 1] // leave scalar i-1 uncovered
            let lower = max(0, i - maxScalarLength)
            var j = i - 2
            while j >= lower {
                var view = String.UnicodeScalarView()
                view.append(contentsOf: scalars[j..<i])
                if counts[String(view)] != nil {
                    best[i] = max(best[i], best[j] + (i - j))
                }
                j -= 1
            }
        }
        return Double(best[n]) / Double(n)
    }
}
