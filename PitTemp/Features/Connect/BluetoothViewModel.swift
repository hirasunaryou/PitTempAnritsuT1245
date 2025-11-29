import Combine
import Foundation

/// ViewModel that centralizes BluetoothService interactions for SwiftUI views.
/// - Note: Views bind only to this object so cancellation and MainActor hops
///   stay in one place instead of scattering across multiple screens.
@MainActor
final class BluetoothViewModel: ObservableObject {
    // Published UI-facing state mirrors BluetoothService but is kept on the main actor.
    @Published private(set) var connectionState: ConnectionState
    @Published private(set) var scanned: [ScannedDevice]
    @Published private(set) var deviceName: String?
    @Published private(set) var autoConnectOnDiscover: Bool
    @Published private(set) var latestTemperature: Double?
    @Published private(set) var bleDebugLog: [BLEDebugLogEntry]
    // Debug metrics that were previously formatted inside the View.
    @Published private(set) var notifyHzText: String = "Hz: --"
    @Published private(set) var notifyCountText: String = "N: --"

    private let service: any BluetoothServicing
    private let registry: any DeviceRegistrying
    private var cancellables: Set<AnyCancellable> = []

    init(service: any BluetoothServicing, registry: any DeviceRegistrying) {
        self.service = service
        self.registry = registry
        // Seed with the current service state so the UI renders instantly.
        connectionState = service.connectionState
        scanned = service.scanned
        deviceName = service.deviceName
        autoConnectOnDiscover = service.autoConnectOnDiscover
        latestTemperature = service.latestTemperature
        bleDebugLog = service.bleDebugLog

        bindServiceState()
    }

    deinit {
        cancellables.forEach { $0.cancel() }
    }

    // MARK: - Public computed helpers

    var isScanning: Bool { connectionState == .scanning }

    /// Sort the scanned devices by RSSI then name so the list stays stable.
    func sortedScannedDevices() -> [ScannedDevice] {
        scanned.sorted { a, b in
            if a.rssi != b.rssi { return a.rssi > b.rssi }
            return a.name < b.name
        }
    }

    /// Display name picks the registry alias when available.
    func displayName(for dev: ScannedDevice) -> String {
        if let rec = registry.record(forName: dev.name), let alias = rec.alias, !alias.isEmpty {
            return "\(alias) (\(dev.name))"
        }
        return dev.name
    }

    /// Connected device alias for the header.
    func connectedLabel(for name: String) -> String? {
        guard let rec = registry.record(forName: name) else { return nil }
        return (rec.alias?.isEmpty == false) ? rec.alias! : rec.name
    }

    /// Human-readable relative time for the scan list.
    func relativeTimeDescription(since date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 2 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        return "\(minutes)m ago"
    }

    // MARK: - Actions

    /// Start scanning with the service while keeping the UI in sync.
    func startScan() {
        service.startScan()
    }

    /// Stop scanning when the toolbar button requests it.
    func stopScan() {
        service.stopScan()
    }

    /// Connect to a device from the picker.
    func connect(to deviceID: String) {
        service.autoConnectOnDiscover = false // Explicit connect should not auto-hop.
        autoConnectOnDiscover = false
        service.connect(deviceID: deviceID)
    }

    /// Disconnect from the current peripheral.
    func disconnect() {
        service.disconnect()
    }

    /// Clear the BLE debug log so the next repro is easier to read.
    func clearDebugLog() { service.clearDebugLog() }

    /// Update TR4A registration code (パスコード) for passcode-locked devices.
    func updateTR4ARegistrationCode(_ code: String) { service.setTR4ARegistrationCode(code) }

    /// Update the auto-connect flag from Settings or a Toggle.
    func updateAutoConnect(isEnabled: Bool) {
        service.autoConnectOnDiscover = isEnabled
        autoConnectOnDiscover = isEnabled
    }

    /// Apply the registry-specified preferred IDs and app-wide auto-connect flag.
    func applyPreferencesFromRegistry(autoConnectEnabled: Bool) {
        updateAutoConnect(isEnabled: autoConnectEnabled)
        let preferred = Set(registry.known.filter { $0.autoConnect }.map { $0.id })
        service.setPreferredIDs(preferred)
    }

    // MARK: - Private

    /// Subscribe to BluetoothService so views receive MainActor updates only from here.
    private func bindServiceState() {
        service.connectionStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.connectionState = state
            }
            .store(in: &cancellables)

        service.scannedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.scanned = devices
            }
            .store(in: &cancellables)

        service.deviceNamePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] name in
                self?.deviceName = name
            }
            .store(in: &cancellables)

        service.latestTemperaturePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] temperature in
                self?.latestTemperature = temperature
            }
            .store(in: &cancellables)

        service.autoConnectPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.autoConnectOnDiscover = enabled
            }
            .store(in: &cancellables)

        // Debug metrics stay formatted here to keep Views presentational only.
        service.notifyHzPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hz in
                self?.notifyHzText = String(format: "Hz: %.1f", hz)
            }
            .store(in: &cancellables)

        service.notifyCountPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.notifyCountText = "N: \(count)"
            }
            .store(in: &cancellables)

        service.bleDebugLogPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entries in
                self?.bleDebugLog = entries
            }
            .store(in: &cancellables)
    }
}
