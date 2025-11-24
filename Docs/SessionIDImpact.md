# Session ID Migration Impact / 影響範囲メモ

このメモは、セッションIDをUUIDから人間可読フォーマット（Op-ISO8601-Device-Context-Rand-vRev-Sync）に移行した際に、アプリ内で影響を受ける箇所の洗い出しと現在の対応状況をまとめたものです。

## 適用済み / Completed
- **生成と運用**: `SessionViewModel` で新フォーマットのIDを払い出し、履歴復元時は旧UUIDでも自動ラップ（後方互換）。
- **保存系**: `SessionAutosaveStore` と `SessionHistoryStore` が `SessionID.rawValue` をファイル名とJSONに使用。ファイル名に使えない文字は `safeFileToken()` でサニタイズ。
- **エクスポート**: `CSVExporter` と `DriveCSVMetadata` が新IDを採用し、Google Driveへのプロパティ保存も文字列IDで統一。
- **閲覧UI**: 履歴詳細・レポート・ライブラリ一覧など、UI表示/ソート/検索を `SessionID.rawValue` ベースに変更。
- **互換性**: 旧JSON/CSVから読み込んだUUID文字列は `SessionID(rawValue:)` で自動的に新型へ変換するため、過去データの破損を防止。

## 要確認・今後の着手候補 / Next Checks
- **バージョン番号運用**: 編集時に `v<Rev>` を増分するフロー（UIトリガーと保存タイミング）を決定する。現在は計測開始ごとに `v1` を払い出す初期実装。
- **Sync状態の昇格**: クラウドアップロード成功時に `Sync=ON` へ更新し、ローカル履歴へ反映する仕組みを追加する。
- **重複検知**: `SessionHistoryStore` で同一 `rawValue` の履歴が複数存在した場合のマージ/警告ロジックを追加する。
- **日次CSVまとめ機能**: Dailyまとめの際、ファイル名・シート名にサニタイズ済みIDを使うかどうかを確認する。
- **UI表記**: `SessionHistorySummary` のラベル短縮（例: 先頭8文字）をどの画面で使うか統一する。長いIDを折り返すUX検討。
- **テスト整備**: `SessionID.generate` に固定時刻/乱数を差し込み、UIスナップショット/CSV出力のユニットテストを追加する。

## 運用メモ / Ops Notes
- 旧セッションID（UUIDのみ）で保存されたCSV/JSONは、読み込み時に自動で新IDにラップされるため、移行手順は不要。
- ファイル名に日時やコロンが含まれるため、すべてのパス生成で `safeFileToken()` を通すことを推奨。今回の修正では履歴/自動保存/CSV出力に適用済み。
- Google Drive の `properties.sessionID` は新フォーマットの文字列で記録される。外部連携（スクリプト等）はこのキーを参照する。
