import XCTest
@testable import PitTemp

@MainActor
final class SettingsStoreTests: XCTestCase {

    func testLoadsSeedValuesFromBackingStore() {
        let backing = InMemorySettingsStoreBacking(seed: [
            "pref.durationSec": 40,
            "pref.advanceWithReturn": false,
            "pref.metaKeyword.track": "test1, test2"
        ])
        let store = SettingsStore(store: backing)

        XCTAssertEqual(store.autoStopLimitSec, 40)
        XCTAssertFalse(store.advanceWithReturn)
        XCTAssertEqual(store.metaVoiceKeywords(for: .track), ["test1", "test2"])
    }

    func testPersistsUpdatedValues() {
        let backing = InMemorySettingsStoreBacking()
        let store = SettingsStore(store: backing)

        store.autoStopLimitSec = 99
        store.zoneOrderEnum = .out_cl_in

        XCTAssertEqual(backing.rawValue(forKey: "pref.durationSec") as? Int, 99)
        XCTAssertEqual(backing.rawValue(forKey: "pref.zoneOrder") as? Int, SettingsStore.ZoneOrder.out_cl_in.rawValue)
    }
}
