import Foundation
import CoreBluetooth

/// T\&D おんどとり TR75A2 専用の現在値取得処理を行う ThermometerDevice。
/// - Note: TR4 シリーズと異なり、WriteWithoutResponse + Notify だけで完結する簡素なプロトコル。
final class TR75A2Device: NSObject, ThermometerDevice {
    let profile: BLEDeviceProfile = .tr75a2
    let requiresPollingForRealtime: Bool = true

    /// どちらのチャンネルを UI へ流すかを示す。1 または 2 を想定。
    /// - Note: TR75A2 は Ch1/Ch2 の2系統を持つため、UI 側からの指示を保存しておく。
    private var selectedChannel: Int

    private var peripheral: CBPeripheral?
    private var ioCharacteristic: CBCharacteristic?

    /// TR7A2/A の送信順序（ブレーク→待機→SOH）を崩さないようにするための専用キュー。
    /// - Important: CoreBluetooth のコールバックキューと同じ serial queue で扱うことで、
    ///   コマンドとウェイクアップシグナルの順序が逆転しないようにしている。
    private let commandQueue = DispatchQueue(label: "BLE.TR75A2.CommandQueue")

    var onFrame: ((TemperatureFrame) -> Void)?
    var onReady: (() -> Void)?

    init(channel: Int = 1) {
        // UI 側でチャンネルを切り替えられるよう、イニシャライザで受け取る
        // 「想定外の値なら Ch1 に丸める」という防御的実装にしておく。
        self.selectedChannel = (channel == 2) ? 2 : 1
    }

    /// ThermometerDevice プロトコル経由で呼ばれるチャンネル設定用フック。
    func setInputChannel(_ channel: Int) {
        // 仕様上 Ch1/Ch2 の 2 択なので、無効値は Ch1 に丸める。
        selectedChannel = (channel == 2) ? 2 : 1
        Logger.shared.log("TR75A2 channel set → Ch\(selectedChannel)", category: .bleSend)
    }

    // MARK: - ThermometerDevice
    func bind(peripheral: CBPeripheral) {
        self.peripheral = peripheral
    }

    func connect() {
        // TR75A2 は接続直後に追加のハンドシェイクは不要。
    }

    func discoverCharacteristics(on peripheral: CBPeripheral, service: CBService) {
        peripheral.discoverCharacteristics([profile.notifyCharUUID, profile.writeCharUUID], for: service)
    }

    func didDiscoverCharacteristics(error: Error?) {
        guard error == nil, let service = peripheral?.services?.first(where: { $0.uuid == profile.serviceUUID }) else { return }
        service.characteristics?.forEach { ch in
            if ch.uuid == profile.notifyCharUUID { ioCharacteristic = ch }
        }

        // Notify を有効化し、準備完了を通知
        if let notify = ioCharacteristic {
            Logger.shared.log("TR75A2 enabling notify on Data Line (\(notify.uuid.uuidString))", category: .bleSend)
            peripheral?.setNotifyValue(true, for: notify)
        }
        onReady?()
    }

    func didUpdateValue(for characteristic: CBCharacteristic, data: Data) {
        guard characteristic.uuid == profile.notifyCharUUID else { return }
        Logger.shared.log("TR75A2 RX ← \(data.hexString)", category: .bleReceive)
        parseResponse(data)
    }

    func didWriteValue(for characteristic: CBCharacteristic, error: Error?) {
        if let error { Logger.shared.log("TR75A2 write error: \(error.localizedDescription)", category: .bleSend) }
    }

    func setDeviceTime(_ date: Date) {
        // プロトコル資料に時刻同期コマンドがないため、ここでは何もしない。
    }

    func startMeasurement() {
        guard let ioCharacteristic else { return }

        // TR7A2/A シリーズはスリープ解除のため、SOH コマンド直前にブレーク信号 (0x00) を送る必要がある。
        // さらに、通知が無効なまま送信するとレスポンスを受け取れないため、事前に Notify を確認する。
        if !ioCharacteristic.isNotifying {
            // 念のためここでも通知を有効化し、次回以降の送信で確実に受信できるようにする。
            Logger.shared.log("TR75A2 notify was off, enabling before sending 0x33", category: .bleSend)
            peripheral?.setNotifyValue(true, for: ioCharacteristic)
            return
        }

        // 0x33 現在値コマンドをブレーク信号付きで送信する。
        sendTR7A2Command(frame: buildCurrentValueCommand(), characteristic: ioCharacteristic)
    }

