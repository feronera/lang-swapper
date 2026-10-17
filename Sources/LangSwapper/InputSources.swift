import Carbon
import Foundation
import LangSwapperCore

/// Enabled keyboard layouts, their key maps (via UCKeyTranslate) and switching (via TIS).
final class InputSources {
    private(set) var layouts: [Language: LayoutMap] = [:]
    private var sources: [Language: TISInputSource] = [:]

    func reload() {
        layouts = [:]
        sources = [:]
        let filter = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else { return }
        for source in list {
            guard let language = Self.language(of: source), sources[language] == nil,
                  let map = Self.buildMap(source: source, language: language) else { continue }
            sources[language] = source
            layouts[language] = map
        }
    }

    func currentLanguage() -> Language? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return Self.language(of: source)
    }

    func select(_ language: Language) {
        guard let source = sources[language] else { return }
        TISSelectInputSource(source)
    }

    // MARK: - TIS helpers

    private static func property<T>(_ source: TISInputSource, _ key: CFString) -> T? {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue() as? T
    }

    static func language(of source: TISInputSource) -> Language? {
        let languages: [String] = property(source, kTISPropertyInputSourceLanguages) ?? []
        guard let primary = languages.first else { return nil }
        return Language.allCases.first { primary.hasPrefix($0.rawValue) }
    }

    /// Asks the layout what every key produces with and without Shift.
    static func buildMap(source: TISInputSource, language: Language) -> LayoutMap? {
        guard let data: Data = property(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let id: String = property(source, kTISPropertyInputSourceID) ?? "?"
        let kbdType = UInt32(LMGetKbdType())
        var forward: [KeyStroke: String] = [:]
        data.withUnsafeBytes { raw in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            for keyCode in UInt16(0)..<UInt16(128) {
                for shift in [false, true] {
                    var deadState: UInt32 = 0
                    var length = 0
                    var chars = [UniChar](repeating: 0, count: 4)
                    let modifiers = shift ? UInt32(shiftKey >> 8) & 0xFF : 0
                    let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDown), modifiers, kbdType,
                                                OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadState,
                                                chars.count, &length, &chars)
                    guard status == noErr, length > 0 else { continue }
                    let s = String(utf16CodeUnits: chars, count: length)
                    if s.unicodeScalars.allSatisfy(isPrintable) && s != " " {
                        forward[KeyStroke(keyCode: keyCode, shift: shift)] = s
                    }
                }
            }
        }
        return forward.isEmpty ? nil : LayoutMap(language: language, inputSourceID: id, forward: forward)
    }

    private static func isPrintable(_ s: Unicode.Scalar) -> Bool {
        s.value >= 0x20 && s.value != 0x7F && !(0xF700...0xF8FF).contains(s.value)
    }
}
