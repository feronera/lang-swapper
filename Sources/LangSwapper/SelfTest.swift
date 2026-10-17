import Foundation
import LangSwapperCore

/// Runs the detector against this Mac's real layouts and dictionaries.
/// Usage: `swift run LangSwapper --selftest`
enum SelfTest {
    static func run() -> Bool {
        let sources = InputSources()
        sources.reload()
        let layouts = sources.layouts
        print("Layouts:", layouts.values.map { "\($0.language.rawValue)=\($0.inputSourceID) (\($0.count) keys)" })
        guard let en = layouts[.english], let th = layouts[.thai] else {
            print("FAIL: need both an English and a Thai keyboard layout enabled")
            return false
        }
        let detector = Dictionaries.makeDetector()

        // (word as the user meant it, language it belongs to, should we switch?)
        let cases: [(String, Language, Bool)] = [
            ("hello", .english, true), ("world", .english, true), ("meeting", .english, true),
            ("สวัสดี", .thai, true), ("ครับ", .thai, true), ("ภาษาไทย", .thai, true),
            ("ขอบคุณครับ", .thai, true), ("the", .english, true), ("ไม่", .thai, true),
            ("เป็น", .thai, true), ("people", .english, true),
            // Ambiguous: "ok" on the Thai layout is "นา", a real Thai word. Leave it.
            ("ok", .english, false),
        ]
        var ok = true
        for (word, language, expectSwitch) in cases {
            let intended = language == .english ? en : th
            let wrong = language == .english ? th : en
            guard let strokes = strokes(for: word, in: intended), let typed = wrong.render(strokes) else {
                print("SKIP \(word): cannot be typed on \(intended.inputSourceID)")
                continue
            }
            // Typed on the wrong layout: should switch back to `word`.
            let fix = detector.decide(strokes: strokes, typed: typed, current: wrong.language, layouts: layouts)
            let fixed = fix?.replacement == word
            // Typed on the right layout: must be left alone.
            let leftAlone = detector.decide(strokes: strokes, typed: word, current: language, layouts: layouts) == nil
            let pass = fixed == expectSwitch && leftAlone
            ok = ok && pass
            print("\(pass ? "PASS" : "FAIL") \(typed) → \(fix?.replacement ?? "nil")  (expected \(word); untouched-when-correct: \(leftAlone))")
        }
        // Commands typed correctly in a terminal must be left alone even if not dictionary words.
        for command in ["git", "kubectl", "pnpm", "chmod"] {
            guard let strokes = strokes(for: command, in: en) else { continue }
            let fix = detector.decide(strokes: strokes, typed: command, current: .english, layouts: layouts,
                                      category: AppCategory(bundleID: "com.apple.Terminal"))
            ok = ok && fix == nil
            print("\(fix == nil ? "PASS" : "FAIL") \(command) in Terminal → \(fix?.replacement ?? "untouched")")
        }
        // Per-app language memory: needs enough words and a clear majority.
        var profile = AppLanguageProfile()
        for _ in 0..<19 { profile.record(.english, in: "code") }
        let tooFew = profile.dominant(in: "code") == nil
        profile.record(.english, in: "code")
        let english = profile.dominant(in: "code") == .english
        for _ in 0..<12 { profile.record(.english, in: "line") }
        for _ in 0..<11 { profile.record(.thai, in: "line") }
        let mixed = profile.dominant(in: "line") == nil
        let profilePass = tooFew && english && mixed
        ok = ok && profilePass
        print("\(profilePass ? "PASS" : "FAIL") app language profile (few: \(tooFew), dominant: \(english), mixed: \(mixed))")

        if ProcessInfo.processInfo.environment["LS_PROBE"] != nil {
            for w in (ProtectedWords.commands.union(ProtectedWords.tech)).sorted() {
                guard let st = strokes(for: w, in: en),
                      let fix = detector.decide(strokes: st, typed: w, current: .english, layouts: layouts) else { continue }
                print("AT RISK \(w) → \(fix.replacement)")
            }
        }
        return ok
    }

    /// Inverts a layout to find the keystrokes that type `text`.
    private static func strokes(for text: String, in layout: LayoutMap) -> [KeyStroke]? {
        var inverse: [String: KeyStroke] = [:]
        for code in UInt16(0)..<128 {
            for shift in [false, true] {
                let k = KeyStroke(keyCode: code, shift: shift)
                if let s = layout.render([k]), inverse[s] == nil { inverse[s] = k }
            }
        }
        var out: [KeyStroke] = []
        for scalar in text.unicodeScalars {
            guard let k = inverse[String(scalar)] else { return nil }
            out.append(k)
        }
        return out
    }
}
