import KeyRemapperCore
import SwiftUI

struct MenuContent: View {
    @Bindable var model: RemapperModel

    var body: some View {
        Text("KeyRemapper: \(model.statusText)")
        if let message = model.errorMessage {
            Text(message)
        }
        Toggle("キーの置き換えを有効にする", isOn: $model.isEnabled)

        Divider()

        Button("設定ファイルを開く") { model.openConfig() }
        Button("設定ファイルを Finder で表示") { model.revealConfig() }
        Button("設定を読み込み直す") { model.reloadConfig(showsAlert: true) }
            .keyboardShortcut("r")

        Menu("接続中のキーボード") {
            Text("選ぶと、設定ファイル用の記述をコピーします")
            Divider()
            if model.keyboards.isEmpty {
                Text("見つかりません")
            }
            ForEach(model.keyboards) { keyboard in
                Button("\(keyboard.name)（0x\(String(keyboard.vendorID, radix: 16)) / 0x\(String(keyboard.productID, radix: 16))）") {
                    model.copySnippet(for: keyboard)
                }
            }
        }

        Divider()

        Toggle("ログイン時に起動", isOn: Binding(
            get: { model.launchesAtLogin },
            set: { model.setLaunchesAtLogin($0) }
        ))
        .onAppear { model.refreshLaunchesAtLogin() }

        Button("KeyRemapper を終了") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
