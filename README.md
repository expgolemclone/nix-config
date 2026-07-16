# nix-config

`exp` 用の NixOS / Home Manager 設定リポジトリ。過去に認証設定を壊したまま `nixos-rebuild switch` を実行してログイン不能になったため、この README には最小限の安全ルールだけを残す。

## 目立つ修正

- **[26aa4ce](https://github.com/expgolemclone/nix-config/commit/26aa4ce8da94a7e2d7c2f5bbe78af44727eff813)**: j5create JCD554 経由の外部 3 台を 4K 30fps, 縦, 縦, 縦(反対向き) に固定し、LG の横向き / 低解像度化を失敗扱いにする。

## 最重要

- branch は切らない。`master` で作業する。
- `users` / `security` / `pam` / `systemd` まわりは、影響を説明できる場合だけ変更する。
- 次の設定は原則変更禁止。
  - `systemd.sysusers.enable = false`
  - `services.userborn.enable = false`
  - `users.mutableUsers` を `false` にする変更

## rebuild 手順

1. `git diff` で変更を確認する。
2. `git commit` して戻せる状態を作る。
3. `nixos-rebuild build --flake .#nixos` で先にビルドだけ通す。
4. 問題なければ `sudo -n nixos-rebuild switch --flake .#nixos` を実行する。
5. switch 直後に別 TTY でログイン確認する。失敗したら `nixos-rebuild switch --rollback`。

## 現行の注意点

- SDDM の Wayland session は plain `hyprland.desktop` だけを使う。
- 廃止済み `fetch-journal` / `journal-fetch` / `journal-push` user unit は Home Manager activation で消す。
- Mozc ユーザ辞書は `home/desktop/fcitx5.nix` と `home/desktop/mozc-user-dictionary.nix` で宣言管理する。
- Neovim は `lualine` に `catppuccin-nvim` を使い、`wrap` / `linebreak` / `breakindent` を有効にする。
- カーソルテーマは Bibata-Modern-Ice（白）と Bibata-Modern-Classic（黒）をカーソル直下の輝度で自動切替する。`hypr-dynamic-cursor.service` が常駐し、125ms 間隔で判定・ヒステリシス付きで切替える。

## 復旧

1. まず前の generation で起動する。
2. それでも入れなければ boot menu から `systemd.unit=rescue.target` を付けて rescue に入る。
3. `passwd exp` で復旧し、設定を直してから `nixos-rebuild switch --flake .#nixos` をやり直す。

### 外付けHDDのinitrdをライブUSBから再生成

ライブUSBをUEFIモードで起動し、ネットワーク接続後に次の1行を実行する。

```console
curl -fsSL https://raw.githubusercontent.com/expgolemclone/nix-config/main/recover-external-hdd | sudo bash
```

スクリプトは外付けHDDのUUID・LABELを検証してからマウントし、`external-hdd-backup`を含む新しいシステムとブートエントリを生成する。フォーマット、パーティション変更、`fsck -y`は実行しない。

バックアップrootに既存の`gh`認証（`/home/exp/.config/gh/hosts.yml`）があれば、成功・失敗にかかわらず、トークンとホームパスを除去した直近120行のログ要約をPR #20へ自動投稿する。投稿先は公開リポジトリなので、完全なログは送信しない。認証がない場合も復旧処理自体は失敗させず、レポートを`/tmp`へ残す。
