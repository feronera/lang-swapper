import Foundation

public enum Language: String, CaseIterable, Sendable {
    case english = "en"
    case thai = "th"

    public var shortName: String { rawValue.uppercased() }
}

/// A physical key press, independent of which layout is active.
public struct KeyStroke: Hashable, Sendable {
    public let keyCode: UInt16
    public let shift: Bool

    public init(keyCode: UInt16, shift: Bool) {
        self.keyCode = keyCode
        self.shift = shift
    }
}

/// What each physical key produces under one keyboard layout.
public struct LayoutMap: Sendable {
    public let language: Language
    public let inputSourceID: String
    private let forward: [KeyStroke: String]

    public init(language: Language, inputSourceID: String, forward: [KeyStroke: String]) {
        self.language = language
        self.inputSourceID = inputSourceID
        self.forward = forward
    }

    public func produces(_ stroke: KeyStroke) -> Bool { forward[stroke] != nil }

    /// Re-types the strokes on this layout; nil when a stroke has no output here.
    public func render(_ strokes: [KeyStroke]) -> String? {
        var out = ""
        for stroke in strokes {
            guard let s = forward[stroke] else { return nil }
            out += s
        }
        return out
    }

    public var count: Int { forward.count }
}
