# TR45/TR4A BLE Support Notes

この文書は PitTemp における TR45（TR4A シリーズ）対応の概要です。実装を読み解く際の地図として利用してください。

## 接続とサービス探索
- 使用サービス UUID: `6E400001-B5A3-F393-E0A9-E50E24DCCA42`（T&D SPP/Nordic UART）。
- 通知特性 (Data Line RX): `6E400003-B5A3-F393-E0A9-E50E24DCCA42`。
- 書き込み特性 (Data Line TX): `6E400002-B5A3-F393-E0A9-E50E24DCCA42`。
- `ConnectionManager` はサービス内の全 characteristic を取得し、UUID が一致しない場合も **notify / write プロパティを持つものへフェールバック** します。これは端末ごとに広告プロパティが異なり、notify を要求すると「request is not supported」になる個体が存在するためです。

## 現在温度の取得（SOH 0x33/0x00）
- `BluetoothService.startTR4APollingIfNeeded` が 1 秒以上の間隔でポーリング。
- 送信フロー: `0x00` ブレーク → 20〜100ms 待機 → SOH フレーム送信。
- コマンドフレーム: `01 33 00 04 00 00 00 00 00 CRC16`（CRC16-CCITT, Big Endian）。
- 応答の 5-6 バイト目を Int16 として `(value - 1000) / 10` を温度[℃]に変換。

## 記録間隔の取得と更新
- 設定取得: SOH `0x85` で 64byte の設定テーブルを受信。先頭 2byte (LE) が記録間隔（秒）。
- 設定更新: 取得したテーブルを基に先頭 2byte を書き換え、SOH `0x3C` で書き戻す。
- `BluetoothService.updateTR4ARecordInterval` が UI からの要求を受け取り、`applyTR4AIntervalUpdate` で送信します。

## 節電とポーリング間隔
- `setTR4APollingInterval` でポーリング周期を動的に変更可能。0 を指定するとポーリングを停止し、無通信による自動切断までの 1 分を活用して省電力にできます。

## 既知の留意点
- TR4A は 1 分間無通信で切断されるため、ポーリング停止時は UI 側で再接続を考慮してください。
- 特性プロパティが広告と一致しない個体があるため、notify/write が見つからない場合はエラーとして UI に伝搬します。
