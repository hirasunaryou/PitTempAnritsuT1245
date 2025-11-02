# PitTemp Anritsu T1245

> iOS app for tyre surface temperature logging with Anritsu prototype thermometers (BLE).
> 安立試作温度計（BLE）と連携してタイヤ表面温度を記録・可視化するiOSアプリ。

---

## 0. TL;DR

* **対象機器**: `AnritsuM-*` の広告名で検出される試作温度計
* **主機能**: リアルタイム温度表示（ライブグラフ）、メタ情報（サーキット等）入力（キーボード/音声）、CSVエクスポート、iCloudアップロード
* **BLE仕様（抜粋）**:

  * Service UUID: `ADA98080-888B-4E9F-9A7F-07DDC240F3CE`
  * Notify Char:  `ADA98081-888B-4E9F-9A7F-07DDC240F3CE`
  * Write Char:   `ADA98082-888B-4E9F-9A7F-07DDC240F3CE`
  * Notify Payload（例）: `... "001+00243"` → `ID=001`, `24.3℃`
  * 振る舞い: **DATA**ボタン＝即時1回、**HOLD**ボタン＝約250ms間隔で連続送信

---

## 1. 開発の経緯 / Background

* 旧版（HIDキーボード前提）: [https://github.com/hirasunaryou/PitTempAnritsuBTH](https://github.com/hirasunaryou/PitTempAnritsuBTH)
* 新版（BLE直結・試作機別仕様）: [https://github.com/hirasunaryou/PitTempAnritsuT1245](https://github.com/hirasunaryou/PitTempAnritsuT1245)
* 移行のポイント:

  * HID入力依存を廃止し、**BLE Notify/Write**で直接通信へ。
  * 実機ログを解析し、**ASCII断片**から温度を安全に抽出する `TemperaturePacketParser` を作成。
  * HOLD中の連続配信と、通常時の**ポーリング（DATA要求）**を自動切替する制御を導入。
  * **DeviceRegistry** と **ConnectView** を追加し、将来の複数試作機運用を見据えた「スキャン→選択→接続」「既知優先の自動接続」を整備。
  * 音声メモ機能を残しつつ、**メタ情報の音声入力**（各項目別、まとめ取り→抽出）をサポート。

**メモ**

* Notifyが20B以内で、先頭にゴミ（非ASCII）が混ざる → ASCIIレンジ抽出で頑健に解析。
* HOLD時はアプリ側ポーリング不要 → 受信間隔<300msで**連続モード検知**し、ポーリング停止。
* 実測Hzを**EMA**で平滑化。`Hz/W/N`（受信/書込カウンタ）をUIでデバッグ表示。
* 外部キーボード仕様だったころの名残がUIやコードにまだ残っている。使いながら改善していく
* ポーリング自体不要かもしれない

---

## 2. 使い方 / How to Use

1. アプリ起動 → **Measure** 画面表示
2. 右上 **Edit** から **Meta Editor** を開き、サーキット名・車両番号等を入力

   * **Voice**: 項目ごとにマイクで入力、または「まとめ取り→テキストから反映」
   * **解析ログの共有**: `Meta (Voice)` 画面下部の **解析履歴** → **CSVエクスポート** から音声解析結果（ヒットしたキーワード、スコア、認識信頼度など）をフィールドテストチームと共有できます。
   * **マイク未接続の注意**: シミュレータなどマイクが無い環境では録音ボタンの上にフォールバック文言を表示し、録音は無効化されます。実機テストでは録音前に iOS のマイク／音声認識権限を許可してください。
3. **Devices…** を開き **Scan** → 対象 `AnritsuM-*` を **Connect**

   * `Settings > Bluetooth` の **Auto connect** をONにすると、既知/優先IDに自動接続
4. HOLDボタンで連続送信時 → アプリは自動的にポーリング停止、グラフが伸び続けます
5. 記録完了 → **Export CSV** / **Upload**（iCloud）

---

## 3. アプリ構成 / Architecture

```
PitTemp/
├─ App/
│  ├─ PitTempApp.swift          # Appエントリ
│  ├─ Info.plist, entitlements
│
├─ BLE/
│  ├─ BluetoothService.swift    # CoreBluetooth: scan/connect/notify/write/poll
│  └─ TemperaturePacketParser.swift
│
├─ Core/
│  ├─ Features/
│  │  └─ Memo/
│  │     └─ SpeechMemoManager.swift
│  ├─ Parsing/
│  │  └─ CarNumberExtractor.swift   # 音声からの抽出補助（必要に応じて拡張予定）
│  └─ Settings/
│     ├─ SettingsStore.swift        # @AppStorage ラッパ（メタ入力モード等）
│     └─ DeviceRegistry.swift       # 既知デバイス保存（UserDefaults/JSON）
│
├─ Data/
│  └─ CSV/
│     ├─ CSVExporter.swift
│     └─ CSVExporting.swift
│
├─ Models/
│  ├─ TemperatureFrame.swift    # time/deviceID/value/status
│  └─ SessionRecorder.swift     # 記録セッション管理
│
├─ Utils/
│  ├─ Haptics.swift
│  └─ FolderBookmark.swift      # iCloudフォルダへのアップロード支援
│
└─ Views/
   ├─ MeasureView.swift         # メイン画面（Now/Hz/W/N、グリッド、グラフ）
   ├─ MiniTempChart.swift
   ├─ MetaEditorView.swift      # 項目別入力（音声/キーボード）
   ├─ MetaVoiceEditorView.swift # まとめ取り→抽出→反映
   ├─ SettingsView.swift
   └─ ConnectView.swift         # スキャン→選択→接続（RSSI/last seen）
```

**データフロー（概念）**

```
AnritsuM (BLE)
   └─(Notify/Write)→ BluetoothService
        ├─ parseFrames() → TemperatureFrame(value ℃, time, deviceID?, status?)
        ├─ publish latestTemperature / notifyHz / counters
        └─ temperatureStream.send(TemperatureSample)
               └─ SessionViewModel.ingestBLESample()
                      ├─ live配列更新（グラフ）
                      └─ peak/結果反映（UIセル）
```

---

## 4. BLEプロトコル覚え書き / BLE Notes

* **Service**: `ADA98080-888B-4E9F-9A7F-07DDC240F3CE`
* **Read/Notify**: `ADA98081-...`
* **Write**: `ADA98082-...`
* **Payload例**:

  * HEX: `0C 00 00 00 30 30 31 2B 30 30 32 34 33 ...`
  * ASCII抽出: `"001+00243"` → `ID=001`, `+24.3℃`
* **動作**:

  * **DATA**ボタン: 単発送信 → アプリの `requestOnce()`（必要に応じてポーリング5Hz）
  * **HOLD**ボタン: 約250ms間隔の連続送信 → アプリは**連続検知**でポーリング自動停止
* **Hz/W/N**（UIデバッグ表記）

  * `Hz`: 実受信率（EMA平滑）
  * `W`: Write回数（DATA/TIME）
  * `N`: Notify受信回数

---

## 5. 主要クラス / Major Components

* `BluetoothService`

  * スキャン・接続管理、Notify受信、Write送信、ポーリング制御、実測Hz
  * `scanned: [ScannedDevice]` を公開（ConnectViewのデータソース）
  * `autoConnectOnDiscover: Bool` と `preferredIDs: Set<String>`
* `TemperaturePacketParser`

  * 受信バイトから**ASCIIのみ抽出** → `+/-`検出 → 数字を最大6桁まで取得 → 1/10℃ → ℃へ変換
  * 将来的に `deviceID` / `status` 拡張にも対応可能な設計
* `DeviceRegistry`

  * 既知デバイス（ID/名前/エイリアス/自動再接続フラグ/RSSI/最終検出）を**UserDefaults(JSON)**保存
  * すべて**Mainスレッド**で `@Published` を更新
* `SessionViewModel`

  * `temperatureStream` を受け取り **liveデータ**（グラフ）・**ゾーン結果**を更新
* `MetaEditorView / MetaVoiceEditorView`

  * 項目別の音声入力、まとめ取り→抽出→反映（正規表現ベース）

---

## 6. ビルド & 実行 / Build & Run

* Xcode 16.x / iOS 18.x 実機で動作確認
* **Signing**: `PitTemp/App/PitTemp.entitlements` の存在と `CFBundleIdentifier` を `Info.plist` で正しく設定
* トラブル:

  * `Publishing changes from background threads` → `DeviceRegistry` をMain更新にして解消済み
  * `Info.plist duplicate` → `Build Settings > Info.plist File` の重複パスに注意

---

## 7. コントリビュート / Contributing

### Branch / PR

* ブランチ: `feat/...`, `chore/...`, `fix/...`, `refactor/...`
* PRタイトル例:

  * `feat(ble): device picker + known-list autoconnect`
  * `chore(structure): move files into App/BLE/Models/...`

### Commit

* `type(scope): summary`（英語推奨 / 日本語補足OK）

### テスト観点（手動）

* HOLD時の連続受信でグラフが伸び続ける
* DATAボタン単発 → ポーリングが機能
* スキャン一覧でRSSI/last seenが更新される
* Auto-connect ONで preferred IDs が優先される
* Metaの音声入力（項目別/まとめ取り→反映）が動く
* Manual Mode の手動入力値が Autosave と CSV の両方に反映される
* Autosave バックアップ:
  * 計測結果を入力した状態でアプリをバックグラウンド→終了し、再起動時に Measure 画面上部のバナーで復元ステータスが表示されること。
  * Settings > Autosave セクションの **Reset Autosave Snapshot** ボタンでバックアップを削除し、同セクションのログと Measure のバナーが更新されること。

---

## 8. 今後の計画 / Roadmap

* **A. Registry編集UI**（エイリアス変更/優先フラグ/忘却）

  * ConnectView上で編集、または Settings にセクション追加
* **B. CSV/セッション管理の堅牢化**

  * 断線・閾値超過（status）を反映、アラート/色分け
* **C. 解析器の強化**

  * deviceID/ステータスの確実抽出、冗長チェック
* **D. 自動メタ抽出の精度UP**

  * 日本語音声の揺らぎ吸収、辞書/ルールの外出し
* **E. UI/UX**

  * グラフインタラクション、ダークモード調整、iPad横画面最適化
* **F. 品質**

  * ユニットテスト（Parser/Registry）、CI（build + lint）

---

## 9. セキュリティ/プライバシー

* 端末レジストリは端末ローカル（UserDefaults）に保存
* 位置情報は明示許可の上で `LocationLogger` が記録（現在は簡易表示のみ）
* iCloudアップロードはユーザ操作で明示的に実行

---

## 10. よくある質問 / FAQ

* **Q. 受信が途切れる**

  * HOLD状態になっているか（本体のHOLDランプ/OUTセグメント確認）。
  * それでも途切れる場合、アプリ側のWatchdogログに注目。
* **Q. 温度が表示されないがNは増える**

  * 受信バイトに非ASCIIが先頭に混ざるケース → ParserがASCIIのみ抽出するのでだいたいOK。
  * 数字桁数不足（3桁未満）だと捨てる。ログを見て入力の揺らぎを確認。

---

## 11. ライセンス

TBD（社内運用 / PoC段階）

---

