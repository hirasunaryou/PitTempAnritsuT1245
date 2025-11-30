# Branch Update Guide / ブランチ更新ガイド

This repository frequently uses the `work` branch for in-progress changes. Use the following steps to update your local branch safely.

## TL;DR commands / すぐに使えるコマンド一覧

```bash
git fetch origin
# If you are on work and want the latest commits:
git pull --rebase origin work
# Confirm the history:
git log --oneline --decorate -5
```

## Step-by-step / 手順解説

1. **Check your current branch / 現在のブランチを確認**
   ```bash
   git status -sb
   ```
   Ensure you are on `work` (or the branch you intend to update).

2. **Save or stash local changes / 手元の変更を保存またはスタッシュ**
   - If you have edits, commit them or run `git stash` so rebase can proceed cleanly.

3. **Fetch remote updates / リモートの更新を取得**
   ```bash
   git fetch origin
   ```

4. **Rebase onto the latest remote branch / 最新のリモートにリベース**
   ```bash
   git pull --rebase origin work
   ```
   - Replace `work` with another branch name if needed.
   - Rebase keeps history linear and avoids merge bubbles.

5. **Verify history / 履歴を確認**
   ```bash
   git log --oneline --decorate -5
   ```
   Check that your branch now includes the newest commits.

6. **Re-apply stashed changes if any / スタッシュを戻す**
   ```bash
   git stash pop
   ```

## Tips / コツ

- Use `git pull --rebase` instead of `git pull` to reduce merge commits.
- If rebase conflicts occur, resolve them, run `git rebase --continue`, and rerun tests.
- Keep `git status` open in another terminal to monitor changes while resolving conflicts.