    func disconnect() {
        peripheral = nil
        ioCharacteristic = nil
    }
}

// MARK: - Private helpers
private extension TR75A2Device {
    /// 0x33 現在値取得コマンドを組み立てる。
    /// - Important: CRC16(CCITT)のみ Big Endian で付与する。
    func buildCurrentValueCommand() -> Data {
        // TR7A2/A の「現在値・警報状態取得」は 01 33 00 04 00 + CRC16(D1 A0) で送る。
        // expectedDataLength はレスポンスで返ってくるデータ部のバイト数（Ch1/Ch2 合計 4 バイト）。
        return TR7A2CommandBuilder.buildFrame(command: 0x33,
                                              expectedDataLength: 0x0004,
                                              payload: Data([0x00]))
    }

    /// TR75A2 のレスポンスを解釈し、選択チャンネルの温度を TemperatureFrame として通知する。
    func parseResponse(_ payload: Data) {
        // 1) 最低限のヘッダ検証と想定サイズ(ヘッダ5 + データ長)チェック
        guard payload.count >= 9, payload[0] == 0x01, payload[1] == 0x33 else { return }
        let dataLength = Int(UInt16(high: payload[3], low: payload[4]))
        let totalLength = 5 + dataLength
        guard payload.count >= totalLength else { return }

        // 2) ステータス 0x06（成功）を前提に処理。それ以外は早期リターン。
        guard payload[2] == 0x06 else { return }

        // 3) チャンネルごとの RawData を Little Endian で取得（オフセット 5,7）
        let ch1Raw = Int16(bitPattern: UInt16(low: payload[5], high: payload[6]))
        let ch2Raw = Int16(bitPattern: UInt16(low: payload[7], high: payload[8]))

        // 4) スケール変換: RawData(0.1℃単位, +1000 オフセット) → ℃
        let channelValue: Double
        if selectedChannel == 2 {
            channelValue = (Double(ch2Raw) - 1000.0) / 10.0
        } else {
            channelValue = (Double(ch1Raw) - 1000.0) / 10.0
        }

        onFrame?(TemperatureFrame(time: Date(), deviceID: selectedChannel, value: channelValue, status: nil))
    }

    /// 仕様書 4.5 の「ブレーク信号 → 20-100ms 待機 → SOH コマンド送信」を実装する。
    /// - Parameters:
    ///   - frame: CRC 付きの SOH コマンドフレーム（事前に `TR7A2CommandBuilder` で組み立てる）。
    ///   - characteristic: TR75A2 の書き込み/Notify 兼用キャラクタリスティック。
    func sendTR7A2Command(frame: Data, characteristic: CBCharacteristic) {
        // 1) ブレーク信号として Null(0x00) を送信。TR75A2 の省電力スリープを起こす。
        let wakeSignal = Data([0x00])
        commandQueue.async { [weak self] in
            guard let self else { return }
            Logger.shared.log("TR75A2 TX (wake) → \(wakeSignal.hexString)", category: .bleSend)
            self.peripheral?.writeValue(wakeSignal, for: characteristic, type: .withoutResponse)

            // 2) 20〜100ms の待機。仕様書推奨値に合わせて 50ms ディレイを挿入する。
            self.commandQueue.asyncAfter(deadline: .now() + .milliseconds(50)) { [weak self] in
                guard let self else { return }

                // 3) 本体コマンドを送信。Wake 後なのでデバイスが確実に認識できる。
                Logger.shared.log("TR75A2 TX → \(frame.hexString)", category: .bleSend)
                self.peripheral?.writeValue(frame, for: characteristic, type: .withoutResponse)
            }
        }
    }
}

private extension UInt16 {
    init(low: UInt8, high: UInt8) { self = UInt16(low) | (UInt16(high) << 8) }
    init(high: UInt8, low: UInt8) { self = UInt16(high) << 8 | UInt16(low) }
}
