import Foundation

/// Matches spoken transcripts against a wake word, tolerating ASR spelling variants.
/// "Cael" → "Kale", "Sonique" → "Sonic", etc. are all considered hits.
enum WakeWordMatcher {

    /// Strip the wake word from `text` and return the remainder.
    /// Returns nil if the wake word isn't present (i.e. the device is still asleep).
    static func strip(wakeWord wake: String, from text: String) -> String? {
        let words = text.split(whereSeparator: { $0 == " " || $0 == "," })
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?")) }
            .filter { !$0.isEmpty }

        guard let hitIndex = words.firstIndex(where: { wordMatches($0, wake: wake) }) else {
            return nil
        }

        let remaining = Array(words[(hitIndex + 1)...])
        return remaining.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?"))
    }

    // MARK: - Internal

    private static func wordMatches(_ word: String, wake: String) -> Bool {
        let w = word.lowercased()
        if w == wake || w.contains(wake) || wake.contains(w) { return true }
        if levenshtein(w, wake) <= 1 { return true }
        return phoneticKey(w) == phoneticKey(wake)
    }

    /// Drop vowels (except leading), collapse common homophones, dedupe doubles.
    /// "cael" → "kl", "kale" → "kl" — they match.
    private static func phoneticKey(_ s: String) -> String {
        let chars = Array(s.lowercased())
        guard !chars.isEmpty else { return "" }
        var out = ""
        for (i, c) in chars.enumerated() {
            var ch = c
            switch ch {
            case "c", "q", "k": ch = "k"
            case "z": ch = "s"
            case "y": ch = "i"
            default: break
            }
            let isVowel = "aeiou".contains(ch)
            if isVowel && i != 0 { continue }
            if out.last == ch { continue }
            out.append(ch)
        }
        return out
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                let cost = a[i-1] == b[j-1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j-1] + 1, prev[j-1] + cost)
            }
            prev = cur
        }
        return prev[b.count]
    }
}
