import Foundation
import CoreBluetooth

/// T\&D おんどとり TR75A2 専用の現在値取得処理を行う ThermometerDevice。
/// - Note: TR4 シリーズと異なり、WriteWithoutResponse + Notify だけで完結する簡素なプロトコル。
final class TR75A2Device: NSObject, ThermometerDevice {
    let profile: BLEDeviceProfile = .tr75a2
    let requiresPollingForRealtime: Bool = true

    /// どちらのチャンネルを UI へ流すかを示す。1 または 2 を想定。
    private var selectedChannel: Int

    private var peripheral: CBPeripheral?
    private var ioCharacteristic: CBCharacteristic?
    private var isNotifyReady = false

    var onFrame: ((TemperatureFrame) -> Void)?
    var onReady: (() -> Void)?

    init(channel: Int = 1) {
        // UI 側でチャンネルを切り替えられるよう、イニシャライザで受け取る
        self.selectedChannel = channel
    }

    /// 外部からチャンネルを変更するための簡易セッター。
    func setChannel(_ channel: Int) {
        selectedChannel = (channel == 2) ? 2 : 1
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
            // 仕様では Notify 有効化後にコマンド送信する必要があるため、まず通知を起動する。
            peripheral?.setNotifyValue(true, for: notify)

            // すでに通知状態になっている場合は即座に準備完了を伝える。通常は didUpdateNotificationState で遷移。
            if notify.isNotifying {
                isNotifyReady = true
                onReady?()
            }
        }
    }

    func didUpdateValue(for characteristic: CBCharacteristic, data: Data) {
        guard characteristic.uuid == profile.notifyCharUUID else { return }
        Logger.shared.log("TR75A2 RX ← \(data.hexString)", category: .bleReceive)
        parseResponse(data)
    }

    func didWriteValue(for characteristic: CBCharacteristic, error: Error?) {
        if let error { Logger.shared.log("TR75A2 write error: \(error.localizedDescription)", category: .bleSend) }
    }

    func didUpdateNotificationState(for characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == profile.notifyCharUUID else { return }

        if let error {
            Logger.shared.log("TR75A2 notify state error: \(error.localizedDescription)", category: .bleReceive)
            return
        }

        // 通知が有効化されたことを確認した上で、計測リクエストを開始する。
        isNotifyReady = characteristic.isNotifying
        if isNotifyReady { onReady?() }
    }

    func setDeviceTime(_ date: Date) {
        // プロトコル資料に時刻同期コマンドがないため、ここでは何もしない。
    }

    func startMeasurement() {
        guard let ioCharacteristic else { return }

        // ブレーク信号送信前に Notify が有効か確認。未準備ならスキップして次のポーリングに任せる。
        guard isNotifyReady else {
            Logger.shared.log("TR75A2 notify not ready; skip startMeasurement", category: .bleSend)
            return
        }

        // 仕様書 4.5: ブレーク信号として Null(0x00) を 1 バイト送る。Write Without Response が推奨。
        let breakSignal = Data([0x00])
        Logger.shared.log("TR75A2 TX (break) → \(breakSignal.hexString)", category: .bleSend)
        peripheral?.writeValue(breakSignal, for: ioCharacteristic, type: .withoutResponse)

        // 20〜100ms の待機が求められている。実装では 50ms の遅延で確実に Wake-up を挟む。
        usleep(50_000)

        // ブレーク後に本来の SOH コマンドを送信する。CRC 生成は既存ロジックを流用。
        let command = buildCurrentValueCommand()
        Logger.shared.log("TR75A2 TX → \(command.hexString)", category: .bleSend)
        peripheral?.writeValue(command, for: ioCharacteristic, type: .withoutResponse)
    }

    func disconnect() {
        peripheral = nil
        ioCharacteristic = nil
        isNotifyReady = false
    }
}

// MARK: - Private helpers
private extension TR75A2Device {
    /// 0x33 現在値取得コマンドを組み立てる。
    /// - Important: CRC16(CCITT)のみ Big Endian で付与する。
    func buildCurrentValueCommand() -> Data {
        var frame = Data([0x01, 0x33, 0x00, 0x04, 0x00])
        let crc = crc16CCITT(frame)
        // Big Endian で上位→下位の順に格納
        frame.append(UInt8((crc >> 8) & 0xFF))
        frame.append(UInt8(crc & 0xFF))
        return frame
    }

    /// TR75A2 のレスポンスを解釈し、選択チャンネルの温度を TemperatureFrame として通知する。
    func parseResponse(_ payload: Data) {
        // 1) 最低限のヘッダ検証と想定サイズ(ヘッダ5 + データ長)チェック
        guard payload.count >= 9, payload[0] == 0x01, payload[1] == 0x33 else { return }
        let dataLength = Int(UInt16(low: payload[3], high: payload[4]))
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

    /// CRC16-CCITT (poly 0x1021, init 0x0000) を計算する。資料のC実装をSwiftへ移植。
    func crc16CCITT(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0x0000
        for byte in data {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if crc & 0x8000 != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc = crc << 1
                }
            }
        }
        return crc
    }
}

private extension UInt16 {
    init(low: UInt8, high: UInt8) { self = UInt16(low) | (UInt16(high) << 8) }
}
