# TR45/TR4A BLE Support Notes

この文書は PitTemp における TR45（TR4A シリーズ）対応の概要です。実装を読み解く際の地図として利用してください。

## 接続とサービス探索
- 使用サービス UUID: `6E400001-B5A3-F393-E0A9-E50E24DCCA42`（T&D SPP/Nordic UART）。
- 通知特性 (Data Line RX): 実機では `6E400004-...` または `6E400006-...` が notify を持つケースが多い。
- 書き込み特性 (Data Line TX): `6E400007-...`（writeNR）や `6E400003-...`（writeNR）、`6E400002-...`（write）を状況に応じて利用。
- `ConnectionManager` はサービス内の全 characteristic を取得し、**通知系はすべて setNotifyValue(true) で有効化**。優先順は `0x0004`→`0x0006`→プロファイル指定、書き込みは writeNR を優先しつつプロパティが一致するものへフェールバックします。

## 現在温度の取得（SOH 0x33/0x00）
- `BluetoothService.startTR4APollingIfNeeded` が 1 秒以上の間隔でポーリング。
- 送信フロー: `0x00` ブレーク → 20〜100ms 待機 → SOH フレーム送信。
- コマンドフレーム: `01 33 00 04 00 00 00 00 00 CRC16`（CRC-16/XMODEM 初期値0x0000, Big Endian）。
- 応答の 5-6 バイト目を Int16 として `(value - 1000) / 10` を温度[℃]に変換。

## 記録間隔の取得と更新
- 設定取得: SOH `0x85` で 64byte の設定テーブルを受信。先頭 2byte (LE) が記録間隔（秒）。
- 設定更新: 取得したテーブルを基に先頭 2byte を書き換え、SOH `0x3C` で書き戻す。
- `BluetoothService.updateTR4ARecordInterval` が UI からの要求を受け取り、`applyTR4AIntervalUpdate` で送信します。

## 節電とポーリング間隔
- `setTR4APollingInterval` でポーリング周期を動的に変更可能。0 を指定するとポーリングを停止し、無通信による自動切断までの 1 分を活用して省電力にできます。

## デバッグログ
- Settings > Bluetooth > BLE Debug Log で **サービス/特性一覧、送信コマンド、切断理由** を時系列で確認できます。
- ログは 200 件でローテーションし、ShareLink でテキストエクスポートも可能です。現場で「どの UUID が通知/書き込みを持っているか」を切り分ける際に使ってください。
- Anritsu 用の時刻同期コマンドは TR4A では未対応のため、初期接続時に TR4A へは送信しない仕様です（MTU 分割とフォーマット差異があるため）。
- 受信側は `didUpdateValueFor` で **CRC/長さを問わず生データを hex で必ず記録**。CRC 不一致や短すぎるフレームは警告としてログに残し、失敗理由を追跡しやすくしています。

## 通知受信とパースの流れ
- `didUpdateValueFor` で **受信チャンクを16進ログ付きで必ず記録**。
- TR4A は 20B チャンクをまとめる必要があるため、`BluetoothService.processTR4ANotification` が SOH 先頭を探して 1 フレーム（5+len+CRC）に組み立てます。
- 組み上がったフレームは `processTR4AFrame` で `cmd/status/len/payload` をログ化し、`TemperaturePacketParser` で 0x33 ステータス 0x06 を温度に変換します。

## 登録コード(0x76)によるロック解除
- TR4A 本体にパスコードロックがある場合、0x33 応答ステータスが `0x0F (REFUSE)` になる。
- Settings > Bluetooth に登録コード入力欄を追加。**印字されている 8 桁の数字列を「16進の32bit値」として解釈**し、little-endian で 0x76 に埋め込む。
  - 例: `74976167` → 0x74976167 → `67 61 97 74` を送信。CRC16/XMODEM で `C6 8E` が末尾に付与される。
- 認証成功（0x76 ステータス 0x06）後に 0x33 ポーリングを開始。空欄なら認証をスキップします。

## 既知の留意点
- TR4A は 1 分間無通信で切断されるため、ポーリング停止時は UI 側で再接続を考慮してください。
- 特性プロパティが広告と一致しない個体があるため、notify/write が見つからない場合はエラーとして UI に伝搬します。
