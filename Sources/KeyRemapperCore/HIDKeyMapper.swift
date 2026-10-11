import Foundation
import IOKit
import IOKit.hid

/// 接続中のキーボード
public struct ConnectedKeyboard: Identifiable, Hashable, Sendable {
    public var id: UInt64
    public var name: String
    public var vendorID: Int
    public var productID: Int

    /// 設定ファイルの "keyboards" にそのまま貼り付けられる記述
    public var configSnippet: String {
        """
        {
          "name": "\(name)",
          "vendorID": 0x\(String(vendorID, radix: 16)),
          "productID": 0x\(String(productID, radix: 16)),
          "mappings": [
            { "from": "caps_lock", "to": "left_control" },
          ],
        },
        """
    }
}

/// HID イベントシステムの UserKeyMapping（`hidutil property --set` と同じもの）でキーを置き換える。
/// 権限は要らない。設定はログアウトまたは再起動で消える。
@MainActor
public final class HIDKeyMapper {
    private static let userKeyMappingKey = "UserKeyMapping" as CFString

    private let client: IOHIDEventSystemClient
    private var notificationPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var pendingChange: DispatchWorkItem?

    /// キーボードの接続や取り外しの後に呼ばれる（続けて起きた変化はまとめて 1 回）
    public var onKeyboardsChanged: (() -> Void)?

    public init() {
        client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    }

    // MARK: - 置き換え

    /// 置き換えを適用する。
    /// 全体の置き換えはイベントシステムに設定し、後から接続したキーボードにも効くようにする。
    /// 接続中のキーボードには、それぞれに適用する置き換えを個別にも設定する
    /// （キーボードごとの設定や、以前の設定が残らないようにするため）。
    @discardableResult
    public func apply(_ config: RemapConfig) -> Bool {
        var succeeded = IOHIDEventSystemClientSetProperty(client, Self.userKeyMappingKey, Self.property(config.mappings))
        for (service, keyboard) in keyboardServices() {
            let mappings = config.mappings(vendorID: keyboard.vendorID, productID: keyboard.productID)
            succeeded = IOHIDServiceClientSetProperty(service, Self.userKeyMappingKey, Self.property(mappings)) && succeeded
        }
        return succeeded
    }

    /// 置き換えをすべて外す
    @discardableResult
    public func clear() -> Bool {
        apply(RemapConfig(mappings: [], keyboards: []))
    }

    /// 指定したキーボードに、いま設定されている置き換え（確認用）
    public func currentMappings(of keyboard: ConnectedKeyboard) -> [KeyMapping]? {
        guard let service = keyboardServices().first(where: { $0.1.id == keyboard.id })?.0,
              let value = IOHIDServiceClientCopyProperty(service, Self.userKeyMappingKey) as? [[String: NSNumber]] else {
            return nil
        }
        return value.compactMap { entry in
            guard let from = entry["HIDKeyboardModifierMappingSrc"], let to = entry["HIDKeyboardModifierMappingDst"] else {
                return nil
            }
            return KeyMapping(from: from.uint64Value, to: to.uint64Value)
        }
    }

    private static func property(_ mappings: [KeyMapping]) -> CFArray {
        mappings.map { mapping -> [String: NSNumber] in
            [
                "HIDKeyboardModifierMappingSrc": NSNumber(value: mapping.from),
                "HIDKeyboardModifierMappingDst": NSNumber(value: mapping.to),
            ]
        } as CFArray
    }

    // MARK: - キーボード

    public var keyboards: [ConnectedKeyboard] {
        keyboardServices().map(\.1).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func keyboardServices() -> [(IOHIDServiceClient, ConnectedKeyboard)] {
        guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else {
            return []
        }
        return services.compactMap { service in
            guard IOHIDServiceClientConformsTo(service, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Keyboard)) != 0 else {
                return nil
            }
            func number(_ key: String) -> Int {
                (IOHIDServiceClientCopyProperty(service, key as CFString) as? NSNumber)?.intValue ?? 0
            }
            let name = IOHIDServiceClientCopyProperty(service, kIOHIDProductKey as CFString) as? String
            let id = (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value ?? 0
            return (service, ConnectedKeyboard(
                id: id,
                name: name ?? "名前のないキーボード",
                vendorID: number(kIOHIDVendorIDKey),
                productID: number(kIOHIDProductIDKey)
            ))
        }
    }

    // MARK: - 接続の監視

    /// キーボードの接続と取り外しの監視を始める。
    /// キーボードを接続し直すと個別の設定が消えるので、onKeyboardsChanged で適用し直す
    public func startObservingKeyboards() {
        guard notificationPort == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notificationPort = port
        IONotificationPortSetDispatchQueue(port, .main)

        let callback: IOServiceMatchingCallback = { refcon, iterator in
            HIDKeyMapper.drain(iterator)
            guard let refcon else { return }
            let mapper = Unmanaged<HIDKeyMapper>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { mapper.keyboardsDidChange() }
        }
        // self はアプリの終了まで生きるので、参照カウントを増やさずに渡す
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(port, type, IOServiceMatching("IOHIDEventService"), callback, refcon, &iterator)
            guard result == KERN_SUCCESS else { continue }
            // 既にあるものを読み捨てて、次の通知を受け取れる状態にする
            Self.drain(iterator)
            iterators.append(iterator)
        }
    }

    private nonisolated static func drain(_ iterator: io_iterator_t) {
        while case let object = IOIteratorNext(iterator), object != 0 {
            IOObjectRelease(object)
        }
    }

    private func keyboardsDidChange() {
        // 接続直後はまだイベントシステムに見えていないことがあるので、少し待ってから知らせる
        pendingChange?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.onKeyboardsChanged?() }
        }
        pendingChange = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }
}
