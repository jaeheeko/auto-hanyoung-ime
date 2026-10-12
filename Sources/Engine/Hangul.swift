import Foundation

/// 두벌식 자모 테이블, 음절→키, 키→음절 오토마타. tools/hangul.py와 동작이 같아야 한다.
public enum Hangul {
    public static let cho: [Character] = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    public static let jung: [Character] = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
    public static let jong: [Character] = Array("ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ")

    /// 단일 키 → 자모. Shift가 의미 있는 키는 QWERT(쌍자음), OP(ㅒㅖ)뿐이다.
    public static let keyToJamo: [Character: Character] = [
        "r": "ㄱ", "R": "ㄲ", "s": "ㄴ", "e": "ㄷ", "E": "ㄸ", "f": "ㄹ", "a": "ㅁ",
        "q": "ㅂ", "Q": "ㅃ", "t": "ㅅ", "T": "ㅆ", "d": "ㅇ", "w": "ㅈ", "W": "ㅉ",
        "c": "ㅊ", "z": "ㅋ", "x": "ㅌ", "v": "ㅍ", "g": "ㅎ",
        "k": "ㅏ", "o": "ㅐ", "i": "ㅑ", "O": "ㅒ", "j": "ㅓ", "p": "ㅔ", "u": "ㅕ",
        "P": "ㅖ", "h": "ㅗ", "y": "ㅛ", "n": "ㅜ", "b": "ㅠ", "m": "ㅡ", "l": "ㅣ",
    ]
    public static let shiftKeys: Set<Character> = Set("QWERTOP")

    static let compoundJung: [Character: [Character: Character]] = [
        "ㅗ": ["ㅏ": "ㅘ", "ㅐ": "ㅙ", "ㅣ": "ㅚ"],
        "ㅜ": ["ㅓ": "ㅝ", "ㅔ": "ㅞ", "ㅣ": "ㅟ"],
        "ㅡ": ["ㅣ": "ㅢ"],
    ]
    static let compoundJong: [Character: [Character: Character]] = [
        "ㄱ": ["ㅅ": "ㄳ"],
        "ㄴ": ["ㅈ": "ㄵ", "ㅎ": "ㄶ"],
        "ㄹ": ["ㄱ": "ㄺ", "ㅁ": "ㄻ", "ㅂ": "ㄼ", "ㅅ": "ㄽ", "ㅌ": "ㄾ", "ㅍ": "ㄿ", "ㅎ": "ㅀ"],
        "ㅂ": ["ㅅ": "ㅄ"],
    ]
    static let splitJong: [Character: (Character, Character)] = {
        var d: [Character: (Character, Character)] = [:]
        for (a, m) in compoundJong { for (b, c) in m { d[c] = (a, b) } }
        return d
    }()
    static let jamoToKeys: [Character: String] = {
        var d: [Character: String] = [:]
        for (k, j) in keyToJamo { d[j] = String(k) }
        for (a, m) in compoundJung { for (b, c) in m { d[c] = d[a]! + d[b]! } }
        for (a, m) in compoundJong { for (b, c) in m { d[c] = d[a]! + d[b]! } }
        return d
    }()
    static let choIndex: [Character: Int] = Dictionary(uniqueKeysWithValues: cho.enumerated().map { ($1, $0) })
    static let jungIndex: [Character: Int] = Dictionary(uniqueKeysWithValues: jung.enumerated().map { ($1, $0) })
    static let jongIndex: [Character: Int] = Dictionary(uniqueKeysWithValues: jong.enumerated().map { ($1, $0 + 1) })
    public static let consonants: Set<Character> = Set(cho)
    static let jongOK: Set<Character> = Set(jong)

    public static func isSyllable(_ ch: Character) -> Bool {
        guard let v = ch.unicodeScalars.first?.value, ch.unicodeScalars.count == 1 else { return false }
        return v >= 0xAC00 && v <= 0xD7A3
    }

    public static func isCompatJamo(_ ch: Character) -> Bool {
        guard let v = ch.unicodeScalars.first?.value, ch.unicodeScalars.count == 1 else { return false }
        return v >= 0x3131 && v <= 0x3163
    }

    public static func isHangul(_ ch: Character) -> Bool { isSyllable(ch) || isCompatJamo(ch) }

    /// 한글 문자열을 두벌식 키 문자열로. 한글이 아닌 문자는 그대로 둔다.
    public static func toKeys(_ text: String) -> String {
        var out = ""
        for ch in text {
            if isSyllable(ch) {
                let code = Int(ch.unicodeScalars.first!.value) - 0xAC00
                let c = code / 588, j = (code % 588) / 28, g = code % 28
                out += jamoToKeys[cho[c]]!
                out += jamoToKeys[jung[j]]!
                if g > 0 { out += jamoToKeys[jong[g - 1]]! }
            } else if isCompatJamo(ch) {
                out += jamoToKeys[ch] ?? String(ch)
            } else {
                out.append(ch)
            }
        }
        return out
    }

    /// 키 → 자모. QWERTOP 밖의 대문자는 소문자 자모로 본다.
    public static func jamoOfKey(_ ch: Character) -> Character? {
        if let j = keyToJamo[ch] { return j }
        if ch.isUppercase, let j = keyToJamo[Character(ch.lowercased())] { return j }
        return nil
    }

    public struct Composed {
        public let text: String
        public let lone: Int      // 단독 자모 수
        public let shiftBad: Int  // QWERTOP 밖 대문자 수
    }

    /// 키 문자열을 두벌식 오토마타로 조립한다.
    public static func compose(_ keys: String) -> Composed {
        var out = ""
        var cho: Character? = nil, jung: Character? = nil, jong: Character? = nil
        var lone = 0, shiftBad = 0

        func flush() {
            if cho == nil && jung == nil { return }
            if let c = cho, let j = jung {
                var code = 0xAC00 + choIndex[c]! * 588 + jungIndex[j]! * 28
                if let g = jong { code += jongIndex[g]! }
                out.append(Character(UnicodeScalar(code)!))
            } else {
                out.append(cho ?? jung!)
                lone += 1
            }
            cho = nil; jung = nil; jong = nil
        }

        for ch in keys {
            guard let j = jamoOfKey(ch) else {
                flush()
                out.append(ch)
                continue
            }
            if ch.isUppercase && !shiftKeys.contains(ch) { shiftBad += 1 }
            if consonants.contains(j) {
                if jung == nil {
                    if cho != nil { flush() }
                    cho = j
                } else if cho == nil {
                    flush()
                    cho = j
                } else if jong == nil {
                    if jongOK.contains(j) { jong = j } else { flush(); cho = j }
                } else if let comp = compoundJong[jong!]?[j] {
                    jong = comp
                } else {
                    flush()
                    cho = j
                }
            } else {
                if jung == nil {
                    jung = j
                } else if jong == nil {
                    if let comp = compoundJung[jung!]?[j] { jung = comp } else { flush(); jung = j }
                } else if let (first, second) = splitJong[jong!] {
                    jong = first
                    flush()
                    cho = second; jung = j
                } else {
                    let moved = jong!
                    jong = nil
                    flush()
                    cho = moved; jung = j
                }
            }
        }
        flush()
        return Composed(text: out, lone: lone, shiftBad: shiftBad)
    }
}
