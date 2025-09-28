
* **PitTemp**（ピットでの温度計測 → 超シンプル）
* **TireTemp Logger**（そのままだけど説明不要）
* **PitLog**（ピットでログを取る）
* **TireTemp Share**（温度＋共有を明示）
* **PitTemp Sync**（ピットで温度を同期）
* **TireLogger**（タイヤ温度ログ収集）

---

### 🛠 機能をそのまま伝える系

* **Pit Temperature Recorder**（やや長め、でも分かりやすい）
* **Bluetooth Tire Logger**（Bluetooth対応を前面に出す）
* **Tire Temp Cloud**（クラウド共有を意識）
* **PitTemp Cloud**（ピットで測ってすぐクラウドへ）

---

僕のオススメは短くて呼びやすい **PitTemp** か **TireLogger**。
「わかりやすさ」と「呼びやすさ」の両立ができていて、初見の人でも即イメージが湧くと思います。

いいですね、**MacやWebで閲覧前提**なら、最初から「共有ライブラリ名」「ターゲット名」「API/DBの命名」を揃えておくと後々めちゃ楽です。
“わかりやすさ優先”路線で、すぐ流用できる具体名をまとめました。

# プロジェクト/ターゲット名（Xcode）

* **ワークスペース**: `PitTemp.xcworkspace`
* **iOSアプリ（本体）**: `PitTemp`

  * Bundle ID: `com.yourteam.PitTemp`（開発用は `com.yourteam.PitTemp.dev`）
* **共有フレームワーク（ロジック共通化）**: `PitTempKit`

  * 中に BLE, ロギング, モデル, API クライアントをまとめる
* **ユニットテスト**: `PitTempTests`
* **UIテスト**: `PitTempUITests`
* **（任意）CLI ツール**: `ptctl`

  * ログのエクスポート/インポートやデバッグに便利（例: `ptctl export --session 2025-09-20`）

> 将来的にMac版を出すなら
>
> * Catalyst なら：iOSターゲットをそのまま `Mac (Designed for iPad)` 化
> * ネイティブAppなら：`PitTempDesk`（デスク=現場PCのニュアンス）がおすすめ
>
>   * Bundle ID: `com.yourteam.PitTempDesk`

# モジュール/クラス命名（役割が一目で分かる形）

**接頭辞は `PT` or `PitTemp` を統一して付与。**

* BLE/センサー

  * `PTBluetoothManager`（接続・再接続）
  * `PTSensorDiscoveryService`（スキャン）
  * `PTTireTempSensor`（センサ抽象）
  * `PTTemperatureParser`（生データ→摂氏）
* モデル

  * `PTTirePosition`（`FL/FR/RL/RR`）
  * `PTProbePoint`（`Inner/Middle/Outer`）
  * `PTTempRecord`（温度1点）
  * `PTLap`, `PTSession`（走行単位）
* ロギング/永続化

  * `PTLocalStore`（Core Data / SQLite）
  * `PTLogRepository`
* 共有/クラウド

  * `PTAPIClient`
  * `PTCloudSyncService`
  * `PTAuthSession`
* UI

  * `PTDashboardViewController`
  * `PTQuickCaptureView`（“スパスパ取る”画面）
  * `PTTireMatrixView`（4輪×3点の表）
  * `PTLiveShareIndicator`（共有状態）

# 画面名（わかりやすさ重視）

* **Pit View**（ピット計測）
* **Session Log**（セッション一覧）
* **Tire Matrix**（4輪×内中外の一覧）
* **Live Share**（共有状況）
* **Export**（CSV/JSON出力）

# Web/バックエンド命名

* **サービス名**: `PitTemp Cloud`
* **Web アプリ**: `PitTemp Web`
* **API**: `PitTemp API`

## エンドポイント（REST の素直な形）

* `POST /api/v1/sessions`（セッション開始）
* `POST /api/v1/sessions/{sessionId}/samples`（温度バルク投入）
* `GET /api/v1/sessions/{sessionId}`（メタ/統計）
* `GET /api/v1/sessions/{sessionId}/samples?wheel=FL&point=Inner`
* `GET /api/v1/teams/{teamId}/live`（最新値のサマリ）
* `POST /api/v1/notes`（音声メモ→文字起こしID紐づけ）

