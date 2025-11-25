# CHANGELOG

## Unreleased

### Summary / 概要
* リポジトリのフォルダ構成を `Shared/` と `Features/` で再編し、機能横断ユーティリティと画面単位の責務を明確化。
* README のアーキテクチャ図とセットアップ手順を更新し、CI/テスト実行コマンドを追記。

### Compatibility notes / 互換性の注意
* フォルダ移動後は Xcode プロジェクト内の参照が残る場合があります。`Project Navigator` で不要な参照を **Remove Reference** し、`Build Phases > Compile Sources` を見直してください。
* `Info.plist` や entitlements のパスが変わった場合、`Build Settings > Packaging` のパスも合わせて更新しないとビルドが失敗することがあります。
