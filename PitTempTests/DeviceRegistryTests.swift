import XCTest
@testable import PitTemp

final class DeviceRegistryTests: XCTestCase {

    /// UserDefaults を叩かずにロードできることを確認する。
    func testLoadsSeedRecordsFromInjectedStore() async {
        let seed = DeviceRecord(id: "A", name: "Seed", alias: nil, autoConnect: false, lastSeenAt: nil, lastRSSI: nil)
        let store = InMemoryDeviceRegistryStore(seed: [seed])
        let registry = DeviceRegistry(store: store)

        // Published なので main に乗ってから反映される。短い待機で UI 同期を模倣。
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(registry.known.first?.id, seed.id)
    }

    /// upsert が main スレッドで保存されることを確認し、保存先の配列も検証する。
    func testUpsertSavesThroughStore() async {
        let store = InMemoryDeviceRegistryStore()
        let registry = DeviceRegistry(store: store)
        registry.upsertSeen(id: "B", name: "Beacon", rssi: -50)

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(store.lastSavedRecords.count, 1)
        XCTAssertEqual(store.lastSavedRecords.first?.name, "Beacon")
        XCTAssertEqual(store.lastSavedRecords.first?.lastRSSI, -50)
    }

    func testJSONStoreReadsAndWritesFile() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("registry.json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let record = DeviceRecord(id: "json", name: "JSON", alias: "Alias", autoConnect: true, lastSeenAt: Date(), lastRSSI: -42)
        let store = JSONDeviceRegistryStore(url: tempURL)
        store.saveRecords([record])

        let loaded = store.loadRecords()
        XCTAssertEqual(loaded.first?.id, record.id)
        XCTAssertEqual(loaded.first?.alias, record.alias)
    }

    /// UserDefaults を用いた既定ストアが round-trip 保存/復元できることを確認する。
    /// - Note: 標準の key を直接使うため、試験終了後に掃除しておく。
    func testUserDefaultsStorePersistsAndLoads() async throws {
        let defaults = UserDefaults.standard
        let key = "ble.deviceRegistry.v1"
        defaults.removeObject(forKey: key)

        // 事前に JSON を投入し、初期ロードが @Published known へ反映されるか検証。
        let seeded = [DeviceRecord(id: "seed", name: "Seed", alias: "Pilot", autoConnect: false, lastSeenAt: nil, lastRSSI: nil)]
        defaults.set(try JSONEncoder().encode(seeded), forKey: key)

        let registry = DeviceRegistry() // 既定の UserDefaultsDeviceRegistryStore を利用
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(registry.record(for: "seed")?.alias, "Pilot")

        // 別名を変更 → UserDefaults 内部の JSON が更新されることを確認。
        registry.setAlias("Driver", for: "seed")
        try? await Task.sleep(nanoseconds: 50_000_000)

        let data = try XCTUnwrap(defaults.data(forKey: key))
        let decoded = try JSONDecoder().decode([DeviceRecord].self, from: data)
        XCTAssertEqual(decoded.first?.alias, "Driver")

        defaults.removeObject(forKey: key)
    }
}
