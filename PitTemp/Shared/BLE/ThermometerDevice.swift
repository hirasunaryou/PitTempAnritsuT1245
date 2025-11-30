//  ThermometerDevice.swift
//  PitTemp
//  Role: 複数ベンダーの温度計ごとの接続/通信ロジックを切り出す抽象プロトコル。
//  Note: BluetoothService は CoreBluetooth デリゲートを一元受信し、本プロトコルに委譲する。

import Foundation
import CoreBluetooth

/// ベンダーごとのBLE実装を統一するインターフェイス。
/// - Important: CoreBluetoothのイベントフローに沿って呼ばれる想定なので、
///   クラス実装で状態管理・CRC計算・パケット組み立てを担当する。
protocol ThermometerDevice: AnyObject {
    /// 接続判定に使うBLEプロファイル（スキャン時に紐づけ）
    var profile: BLEDeviceProfile { get }
    /// 現在接続中のPeripheral（BluetoothServiceが保持して注入する）
    var peripheral: CBPeripheral? { get set }
    /// キャラクタリスティック探索完了時の通知。UI更新などはBluetoothService側で行う。
    var onReady: ((CBPeripheral) -> Void)? { get set }
    /// 温度フレームを通知するコールバック。
    var onFrame: ((TemperatureFrame) -> Void)? { get set }
    /// エラー発生時にサービスへ伝達するコールバック。
    var onFailure: ((String) -> Void)? { get set }

    /// 接続開始直後（didConnect）に呼ばれ、サービス探索などを開始する。
    func didConnect(_ peripheral: CBPeripheral)
    /// サービス発見時の処理。
    func didDiscoverServices(_ peripheral: CBPeripheral, error: Error?)
    /// キャラクタリスティック発見時の処理。
    func didDiscoverCharacteristics(for service: CBService, error: Error?)
    /// Notify受信時の処理。
    func didReceiveNotification(from characteristic: CBCharacteristic, data: Data)
    /// 測定開始（必要な場合のみ）
    func startMeasurement()
    /// 切断時に呼ばれる後処理。
    func disconnect(using central: CBCentralManager)
}

extension ThermometerDevice {
    /// デバッグ用: Dataを16進文字列へ整形し、スペース区切りで読みやすく返す。
    func hexString(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
