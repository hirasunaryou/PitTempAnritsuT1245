import Combine
import Foundation

/// ViewModel/UseCase をユニットテストするためのシンプルな Bluetooth モック群。
final class MockBluetoothService: BluetoothServicing {
    @Published var connectionState: ConnectionState = .idle
    @Published var deviceName: String? = nil
    @Published var currentPeripheralID: String? = nil
    @Published var scanned: [ScannedDevice] = []
    @Published var latestTemperature: Double? = nil
    @Published var autoConnectOnDiscover: Bool = false
    @Published var notifyCountUI: Int = 0
    @Published var notifyHz: Double = 0
    @Published var tr4aState: TR4ADeviceState = TR4ADeviceState()
    var registry: DeviceRegistrying?
    var connectionStatePublisher: AnyPublisher<ConnectionState, Never> { $connectionState.eraseToAnyPublisher() }
    var scannedPublisher: AnyPublisher<[ScannedDevice], Never> { $scanned.eraseToAnyPublisher() }
    var deviceNamePublisher: AnyPublisher<String?, Never> { $deviceName.eraseToAnyPublisher() }
    var currentPeripheralIDPublisher: AnyPublisher<String?, Never> { $currentPeripheralID.eraseToAnyPublisher() }
    var latestTemperaturePublisher: AnyPublisher<Double?, Never> { $latestTemperature.eraseToAnyPublisher() }
    var autoConnectPublisher: AnyPublisher<Bool, Never> { $autoConnectOnDiscover.eraseToAnyPublisher() }
    var notifyHzPublisher: AnyPublisher<Double, Never> { $notifyHz.eraseToAnyPublisher() }
    var notifyCountPublisher: AnyPublisher<Int, Never> { $notifyCountUI.eraseToAnyPublisher() }
    var tr4aStatePublisher: AnyPublisher<TR4ADeviceState, Never> { Just(tr4aState).eraseToAnyPublisher() }

    private let subject = PassthroughSubject<TemperatureFrame, Never>()
    var temperatureFrames: AnyPublisher<TemperatureFrame, Never> { subject.eraseToAnyPublisher() }

    var didStartScan = false
    var didStopScan = false
    var didDisconnect = false
    var connectedID: String?

    func startScan() { didStartScan = true }
    func stopScan() { didStopScan = true }
    func connect(deviceID: String) { connectedID = deviceID }
    func disconnect() { didDisconnect = true }
    func setDeviceTime(to date: Date) { /* no-op for tests */ }
    func setPreferredIDs(_ ids: Set<String>) { /* record if needed */ }
    func requestTR4ASettings() {}
    func updateTR4ARecording(interval: UInt8, endless: Bool) {}
    func startTR4ARecording() {}
    func stopTR4ARecording() {}
    func sendTR4APasscode(_ code: String) {}

    /// テスト側から任意のフレームを流し込むためのヘルパー。
    func emit(frame: TemperatureFrame) { subject.send(frame) }
}

final class MockDeviceRegistry: DeviceRegistrying {
    @Published var known: [DeviceRecord] = []

    func record(for id: String) -> DeviceRecord? { known.first { $0.id == id } }
    func record(forName name: String) -> DeviceRecord? { known.first { $0.name == name || $0.alias == name } }
    func upsertSeen(id: String, name: String, rssi: Int?) {
        known.append(DeviceRecord(id: id, name: name, alias: nil, autoConnect: false, lastSeenAt: Date(), lastRSSI: rssi))
    }
    func setAlias(_ alias: String?, for id: String) { /* simplified */ }
    func setAutoConnect(_ on: Bool, for id: String) { /* simplified */ }
    func forget(id: String) { known.removeAll { $0.id == id } }
}

final class MockTemperatureIngestUseCase: TemperatureIngesting {
    var framesToReturn: [TemperatureFrame] = []
    var lastDate: Date?

    func frames(from data: Data) -> [TemperatureFrame] { framesToReturn }

    func makeTimeSyncPayload(for date: Date) -> Data {
        lastDate = date
        return Data("MOCK".utf8)
    }
}
