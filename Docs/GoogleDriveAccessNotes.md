# Google Drive 連携に関するQ&Aメモ / Notes on Google Drive Integration

**作成日 / Created:** 2025-11-09

---

## Q1. アクセストークンか GoogleSignIn SDK を提供してくださいと言われたら？
- **質問 / Question:** アクセストークンか GoogleSignIn SDK を提供してくださいと表示されるが、どうすればよいか？
- **回答 / Answer:**
  - GoogleSignIn SDK を追加しない場合でも、設定画面の「Manual access token」欄にアクセストークンを入力すれば Drive API を利用できる。トークンは Google Cloud Console で OAuth クライアントを作成し、`https://www.googleapis.com/auth/drive.file` スコープで発行する。通常は 1 時間ほどの有効期限があるため定期更新が必要。
  - GoogleSignIn SDK を導入する場合は、Swift Package Manager で `GoogleSignIn` を追加し、OAuth クライアント ID と URL スキームを設定する。これによりアプリ内で Google アカウントにサインインし Drive アップロードが可能になる。

## Q2. GoogleSignIn SDK の導入コストや運用負荷は？
- **質問 / Question:** GoogleSignIn SDK を組み込むと費用や追加管理が必要になるか？
- **回答 / Answer:**
  - SDK と OAuth クライアントの利用に追加費用は掛からない（API 無料枠の範囲内）。
  - 運用面では OAuth クライアント ID の発行・管理、OAuth 同意画面の設定、URL スキームの維持などの作業が必要。アカウントや証明書を変更した場合は再設定が発生する。
  - SDK を使わない場合でも手動アクセストークンで運用できるため、要件に応じて選択可能。

## Q3. 測定者が Google アカウントを持っていない場合の扱いは？
- **質問 / Question:** 測定者が Google アカウントを持たなくても共有リンクで CSV を閲覧できるのか？
- **回答 / Answer:**
  - Drive の共有設定を「リンクを知っている全員が閲覧可」にすると、Google アカウントなしでもリンク経由で参照・ダウンロードできる。
  - ただしアプリから Drive にアップロードするには Google アカウントに紐づくアクセストークンが必須。測定者がアカウントを持たない場合は、管理者が発行したアクセストークンをアプリに入力する、代理でアップロードする、共通アカウントを配布するといった運用が必要。
  - リンク共有は漏洩リスクがあるため、組織のポリシーに応じてアクセス制御（組織限定共有など）を検討する。

---

上記内容は 2025 年 11 月時点での検討結果であり、運用要件の変更に応じて更新すること。 / This summary captures the guidance as of Nov 2025 and should be updated if requirements evolve.
