import Foundation
import Testing
@testable import KeyRemapperCore

private func config(_ text: String) throws -> RemapConfig {
    try RemapConfig(json: Data(text.utf8))
}

@Test func defaultConfigMapsHenkanAndMuhenkan() throws {
    let config = try config(RemapConfig.defaultFileContents)
    #expect(config.mappings == [
        KeyMapping(from: 0x7_0000_008A, to: 0x7_0000_0090),
        KeyMapping(from: 0x7_0000_008B, to: 0x7_0000_0091),
    ])
    #expect(config.keyboards.isEmpty)
}

@Test func acceptsNamesAliasesAndHexUsages() {
    #expect(KeyCodes.usage(for: "caps_lock") == 0x7_0000_0039)
    #expect(KeyCodes.usage(for: " Japanese_PC_XFER ") == 0x7_0000_008A)
    #expect(KeyCodes.usage(for: "a") == 0x7_0000_0004)
    #expect(KeyCodes.usage(for: "0") == 0x7_0000_0027)
    #expect(KeyCodes.usage(for: "f13") == 0x7_0000_0068)
    #expect(KeyCodes.usage(for: "fn") == 0xFF_0000_0003)
    #expect(KeyCodes.usage(for: "0x39") == 0x7_0000_0039)
    #expect(KeyCodes.usage(for: "0x700000039") == 0x7_0000_0039)
    #expect(KeyCodes.usage(for: "no_such_key") == nil)
    #expect(KeyCodes.usage(for: "0x0") == nil)
}

@Test func keyboardMappingsOverrideGlobalOnes() throws {
    let config = try config("""
        {
          mappings: [
            { from: "henkan", to: "kana" },
            { from: "caps_lock", to: "left_control" },
          ],
          keyboards: [
            { vendorID: 0x4fe, productID: 0x22, mappings: [{ from: "caps_lock", to: "escape" }] },
          ],
        }
        """)
    #expect(config.count == 3)
    #expect(config.mappings(vendorID: 0x4FE, productID: 0x22) == [
        KeyMapping(from: 0x7_0000_008A, to: 0x7_0000_0090),
        KeyMapping(from: 0x7_0000_0039, to: 0x7_0000_0029),
    ])
    // 設定のないキーボードには全体の置き換えだけ
    #expect(config.mappings(vendorID: 0x5AC, productID: 0x251) == config.mappings)
}

@Test func reportsWhereTheProblemIs() {
    #expect(throws: ConfigError(message: "keyboards[0].mappings[1]: 不明なキー \"kanaa\"")) {
        try config("""
            { keyboards: [{ vendorID: 1, productID: 2, mappings: [
              { from: "henkan", to: "kana" },
              { from: "muhenkan", to: "kanaa" },
            ] }] }
            """)
    }
    #expect(throws: ConfigError(message: "mappings[1]: \"henkan\" の置き換えが重複しています")) {
        try config(#"{ mappings: [{ from: "henkan", to: "kana" }, { from: "henkan", to: "eisu" }] }"#)
    }
    #expect(throws: ConfigError.self) {
        try config(#"{ keyboards: [{ productID: 2 }] }"#)
    }
    #expect(throws: ConfigError.self) {
        try config("{ mappings: [ ")
    }
}

@Test func emptyFileSectionsAreAllowed() throws {
    #expect(try config("{}") == RemapConfig(mappings: [], keyboards: []))
}
