//
//  DeviceRegistry.swift
//  PitTemp
//

import Foundation

/// 端末の記録（近傍で見つけた・別名・自動再接続フラグ・RSSI・最終見かけ時刻）
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
    /// ID（peripheral.identifier.uuidString）で検索
    func record(for id: String) -> DeviceRecord? {
        known.first(where: { $0.id == id })
    }

    /// 表示名（広告名 or エイリアス）で検索
    func record(forName name: String) -> DeviceRecord? {
        known.first(where: { $0.name == name || $0.alias == name })
    }

    // MARK: - Mutations
    /// スキャンで見かけたときに upsert
    func upsertSeen(id: String, name: String, rssi: Int?) {
        if let idx = known.firstIndex(where: { $0.id == id }) {
            known[idx].name = name
            known[idx].lastSeenAt = Date()
            known[idx].lastRSSI = rssi
        } else {
            known.append(DeviceRecord(
                id: id, name: name, alias: nil, autoConnect: false,
                lastSeenAt: Date(), lastRSSI: rssi
            ))
        }
        save()
    }

    func setAlias(_ alias: String?, for id: String) {
        mutate(id) { $0.alias = alias }
    }

    func setAutoConnect(_ on: Bool, for id: String) {
        mutate(id) { $0.autoConnect = on }
    }

    func forget(id: String) {
        known.removeAll { $0.id == id }
        save()
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

    private func mutate(_ id: String, _ f: (inout DeviceRecord) -> Void) {
        guard let idx = known.firstIndex(where: { $0.id == id }) else { return }
        f(&known[idx])
        save()
    }
}
