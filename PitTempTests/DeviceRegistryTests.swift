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
}
