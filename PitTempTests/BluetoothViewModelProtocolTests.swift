import Combine
import XCTest
@testable import PitTemp

final class BluetoothViewModelProtocolTests: XCTestCase {
    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func testAutoConnectFlagPropagatesFromService() {
        let service = MockBluetoothService()
        let registry = MockDeviceRegistry()
        let vm = BluetoothViewModel(service: service, registry: registry)
        let expectation = expectation(description: "auto-connect propagates")

        vm.$autoConnectOnDiscover.dropFirst().sink { enabled in
            if enabled { expectation.fulfill() }
        }.store(in: &cancellables)

        service.autoConnectOnDiscover = true

        wait(for: [expectation], timeout: 1.0)
    }

    func testDisplayNamePrefersAlias() {
        let service = MockBluetoothService()
        let registry = MockDeviceRegistry()
        registry.known = [DeviceRecord(id: "abc", name: "AnritsuM-01", alias: "Phoenix", autoConnect: false, lastSeenAt: Date(), lastRSSI: nil)]
        let vm = BluetoothViewModel(service: service, registry: registry)
        let scanned = ScannedDevice(id: "abc", name: "AnritsuM-01", rssi: -50, lastSeenAt: Date())

        XCTAssertEqual(vm.displayName(for: scanned), "Phoenix (AnritsuM-01)")
    }
}