## データモデル/テーブル名

* `teams (id, name)`
* `sessions (id, team_id, track, started_at, ended_at)`
* `tires (id, session_id, position)` ← `FL/FR/RL/RR`
* `samples (id, tire_id, point, celsius, captured_at)` ← `Inner/Middle/Outer`
* `notes (id, session_id, type, url, transcript, created_at)` ← 音声メモ

## 権限と環境

* 環境: `dev` / `stg` / `prod`
* API ベース URL 例:

  * `https://api-dev.pittemp.app` / `https://api.pittemp.app`
* iOS の設定キー:

  * `PTEnvironment`（`dev|prod`）
  * `PTAPIBaseURL`
* App Group（共有コンテナ）: `group.com.yourteam.pittemp`

# ファイル/フォルダ構成（iOS）

```
PitTemp/
 ├── App/
 │   └── PitTempApp.swift
 ├── Features/
 │   ├── Pit/
 │   │   ├── PTQuickCaptureView.swift
 │   │   └── PTTireMatrixView.swift
 │   ├── Sessions/
 │   └── LiveShare/
 ├── Services/
 │   ├── BLE/ (PTBluetoothManager.swift, PTSensorDiscoveryService.swift ...)
 │   ├── Cloud/ (PTAPIClient.swift, PTCloudSyncService.swift)
 │   └── Storage/ (PTLocalStore.swift, PTLogRepository.swift)
 ├── Models/ (PTTempRecord.swift, PTTirePosition.swift, PTSession.swift ...)
 └── Tests/
```

# 命名ルール（決め打ち推奨）

* **列挙**: `enum TirePosition { case FL, FR, RL, RR }`, `enum ProbePoint { case inner, middle, outer }`
* **測定値構造体**:

  ```swift
  struct PTTempRecord {
      let sessionId: UUID
      let position: TirePosition   // FL/FR/RL/RR
      let point: ProbePoint        // inner/middle/outer
      let celsius: Double
      let capturedAt: Date
      let source: String           // "BLE:<deviceId>"
  }
  ```
* **時刻**: すべて UTC 保持、表示のみローカル
* **ID**: UUID v4 で統一

# スキーム/ビルド設定

* **Schemes**: `PitTemp-Dev`, `PitTemp-Prod`
* **Bundle IDs**:

  * Dev: `com.yourteam.PitTemp.dev`
  * Prod: `com.yourteam.PitTemp`
* **Display Name**:

  * Dev: `PitTemp•Dev`（ドットで区別）
  * Prod: `PitTemp`

# 出力名（わかりやすい書き出し）

* CSV: `PitTemp_{YYYYMMDD}_{Session}.csv`
* JSON: `PitTemp_{YYYYMMDD}_{Session}.json`
* 画像/レポート: `PitTemp_Report_{Session}.pdf`

# BLE 関連の命名メモ（ベンダー仕様がある前提で自前側）

* Service: `PitTemp Temperature Service`
* Characteristic:

  * `PTTempSample`（最新1点）
  * `PTTempBurst`（バルク / Notify）
  * `PTBatteryLevel`（任意）
* ログタグ: `BLE:CONNECT`, `BLE:RETRY`, `BLE:PARSE_ERROR` など固定語彙

# Web 側のUIタブ名（共有時も迷わない）

* **Live**（今この瞬間の4輪×3点）
* **Session**（セッション選択）
* **Notes**（音声メモ/テキスト）
* **Export**（CSV/JSON/PDF）
* **Team**（メンバー管理）

---

迷ったらまずは：

* Xcode **プロジェクト名: `PitTemp`**
* 共有ライブラリ **`PitTempKit`**
* iOS ターゲット **`PitTemp`**、スキーム **`PitTemp-Dev`**
* クラス名は **`PT…` で役割を明示**

このセットで走り始めれば、半年後にそのままストア/クラウド拡張へスムーズに移行できます。
必要なら、最初の **Swift ファイル雛形** も用意しますよ（`PTTempRecord`, `PTBluetoothManager`の最小実装など）。
