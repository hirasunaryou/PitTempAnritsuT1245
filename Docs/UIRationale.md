# UI設計の背景とユーザーフィードバックの整理 / UI Rationale & Feedback Digest

このドキュメントは、これまで寄せられたユーザービリティ改善要望や不具合指摘が最終的なUI構成にどう反映されたかを、開発ストーリーとしてまとめたものです。開発者は適宜スクリーンショットを差し込み、なぜ今のレイアウト・文言・トグル構成になっているのかを説明する材料として活用してください。

## 1. 収集したユーザーの声（抜粋）
- **保存先が分からない / オフライン時の挙動が不安**: 保存後に「ローカルかクラウドか」が曖昧という指摘を受け、保存ポップアップに行ごとの行き先ラベルとオンライン/オフライン状態を併記するようにした。【F:Docs/UsabilityHistory.md†L5-L11】【F:PitTemp/Features/Measure/MeasureView.swift†L2055-L2134】
- **セッションIDの読み方・突合が難しい**: CSVに残る識別子が理解されにくいとの声から、設定画面に用途解説を置き、保存時もラベル＋UUIDの両方を明示する方針にした。【F:Docs/UsabilityHistory.md†L13-L18】【F:PitTemp/Features/Settings/SettingsView.swift†L142-L159】【F:PitTemp/Shared/Models/SessionFileContext.swift†L8-L42】
- **Drive一覧が文脈不足**: CSV一覧がファイル名頼りで混乱するという指摘を受け、ドライバー/車両/端末/セッションの各メタ情報をグリッドで表示し検索・並べ替えできるようにした。【F:Docs/UsabilityHistory.md†L20-L24】【F:PitTemp/Features/Library/LibraryView.swift†L1436-L1522】
- **端末フォルダ名が長く衝突しやすい**: Finderで読みづらいとの声に合わせ、端末名を整形し短縮IDを付けたフォルダ名生成に変更した。【F:Docs/UsabilityHistory.md†L26-L30】【F:PitTemp/Shared/Data/CSV/CSVExporter.swift†L124-L161】
- **履歴閲覧時にライブ計測を上書きしたくない**: 履歴モード中はオートセーブを完全停止し、ログで状態を伝えるようにした。【F:PitTemp/Features/Measure/SessionViewModel.swift†L503-L600】
- **Meta Voiceの誤認識をその場で直したい**: 認識揺れを受けてキーワードのデフォルトを拡充し、エディタに「手動で微調整」セクションを追加した。【F:Docs/MetaVoiceDeveloperNotes.md†L3-L24】【F:PitTemp/Shared/Settings/SettingsStore.swift†L46-L112】【F:PitTemp/Shared/Settings/SettingsStore.swift†L320-L333】【F:PitTemp/Features/Meta/MetaVoiceEditorView.swift†L508-L534】

## 2. 現在のUI構成に至った根拠
- **Measure画面の保存バナー**: ローカル/iCloud/Google Driveの行ごとにアイコンと色を分け、オフライン時は「queued」を示すことで「どこに行ったか分かる」体験を優先している。【F:PitTemp/Features/Measure/MeasureView.swift†L2055-L2134】
- **保存ポップアップのパス表示**: iCloud共有リンク配下の「日付/端末/ファイル名」をそのまま表示し、ローカル保存先との差を視覚化する設計にしている。【F:PitTemp/Features/Measure/MeasureView.swift†L2140-L2164】
- **Settingsのクラウドトグルと説明文**: 「Upload after Save」でローカル保存のみ運用を選べるようにし、iCloud/Driveを別トグルで切替できることで共有ポリシーの不安を解消する。【F:PitTemp/Features/Settings/SettingsView.swift†L35-L140】
- **Session IDセクション**: ラベルとUUIDの読み方・用途を文章で提示し、クラウドにも両方を埋め込む根拠をUI内で説明している。【F:PitTemp/Features/Settings/SettingsView.swift†L142-L159】【F:PitTemp/Shared/Models/SessionFileContext.swift†L8-L42】
- **Library画面のグリッド行**: ドライバー・車両・端末名・セッションラベル/UUID・日付フォルダを行単位で並べ、検索と並べ替えもメタデータを対象にすることで「探しやすさ」を担保している。【F:PitTemp/Features/Library/LibraryView.swift†L1436-L1539】
- **Meta Voiceエディタの手動修正ブロック**: 自動抽出後に各フィールドを直接編集できるカードを用意し、認識の揺れを現場で補正する導線を確保している。【F:PitTemp/Features/Meta/MetaVoiceEditorView.swift†L508-L534】
- **フォルダ命名とメタデータ整形**: 端末名をサニタイズして短縮しつつUUIDを含めたフォルダ名を生成し、Drive側にはDay/Session階層でセッションラベルを反映することで、人が辿りやすく衝突も避ける構成にしている。【F:PitTemp/Shared/Data/CSV/CSVExporter.swift†L124-L161】【F:PitTemp/Shared/Models/SessionFileContext.swift†L20-L45】
- **オートセーブのガード**: 履歴モード中はスナップショット保存をスキップし、ログで状態を残すことで「過去データでライブ計測を壊さない」ことを保証している。【F:PitTemp/Features/Measure/SessionViewModel.swift†L503-L600】

## 3. 今後ドキュメントを拡張する際のヒント
- 各セクションにスクリーンショットを追加し、「どの指摘にどう応えたか」を視覚的に示す。オフライン/オンライン時のバナー切替やライブラリ検索結果など、挙動が分かる状態で撮影すると説得力が増します。
- 新たなフィードバックが来たら、上記の「声」セクションに追記し、どのUI変更で解消したかを「根拠」セクションに対応付けてください。
- 変更検討時は、既存のトグルや説明文が同じ課題に触れていないかを先に確認し、重複や矛盾を避けると後続の開発工数を抑えられます。

---

このドキュメントは「ユーザーの声 → UI変更 → 実装箇所」という紐づけを時系列で残すことで、今後の改善提案が来た際にも過去の意図を踏まえた最適な判断を行えるようにすることを目的としています。
