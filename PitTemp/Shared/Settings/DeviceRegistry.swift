//
//  DeviceRegistry.swift
//  PitTemp

import Foundation

/// ストレージの抽象化。
/// - 目的: 保存先を差し替えられるようにし、単体テストや将来の Keychain/ファイル保存に備える。
protocol DeviceRegistryStore {
    /// 保存済みのレコード一覧をロードする。
    /// - 戻り値: 何も保存されていなければ空配列。
    func loadRecords() -> [DeviceRecord]
    /// レコード一覧を永続化する。
    /// - 引数の配列を丸ごと保存することを想定。
    func saveRecords(_ records: [DeviceRecord])
}

/// UserDefaults を使った既定の保存先。
final class UserDefaultsDeviceRegistryStore: DeviceRegistryStore {
    private let storeKey = "ble.deviceRegistry.v1"

    func loadRecords() -> [DeviceRecord] {
        guard let data = UserDefaults.standard.data(forKey: storeKey) else { return [] }
        return (try? JSONDecoder().decode([DeviceRecord].self, from: data)) ?? []
    }

    func saveRecords(_ records: [DeviceRecord]) {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }
}

/// JSON ファイルへの保存を行うストア。UserDefaults を使えない環境での永続化用。
final class JSONDeviceRegistryStore: DeviceRegistryStore {
    private let url: URL

    init(url: URL) {
        self.url = url
    }

    func loadRecords() -> [DeviceRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([DeviceRecord].self, from: data)) ?? []
    }

    func saveRecords(_ records: [DeviceRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// 端末の記録（近傍で見かけた・別名・自動再接続・RSSI・最終見かけ時刻）
struct DeviceRecord: Identifiable, Codable, Equatable {
    let id: String               // peripheral.identifier.uuidString
    var name: String             // 広告名（例: AnritsuM-P03953）
    var alias: String?           // ニックネーム（任意）
    var autoConnect: Bool        // 起動時に自動再接続するか
    var lastSeenAt: Date?        // 直近で見かけた時刻
    var lastRSSI: Int?           // 直近で見かけたRSSI（dBm）
}

/// 既知デバイスのレジストリ。UserDefaults 以外にも切り替え可能。
final class DeviceRegistry: ObservableObject, DeviceRegistrying {
    @Published private(set) var known: [DeviceRecord] = []

    private let store: DeviceRegistryStore

    /// - Parameter store: デフォルトは UserDefaults だが、テスト用にインメモリ保存などへ差し替えられる。
    init(store: DeviceRegistryStore = UserDefaultsDeviceRegistryStore()) {
        self.store = store
        load()
    }

    // MARK: - Query
    func record(for id: String) -> DeviceRecord? {
        known.first { $0.id == id }
    }

    func record(forName name: String) -> DeviceRecord? {
        known.first { $0.name == name || $0.alias == name }
    }

    // MARK: - Mutations
    func upsertSeen(id: String, name: String, rssi: Int?) {
        let now = Date()
        DispatchQueue.main.async {
            if let idx = self.known.firstIndex(where: { $0.id == id }) {
                self.known[idx].name = name
                self.known[idx].lastSeenAt = now
                self.known[idx].lastRSSI = rssi
            } else {
                self.known.append(DeviceRecord(
                    id: id, name: name, alias: nil, autoConnect: false,
                    lastSeenAt: now, lastRSSI: rssi
                ))
            }
            self.save()
        }
    }

    func setAlias(_ alias: String?, for id: String) {
        mutate(id) { rec in
            var r = rec
            r.alias = alias
            return r
        }
    }

    func setAutoConnect(_ on: Bool, for id: String) {
        mutate(id) { rec in
            var r = rec
            r.autoConnect = on
            return r
        }
    }

    func forget(id: String) {
        DispatchQueue.main.async {
            self.known.removeAll { $0.id == id }
            self.save()
        }
    }

    /// Main スレッドで「置換」する方式（inout ではなく変換を返す）
    private func mutate(_ id: String, transform: @escaping (DeviceRecord) -> DeviceRecord) {
        DispatchQueue.main.async {
            guard let idx = self.known.firstIndex(where: { $0.id == id }) else { return }
            self.known[idx] = transform(self.known[idx])
            self.save()
        }
    }

    // MARK: - Persistence
    private func load() {
        // コンストラクタで一度だけ読み込む。UIスレッドで Published を更新するため main で実行。
        DispatchQueue.main.async {
            self.known = self.store.loadRecords()
        }
    }

    private func save() {
        // 保存先はプロトコルに委ねることで、UserDefaults/ファイル/モックを容易に差し替え。
        store.saveRecords(known)
    }
}
