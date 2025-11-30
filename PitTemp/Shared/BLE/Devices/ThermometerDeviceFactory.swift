import Foundation

/// プロファイルに応じたデバイス具象クラスを生成するファクトリ。
struct ThermometerDeviceFactory {
    func make(for profile: BLEDeviceProfile, temperatureUseCase: TemperatureIngesting) -> ThermometerDevice {
        switch profile.key {
        case BLEDeviceProfile.anritsu.key:
            return AnritsuDevice(ingestor: temperatureUseCase)
        case BLEDeviceProfile.tr4.key:
            return TR4Device()
        default:
            return AnritsuDevice(ingestor: temperatureUseCase)
        }
    }
}
