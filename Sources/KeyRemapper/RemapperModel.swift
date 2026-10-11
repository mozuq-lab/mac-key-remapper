import AppKit
import KeyRemapperCore
import Observation
import ServiceManagement

@MainActor
@Observable
final class RemapperModel {
    enum Status: Equatable {
        case active(count: Int)
        case disabled
        case failed(String)
    }

    private enum Keys {
        static let isEnabled = "isEnabled"
    }

    private(set) var status: Status = .disabled
    private(set) var keyboards: [ConnectedKeyboard] = []
    private(set) var launchesAtLogin = SMAppService.mainApp.status == .enabled

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.isEnabled)
            applyCurrentConfig()
        }
    }

    /// ~/.config/keyremapper/config.json
    let configURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/keyremapper/config.json")

    @ObservationIgnored private let mapper = HIDKeyMapper()
    @ObservationIgnored private var config: RemapConfig?

    init() {
        isEnabled = UserDefaults.standard.object(forKey: Keys.isEnabled) as? Bool ?? true
    }

    var statusSymbol: String {
        switch status {
        case .active: "keyboard"
        case .disabled: "keyboard.chevron.compact.down"
        case .failed: "exclamationmark.triangle"
        }
    }

    var statusText: String {
        switch status {
        case .active(let count): "有効（\(count) 件の置き換え）"
        case .disabled: "無効"
        case .failed: "エラー"
        }
    }

    func start() {
        mapper.onKeyboardsChanged = { [unowned self] in
            // 接続し直したキーボードには個別の設定が残っていないので、適用し直す
            applyCurrentConfig()
        }
        mapper.startObservingKeyboards()
        // スリープから復帰したときも、念のため適用し直す
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [unowned self] _ in
            MainActor.assumeIsolated { applyCurrentConfig() }
        }
        reloadConfig(showsAlert: true)
    }

    // MARK: - 設定

    /// 設定ファイルを読み込み直して適用する。読めなかった場合は、前の設定のまま動かす
    func reloadConfig(showsAlert: Bool) {
        do {
            config = try loadConfig()
            applyCurrentConfig()
        } catch {
            let message = error.localizedDescription
            status = .failed(message)
            if showsAlert {
                showAlert("設定ファイルを読み込めませんでした", "\(message)\n\n前の設定のまま動作します。\n\(configPathText)")
            }
        }
    }

    private func loadConfig() throws -> RemapConfig {
        if !FileManager.default.fileExists(atPath: configURL.path) {
            try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try RemapConfig.defaultFileContents.write(to: configURL, atomically: true, encoding: .utf8)
        }
        return try RemapConfig(json: Data(contentsOf: configURL))
    }

    private func applyCurrentConfig() {
        keyboards = mapper.keyboards
        guard let config else { return }
        guard isEnabled else {
            mapper.clear()
            status = .disabled
            return
        }
        if mapper.apply(config) {
            status = .active(count: config.count)
        } else {
            status = .failed("キーの置き換えを設定できませんでした")
        }
    }

    func restoreOriginalKeys() {
        mapper.clear()
    }

    var configPathText: String {
        (configURL.path as NSString).abbreviatingWithTildeInPath
    }

    var errorMessage: String? {
        if case .failed(let message) = status { message } else { nil }
    }

    func openConfig() {
        _ = try? loadConfig()  // なければ作っておく
        // .json に関連付けられたアプリがなければテキストエディットで開く
        if NSWorkspace.shared.urlForApplication(toOpen: configURL) != nil {
            NSWorkspace.shared.open(configURL)
        } else if let textEdit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            NSWorkspace.shared.open([configURL], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func revealConfig() {
        NSWorkspace.shared.activateFileViewerSelecting([configURL])
    }

    func copySnippet(for keyboard: ConnectedKeyboard) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(keyboard.configSnippet, forType: .string)
    }

    // MARK: - ログイン時の起動

    func setLaunchesAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            showAlert("ログイン項目を変更できませんでした", error.localizedDescription)
        }
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    func refreshLaunchesAtLogin() {
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: -

    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }
}
