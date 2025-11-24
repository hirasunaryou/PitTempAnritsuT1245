import Foundation

/// BLE 生データから TemperatureFrame を構築するユースケース。
/// - Important: CoreBluetooth などインフラ層に依存せず、シンプルな Data → モデル変換に徹する。
protocol TemperatureIngesting {
    func frames(from data: Data) -> [TemperatureFrame]
    func makeTimeSyncPayload(for date: Date) -> Data
}

struct TemperatureIngestUseCase: TemperatureIngesting {
    private let parser: TemperaturePacketParsing

    init(parser: TemperaturePacketParsing = TemperaturePacketParser()) {
        self.parser = parser
    }

    func frames(from data: Data) -> [TemperatureFrame] {
        parser.parseFrames(data)
    }

    func makeTimeSyncPayload(for date: Date) -> Data {
        parser.buildTIMESet(date: date)
    }
}
