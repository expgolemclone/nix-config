# nix-config

`exp`用のNixOS / Home Manager設定リポジトリ. 過去に認証設定を壊したまま`nixos-rebuild switch`を実行してログイン不能になったため, このREADMEには最小限の安全ルールだけを残す.

## 最重要

- bookmarkとremote branchは`main`だけを使う.
- `users` / `security` / `pam` / `systemd`まわりは, 影響を説明できる場合だけ変更する.
- 次の設定は原則変更禁止.
  - `systemd.sysusers.enable = false`
  - `services.userborn.enable = false`
  - `users.mutableUsers`を`false`にする変更

## rebuild手順

1. `jj diff`で変更を確認する.
2. 戻せるchangeを作る.
3. `nixos-rebuild build --flake .#nixos`で先にビルドだけを通す.
4. 問題がなければ`sudo -n nixos-rebuild switch --flake .#nixos`を実行する.
5. switch直後に別TTYまたはSSHでログイン確認する. 失敗したら`nixos-rebuild switch --rollback`を実行する.

## 現行の注意点

- SDDMのWayland sessionはplain `hyprland.desktop`だけを使う.
- 廃止済み`fetch-journal` / `journal-fetch` / `journal-push` user unitはHome Manager activationで消す.
- Mozcユーザ辞書は`home/desktop/fcitx5.nix`と`home/desktop/mozc-user-dictionary.nix`で宣言管理する.
- Neovimは`lualine`に`catppuccin-nvim`を使い, `wrap` / `linebreak` / `breakindent`を有効にする.
- カーソルテーマはBibata-Modern-IceとBibata-Modern-Classicをカーソル直下の輝度で自動切替する.
- `yazi-fork`はprivateなローカルflake inputである. ライブ復旧ではHDD内の`/home/exp/projects/yazi_fork`を`--override-input`で使う.

## SSDトラブル時の既定方針

SSDを直ちに初期化しない. BUFFALO外付けHDDの`external-hdd-backup` specialisationから起動し, HDDを一時的な通常環境として使う.

外付けHDD起動時だけ, 次の復旧設定が有効になる.

- ホスト名を`nixos-recovery`にする.
- 有線LANへ`192.168.137.2/24`を追加する.
- GitHubアカウント`expgolemclone`の公開SSH鍵を取得する.
- `exp`への公開鍵SSHだけを許可する.
- password, keyboard-interactive, root SSH loginを禁止する.
- firewallでTCP 22だけを許可する.
- `recovery-status`, `recovery-ssd-diagnose`, `recovery-restore-ssd`を提供する.

VAIO側の操作と人間が行う最小手順は[`docs/remote-recovery.md`](docs/remote-recovery.md)を参照する.

## 通常の設定事故からの復旧

1. 前のgenerationで起動する.
2. それでも入れなければboot menuから`systemd.unit=rescue.target`を付けてrescueへ入る.
3. `passwd exp`で復旧し, 設定を直してから`nixos-rebuild switch --flake .#nixos`をやり直す.

## 外付けHDDのinitrdをライブUSBから再生成

公式NixOSインストーラをUEFIモードで起動し, ネットワーク接続後に次の1行を実行する.

```console
curl -fsSL https://raw.githubusercontent.com/expgolemclone/nix-config/main/bootstrap-live-recovery | sudo bash
```

以降はVAIOから`nixos@192.168.137.2`へSSH接続し, 次を実行する.

```console
curl -fsSL https://raw.githubusercontent.com/expgolemclone/nix-config/main/recover-external-hdd | sudo bash
```

スクリプトはHDDのUUID, LABEL, filesystem, partition pairingを検証し, rootとESPをread-onlyに保ったまま固定revisionを解決する. rootだけを書き込み可能にしてシステムをbuildし, external-HDD specialisation, fstab, initrd modulesを確認した後にだけESPを書き込み可能にする. format, repartition, `fsck`は実行しない.

GitHubへのreportは既定で無効であり, 復旧の必須条件ではない. 明示的に`RECOVERY_REPORT_MODE=github`を設定した場合だけ, 保存済み`gh`認証を使ってissueへ結果を投稿する.
