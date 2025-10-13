//
//  DeviceRegistry.swift
//  PitTemp

import Foundation

/// 端末の記録（近傍で見かけた・別名・自動再接続・RSSI・最終見かけ時刻）
struct DeviceRecord: Identifiable, Codable, Equatable {
    let id: String               // peripheral.identifier.uuidString
    var name: String             // 広告名（例: AnritsuM-P03953）
    var alias: String?           // ニックネーム（任意）
    var autoConnect: Bool        // 起動時に自動再接続するか
    var lastSeenAt: Date?        // 直近で見かけた時刻
    var lastRSSI: Int?           // 直近で見かけたRSSI（dBm）
}

/// 既知デバイスのレジストリ。UserDefaultsへJSON保存。
final class DeviceRegistry: ObservableObject {
    @Published private(set) var known: [DeviceRecord] = []

    private let storeKey = "ble.deviceRegistry.v1"

    init() { load() }

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
        guard let data = UserDefaults.standard.data(forKey: storeKey) else { return }
        if let arr = try? JSONDecoder().decode([DeviceRecord].self, from: data) {
            known = arr
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(known) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }
}
