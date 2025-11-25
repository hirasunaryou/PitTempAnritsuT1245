# ユーザビリティ改善・ユーザ指摘対応の履歴まとめ

開発依頼者への報告で「どんな指摘にどう応えたか」を素早く示すためのダイジェストです。
各項目のスクショは開発者が適宜差し込んでください（UIセクションの下に貼ると見やすい構成にしています）。

## 1. 時系列ハイライト

| 時期 (コミット系列) | ユーザー指摘/ニーズ | 取った対策 | 実装の要点・参照ポイント |
| --- | --- | --- | --- |
| 2024: Meta Voice 認識精度のばらつき | 長音の抜けや誤認識（ゼッケン→石鹸）で項目抽出が失敗する、手動で直せる場が欲しい | ・キーワードデフォルトを長音なし/誤認識語まで拡充し、旧設定のみ自動マイグレーション<br>・Meta Voice 画面に「手動で微調整」ブロックを追加してその場修正可<br>・値整形を最小限にして既存の人名が壊れないように変更 | ・設定デフォルトと移行ロジック【F:Docs/MetaVoiceDeveloperNotes.md†L3-L24】【F:PitTemp/Shared/Settings/SettingsStore.swift†L46-L148】【F:PitTemp/Shared/Settings/SettingsStore.swift†L320-L333】<br>・音声抽出UI/リファイナの調整【F:PitTemp/Features/Meta/MetaVoiceEditorView.swift†L508-L534】【F:PitTemp/Features/Meta/MetaVoiceEditorView.swift†L720-L760】 |
| 2025: 記録の取り違え・上書き事故の不安 | 履歴閲覧中にライブ計測のオートセーブを汚したくない／保存有無を明確に知りたい | ・履歴モード中はオートセーブを完全停止し、ライブデータを守る<br>・復元/読込/手動削除のログを UI に流して「いま何が保存されたか」を明示 | ・オートセーブのガード＆ステータス発行【F:PitTemp/Features/Measure/SessionViewModel.swift†L503-L655】 |
| 2025: 保存先と共有の混乱 | 「どこに保存されたか分かりづらい」「クラウドに上げたくないケースがある」 | ・端末ニックネームを保存フォルダ名に埋め込み、誰のデータか判別しやすく<br>・「Save 後にクラウドへ上げる」トグルを用意し、ローカルのみ保存も選択可 | ・プロフィール入力とクラウド保存トグルの説明【F:PitTemp/Features/Settings/SettingsView.swift†L25-L65】<br>・ニックネームの永続化設定【F:PitTemp/Shared/Settings/SettingsStore.swift†L46-L148】 |

## 2. スクリーンショット挿入のヒント

- **Meta Voice 微調整 UI**: `MetaVoiceEditorView` の「手動で微調整」セクション付近を撮ると、音声抽出後にすぐ直せる点が伝わります。
- **オートセーブ状態表示**: 計測画面 or 設定画面でオートセーブのステータスログが出ている様子を撮影し、履歴モードと分離されていることを示してください。
- **クラウド保存トグルとニックネーム**: 設定画面の「Profile」「Export」セクションを撮影すると、保存先や共有ポリシーをユーザーが選べることが一目で分かります。

## 3. 追加の読み解きポイント

- キーワード初期値の自動移行は「旧デフォルトと一致する場合のみ」動くため、既存ユーザー設定を壊さずに新語彙を配信できます。実装は `migrateMetaVoiceKeywordsIfNeeded()` を参照してください。【F:PitTemp/Shared/Settings/SettingsStore.swift†L320-L333】
- オートセーブのワークアイテムは履歴モードでは即キャンセルされるため、過去セッションを開いても最新計測のスナップショットが上書きされません。【F:PitTemp/Features/Measure/SessionViewModel.swift†L564-L595】
- 「Upload after Save」トグルをオフにするとローカル保存のみになり、後から Library で必要分だけ手動アップロードする運用ができます。【F:PitTemp/Features/Settings/SettingsView.swift†L55-L65】

