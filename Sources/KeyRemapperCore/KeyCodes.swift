import Foundation

/// キーの名前と HID の usage（上位 32 ビットが usage page、下位 32 ビットが usage）の対応。
/// 名前は Karabiner-Elements の key_code に合わせ、日本語キーには短い別名も用意する。
public enum KeyCodes {
    /// キーボードのキー（usage page 0x07）
    private static let keyboardPage: UInt64 = 0x7_0000_0000

    private static let keyboardUsages: [String: UInt64] = {
        var table: [String: UInt64] = [:]

        // a〜z
        for (offset, scalar) in "abcdefghijklmnopqrstuvwxyz".unicodeScalars.enumerated() {
            table[String(scalar)] = 0x04 + UInt64(offset)
        }
        // 1〜9, 0
        for (offset, digit) in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"].enumerated() {
            table[digit] = 0x1E + UInt64(offset)
        }
        // f1〜f12, f13〜f24
        for number in 1...12 { table["f\(number)"] = 0x3A + UInt64(number - 1) }
        for number in 13...24 { table["f\(number)"] = 0x68 + UInt64(number - 13) }

        let named: [(UInt64, [String])] = [
            (0x28, ["return_or_enter", "return", "enter"]),
            (0x29, ["escape", "esc"]),
            (0x2A, ["delete_or_backspace", "backspace"]),
            (0x2B, ["tab"]),
            (0x2C, ["spacebar", "space"]),
            (0x2D, ["hyphen"]),
            (0x2E, ["equal_sign"]),
            (0x2F, ["open_bracket"]),
            (0x30, ["close_bracket"]),
            (0x31, ["backslash"]),
            (0x32, ["non_us_pound"]),
            (0x33, ["semicolon"]),
            (0x34, ["quote"]),
            (0x35, ["grave_accent_and_tilde"]),
            (0x36, ["comma"]),
            (0x37, ["period"]),
            (0x38, ["slash"]),
            (0x39, ["caps_lock"]),
            (0x46, ["print_screen"]),
            (0x47, ["scroll_lock"]),
            (0x48, ["pause"]),
            (0x49, ["insert"]),
            (0x4A, ["home"]),
            (0x4B, ["page_up"]),
            (0x4C, ["delete_forward"]),
            (0x4D, ["end"]),
            (0x4E, ["page_down"]),
            (0x4F, ["right_arrow"]),
            (0x50, ["left_arrow"]),
            (0x51, ["down_arrow"]),
            (0x52, ["up_arrow"]),
            (0x64, ["non_us_backslash"]),
            (0x65, ["application"]),
            // 日本語キーボード
            (0x87, ["international1", "japanese_pc_ro", "ro"]),
            (0x88, ["international2", "japanese_pc_katakana", "katakana_hiragana"]),
            (0x89, ["international3", "japanese_yen", "yen"]),
            (0x8A, ["international4", "japanese_pc_xfer", "henkan"]),
            (0x8B, ["international5", "japanese_pc_nfer", "muhenkan"]),
            (0x90, ["lang1", "japanese_kana", "kana"]),
            (0x91, ["lang2", "japanese_eisuu", "eisu"]),
            // 修飾キー
            (0xE0, ["left_control"]),
            (0xE1, ["left_shift"]),
            (0xE2, ["left_option"]),
            (0xE3, ["left_command"]),
            (0xE4, ["right_control"]),
            (0xE5, ["right_shift"]),
            (0xE6, ["right_option"]),
            (0xE7, ["right_command"]),
        ]
        for (usage, names) in named {
            for name in names { table[name] = usage }
        }
        return table.mapValues { keyboardPage | $0 }
    }()

    /// Apple のキーボードの fn キー（usage page 0xFF）
    private static let otherUsages: [String: UInt64] = ["fn": 0xFF_0000_0003]

    /// キーの名前、または 16 進の usage（"0x39" ならキーボードの usage、"0x700000039" なら page 込み）を usage に変換する
    public static func usage(for key: String) -> UInt64? {
        let name = key.trimmingCharacters(in: .whitespaces).lowercased()
        if let usage = keyboardUsages[name] ?? otherUsages[name] {
            return usage
        }
        guard name.hasPrefix("0x"), let value = UInt64(name.dropFirst(2), radix: 16), value != 0 else {
            return nil
        }
        return value <= 0xFFFF ? keyboardPage | value : value
    }
}
