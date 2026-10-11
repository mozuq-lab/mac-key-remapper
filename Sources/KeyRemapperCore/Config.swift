import Foundation

/// 1 つのキーの置き換え（HID の usage どうし）
public struct KeyMapping: Equatable, Sendable {
    public var from: UInt64
    public var to: UInt64

    public init(from: UInt64, to: UInt64) {
        self.from = from
        self.to = to
    }
}

/// 設定ファイルを読み込み、キーの名前を usage に直したもの
public struct RemapConfig: Equatable, Sendable {
    public struct Keyboard: Equatable, Sendable {
        public var name: String?
        public var vendorID: Int
        public var productID: Int
        /// このキーボードだけの置き換え（全体の置き換えとは別）
        public var mappings: [KeyMapping]
    }

    /// すべてのキーボードに適用する置き換え
    public var mappings: [KeyMapping]
    public var keyboards: [Keyboard]

    /// 指定したキーボードに適用する置き換え。全体の置き換えに、そのキーボードだけの置き換えを上書きで加える
    public func mappings(vendorID: Int, productID: Int) -> [KeyMapping] {
        guard let keyboard = keyboards.first(where: { $0.vendorID == vendorID && $0.productID == productID }) else {
            return mappings
        }
        let overridden = Set(keyboard.mappings.map(\.from))
        return mappings.filter { !overridden.contains($0.from) } + keyboard.mappings
    }

    /// 置き換えの件数（全体とキーボードごとの合計）
    public var count: Int {
        mappings.count + keyboards.reduce(0) { $0 + $1.mappings.count }
    }
}

public struct ConfigError: LocalizedError, Equatable {
    public var message: String
    public var errorDescription: String? { message }
}

extension RemapConfig {
    /// 設定ファイルの中身（JSON5。コメント、16 進数、末尾のカンマが使える）を読み込む
    public init(json: Data) throws {
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        let file: ConfigFile
        do {
            file = try decoder.decode(ConfigFile.self, from: json)
        } catch let error as DecodingError {
            throw ConfigError(message: "設定ファイルを読めません: \(error.readableDescription)")
        }

        mappings = try Self.resolve(file.mappings ?? [], location: "mappings")
        keyboards = try (file.keyboards ?? []).enumerated().map { index, keyboard in
            Keyboard(
                name: keyboard.name,
                vendorID: keyboard.vendorID,
                productID: keyboard.productID,
                mappings: try Self.resolve(keyboard.mappings ?? [], location: "keyboards[\(index)].mappings")
            )
        }
    }

    private static func resolve(_ entries: [ConfigFile.Mapping], location: String) throws -> [KeyMapping] {
        var result: [KeyMapping] = []
        for (index, entry) in entries.enumerated() {
            guard let from = KeyCodes.usage(for: entry.from) else {
                throw ConfigError(message: "\(location)[\(index)]: 不明なキー \"\(entry.from)\"")
            }
            guard let to = KeyCodes.usage(for: entry.to) else {
                throw ConfigError(message: "\(location)[\(index)]: 不明なキー \"\(entry.to)\"")
            }
            if result.contains(where: { $0.from == from }) {
                throw ConfigError(message: "\(location)[\(index)]: \"\(entry.from)\" の置き換えが重複しています")
            }
            result.append(KeyMapping(from: from, to: to))
        }
        return result
    }

    /// 設定ファイルがないときに作る内容（変換 → かな、無変換 → 英数）
    public static let defaultFileContents = """
        // KeyRemapper の設定ファイル（JSON5 形式。// のコメントや 16 進数が使えます）
        // 書き換えたら、メニューの「設定を読み込み直す」を選んでください。
        {
          // すべてのキーボードに適用する置き換え
          "mappings": [
            { "from": "henkan",   "to": "kana" },  // 変換 → かな
            { "from": "muhenkan", "to": "eisu" },  // 無変換 → 英数
          ],

          // 特定のキーボードだけに適用する置き換え（全体の置き換えより優先）。
          // vendorID と productID は、メニューの「接続中のキーボード」から選ぶとコピーできます。
          "keyboards": [
            // {
            //   "name": "HHKB",
            //   "vendorID": 0x4fe,
            //   "productID": 0x22,
            //   "mappings": [
            //     { "from": "caps_lock", "to": "left_control" },
            //   ],
            // },
          ],
        }

        """
}

/// 設定ファイルの形
private struct ConfigFile: Decodable {
    struct Mapping: Decodable {
        var from: String
        var to: String
    }

    struct Keyboard: Decodable {
        var name: String?
        var vendorID: Int
        var productID: Int
        var mappings: [Mapping]?
    }

    var mappings: [Mapping]?
    var keyboards: [Keyboard]?
}

private extension DecodingError {
    var readableDescription: String {
        func path(_ context: Context) -> String {
            let path = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
            return path.isEmpty ? "" : "\(path.hasPrefix(".") ? String(path.dropFirst()) : path): "
        }
        switch self {
        case .keyNotFound(let key, let context):
            return "\(path(context))\"\(key.stringValue)\" がありません"
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "\(path(context))値の種類が違います"
        case .dataCorrupted(let context):
            let underlying = (context.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
            return "\(path(context))\(underlying ?? context.debugDescription)"
        @unknown default:
            return localizedDescription
        }
    }
}
