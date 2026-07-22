import Foundation

/// Matches spoken transcripts against a wake word, tolerating ASR spelling variants.
/// "Cael" → "Kale", "Sonique" → "Sonic", etc. are all considered hits.
/// Now includes confidence scoring to filter false positives.
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

    /// Calculate confidence score for wake word match (0.0 = no match, 1.0 = perfect match).
    /// Use this to filter false positives.
    static func confidence(wakeWord wake: String, in text: String) -> Double {
        let words = text.split(whereSeparator: { $0 == " " || $0 == "," })
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?")) }
            .filter { !$0.isEmpty }

        var bestScore = 0.0
        for word in words {
            let score = wordMatchConfidence(word, wake: wake)
            if score > bestScore {
                bestScore = score
            }
        }
        return bestScore
    }

    // MARK: - Internal

    private static func wordMatches(_ word: String, wake: String) -> Bool {
        let w = word.lowercased()
        if w == wake || w.contains(wake) || wake.contains(w) { return true }
        if levenshtein(w, wake) <= 1 { return true }
        return phoneticKey(w) == phoneticKey(wake)
    }

    /// Calculate confidence score for a single word match (0.0-1.0).
    /// 1.0 = exact match, 0.9+ = very close, 0.5-0.9 = phonetic/fuzzy, 0.0 = no match.
    private static func wordMatchConfidence(_ word: String, wake: String) -> Double {
        let w = word.lowercased()
        let wakeLower = wake.lowercased()

        // Exact match = perfect confidence
        if w == wakeLower { return 1.0 }

        // Contains check (substring match)
        if w.contains(wakeLower) {
            let ratio = Double(wakeLower.count) / Double(w.count)
            return 0.9 * ratio  // Scale by coverage
        }
        if wakeLower.contains(w) {
            let ratio = Double(w.count) / Double(wakeLower.count)
            return 0.85 * ratio
        }

        // Levenshtein distance (1-2 char edits)
        let distance = levenshtein(w, wakeLower)
        if distance == 0 { return 1.0 }
        if distance == 1 { return 0.85 }
        if distance == 2 { return 0.7 }
        if distance <= 3 {
            return 0.5 + (0.2 * (3.0 - Double(distance)) / 3.0)  // 0.5-0.7 range
        }

        // Phonetic match (last resort)
        if phoneticKey(w) == phoneticKey(wakeLower) {
            // Phonetic matches are less reliable - penalize heavily
            return 0.4
        }

        return 0.0
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
