# KeyRemapper

macOS のキーを別のキーに置き換える、メニューバー常駐アプリです（Karabiner-Elements の簡易版）。
設定ファイルに書いた「キー A → キー B」の置き換えを、すべてのキーボード、または特定のキーボードに適用します。

置き換えには macOS の HID イベントシステムの `UserKeyMapping`（`hidutil property --set` と同じ仕組み）を使います。
そのため、**アクセシビリティなどの権限は要りません**。

## できること・できないこと

- できる: 1 つのキーを別の 1 つのキーに置き換える（例: 変換 → かな、Caps Lock → Control）。キーボードごとに別の設定にする
- できない: 組み合わせ（Ctrl+H → Backspace など）、アプリごとの設定、押しっぱなしと単押しで役割を変える、などの Karabiner-Elements の高度な機能

## 動作要件

- macOS 14 (Sonoma) 以降
- Swift 6 のツールチェーン（Xcode 16 以降）

## ビルドとインストール

```sh
scripts/build-app.sh                       # build/KeyRemapper.app ができる
ditto build/KeyRemapper.app /Applications/KeyRemapper.app
open /Applications/KeyRemapper.app
```

起動するとメニューバーにキーボードのアイコンが出ます。Dock には表示されません。

## 使い方

| メニュー項目 | 内容 |
| --- | --- |
| KeyRemapper: 有効（n 件の置き換え） | 現在の状態。設定ファイルに誤りがあるときは、その内容も表示する |
| キーの置き換えを有効にする | オフにすると、元のキー配置に戻す |
| 設定ファイルを開く | `~/.config/keyremapper/config.json` を開く（なければ作る） |
| 設定ファイルを Finder で表示 | 設定ファイルを Finder で選択した状態で開く |
| 設定を読み込み直す（⌘R） | 設定ファイルを書き換えた後に選ぶ |
| 接続中のキーボード | 選ぶと、そのキーボード用の設定の記述（vendorID / productID 入り）をコピーする |
| ログイン時に起動 | ログイン項目への登録・解除 |
| KeyRemapper を終了（⌘Q） | 終了すると、元のキー配置に戻す |

キーボードを接続し直したときや、スリープから復帰したときは、自動で置き換えを適用し直します。

## 設定ファイル

`~/.config/keyremapper/config.json` に書きます。初めて起動したときに、次の内容で作られます。
JSON5 形式なので、`//` のコメント、16 進数、末尾のカンマが使えます。

```json5
{
  // すべてのキーボードに適用する置き換え
  "mappings": [
    { "from": "henkan",   "to": "kana" },  // 変換 → かな
    { "from": "muhenkan", "to": "eisu" },  // 無変換 → 英数
  ],

  // 特定のキーボードだけに適用する置き換え（全体の置き換えより優先）
  "keyboards": [
    {
      "name": "HHKB",          // 自分用のメモ（照合には使わない）
      "vendorID": 0x4fe,
      "productID": 0x22,
      "mappings": [
        { "from": "caps_lock", "to": "left_control" },
      ],
    },
  ],
}
```

- 同じキーに全体とキーボードごとの両方の置き換えがある場合は、キーボードごとの置き換えが優先されます。
- 設定ファイルに誤りがある場合は、メニューにその場所を表示し、前の設定のまま動作します。

### キーの名前

名前は Karabiner-Elements の `key_code` と同じです。主なものは次のとおりです。

| 種類 | 名前 |
| --- | --- |
| 文字・数字 | `a`〜`z`、`0`〜`9` |
| 日本語キー | `henkan`（変換）、`muhenkan`（無変換）、`kana`（かな）、`eisu`（英数）、`katakana_hiragana`、`yen`、`ro` |
| 修飾キー | `left_control`、`left_shift`、`left_option`、`left_command`（`right_` も同様）、`caps_lock`、`fn` |
| その他 | `escape`、`tab`、`spacebar`、`return_or_enter`、`delete_or_backspace`、`delete_forward`、`f1`〜`f24`、矢印キー（`up_arrow` など） |

一覧にないキーは、HID の usage を 16 進数で書けます（`"0x39"` = Caps Lock。usage page 込みの `"0x700000039"` も可）。
すべての名前は [KeyCodes.swift](Sources/KeyRemapperCore/KeyCodes.swift) にあります。

## Karabiner-Elements との併用

Karabiner-Elements が動いている間は、Karabiner が設定したキーボード（「Devices」で有効にしたもの）の入力を Karabiner が先に受け取ります。
そのキーボードには KeyRemapper のキーボードごとの置き換えが効きません。

Karabiner-Elements から移行する場合は、Karabiner-Elements を終了するか、アンインストールしてください。

## 他の Mac に配る（公証）

[MeetRec](https://github.com/mozuq-lab/meetrec) と同じ手順です。公証用のキーチェーンプロファイル（既定は `meetrec-notary`）を用意したうえで、次を実行します。

```sh
scripts/build-app.sh --notarize            # 配布用の build/KeyRemapper.zip ができる
```

## 開発

```sh
swift build
swift test      # 設定ファイルの読み込みとキーの名前のテスト
```

| ディレクトリ | 内容 |
| --- | --- |
| `Sources/KeyRemapperCore` | 設定ファイルの読み込み、キーの名前、置き換えの適用とキーボードの監視（IOKit） |
| `Sources/KeyRemapper` | メニューバーのアプリ（SwiftUI の `MenuBarExtra`） |
| `App/Info.plist`, `scripts/build-app.sh` | KeyRemapper.app の組み立て、署名、公証 |

置き換えの状態は、`hidutil` でも確かめられます。

```sh
hidutil property --get UserKeyMapping                                        # 全体
hidutil property --matching '{"VendorID":0x4fe,"ProductID":0x22}' --get UserKeyMapping   # キーボードごと
```
