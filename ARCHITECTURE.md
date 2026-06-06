# Architecture

NixOS + home-manager flake の構成図。安全運用ガイドは [CLAUDE.md][claude-md] を参照。

## ディレクトリ構成

```
/home/exp/nix-config/
├── flake.nix                   # 入力定義 (nixpkgs / home-manager / nixvim) と nixosConfiguration の組み立て
├── flake.lock                  # 入力リビジョン固定。ローカル yazi_fork の内容ハッシュも保持
├── CLAUDE.md                   # 安全運用ガイド（rebuild 前の必須手順・変更禁止設定）
├── ARCHITECTURE.md             # 本ファイル
├── hooks/
│   └── pre-commit              # nixos-rebuild switch を含む pre-commit フック
├── .claude/
│   ├── settings.local.json     # Claude Code ローカル設定 (Stop hooks 等)
│   └── hooks/
│       └── stop-nixos-rebuild-on-config-change  # clean tree かつ HEAD 変更時に自動 nixos-rebuild switch
├── hosts/
│   └── nixos/
│       ├── configuration.nix       # システム単位の設定（users / systemd / services / mysql / udev 等）
│       ├── hardware-configuration.nix
│       └── update-hosts.py         # /etc/hosts 更新ユーティリティ
├── modules/
│   └── gc.nix                  # nix-store の GC 設定
├── pkgs/                       # ローカル derivation（nixpkgs に無いものを callPackage 用）
│   ├── claude-code/            # claude-code CLI のパッケージ定義
│   └── moomoo/                 # moomoo パッケージ定義
└── home/                       # home-manager（ユーザ単位の設定）
    ├── home.nix                # home-manager のエントリポイント (imports 集約)
    ├── shell.nix               # zsh / starship / shellAliases / 関数
    ├── cli.nix                 # btop / eza / gh wrapper / fastfetch
    ├── git.nix                 # git 設定
    ├── neovim.nix              # nixvim 設定
    ├── packages.nix            # home.packages の追加パッケージ（共通 CLI / Rust / Python）
    └── desktop/                # Wayland / Hyprland 系
        ├── default.nix             # デスクトップ系 imports とパッケージ集約
        ├── cursor.nix              # Bibata カーソルテーマ (XCursor + Hyprcursor 同居パッケージ)
        ├── hyprland/               # Hyprland 設定 + セッション復元 + 壁紙 + カーソル自動切替
        │   ├── default.nix             # Hyprland 設定・キーバインド・systemd services
        │   ├── hypr-dynamic-cursor.py  # カーソル直下輝度で白黒テーマ自動切替
        │   ├── hypr-session-save.sh    # セッション保存
        │   ├── hypr-session-restore.sh # セッション復元
        │   └── wallpapers/            # 壁紙 (黒一色固定)
        ├── fcitx5.nix              # 日本語入力 + QuickPhrase 無効化 + Mozc ユーザ辞書配布
        ├── mozc-user-dictionary.nix # Mozc ユーザ辞書の宣言データ
        ├── mozc/                   # Mozc ユーザ辞書生成 helper
        ├── waybar.nix              # ステータスバー
        ├── kitty.nix               # 端末
        ├── dunst.nix               # 通知
        ├── rofi.nix                # ランチャー
        └── wlogout.nix             # ログアウト UI
```

## レイヤ責務

| レイヤ          | スコープ           | 主なファイル                                  |
| --------------- | ------------------ | --------------------------------------------- |
| flake           | 入力と組み立て     | `flake.nix`                                   |
| modules         | システム共通設定   | `modules/gc.nix`                              |
| hosts           | ホスト固有のシステム設定 | `hosts/nixos/configuration.nix`        |
| pkgs            | ローカル derivation | `pkgs/*/default.nix`                         |
| home (root)     | ユーザ設定の集約   | `home/home.nix`                               |
| home (cli)      | 端末ツールと開発ツール | `home/shell.nix`, `home/cli.nix`, `home/packages.nix` |
| home (desktop)  | GUI / Wayland      | `home/desktop/`                               |

## 適用フロー

1. `flake.nix` が `nixosConfigurations."nixos"` を出力
2. システム側 imports: `modules/gc.nix` → `hosts/nixos/configuration.nix`
3. home-manager imports: `home/home.nix` がエントリポイントとなり `home/{shell,git,neovim,packages,cli}.nix` と `home/desktop/` を取り込む
4. `home/desktop/default.nix` がさらに cursor / hyprland / waybar / kitty 等を imports
5. `nixos-rebuild switch --flake .#nixos` でビルド・有効化（`rebuild` エイリアス）

## 新規追加時の置き場所

- システム全体に影響する設定 → `hosts/nixos/configuration.nix` または `modules/`
- ユーザー固有の CLI ツール設定 → `home/cli.nix` または `home/shell.nix`
- ユーザー固有の共通パッケージ / Rust / Python 開発ツール → `home/packages.nix`。`unzip` などの汎用 CLI や、Rust/WASM Web 開発用の `trunk` もここに置く
- デスクトップ / Wayland 関連 → `home/desktop/` 配下に新規 `.nix` を作成し `home/desktop/default.nix` の imports に追加
- nixpkgs に無いパッケージ → `pkgs/<name>/default.nix` を追加し `pkgs.callPackage` 経由で利用

## NixOS ELF 互換

- `hosts/nixos/configuration.nix` は `programs.nix-ld` を有効化し、`glibc`、`stdenv.cc.cc.lib`、`zlib` を互換ライブラリとして公開する。これにより、`uv` / `pip` が仮想環境へ配置する `ruff` などの汎用 Linux ELF バイナリが、`/lib64/ld-linux-x86-64.so.2` の `stub-ld` で停止せず実行できる。
- Nixpkgs由来の開発ツールは引き続き `home/packages.nix` や各リポジトリの `flake.nix` から提供する。`nix-ld` はNixでビルドされていない補助バイナリを実行する互換層として扱う。

## Mozc ユーザ辞書

- 定義ファイルは `home/desktop/mozc-user-dictionary.nix`。`dictionaryName = "personal"` を維持し、`entries` に `{ key; value; pos; comment ? ""; }` を追加して管理する
- `home/desktop/fcitx5.nix` は `~/.config/fcitx5/config` と `~/.config/fcitx5/profile` を宣言管理する。`config` では `Behavior/DisabledAddons` に `quickphrase` を入れて upstream 既定 hotkey ごと無効化し、`profile` では `Default Layout=jp` / `keyboard-jp` / `mozc` を固定する。`Zenkaku_Hankaku` での切替はこの profile と system 側 XKB レイアウト整合が前提
- `key` はひらがな読みで書く。`pos` は Mozc proto の enum 名 (`NOUN`, `PROPER_NOUN`, `PERSONAL_NAME` など) を使う
- 同じ `value` に対して複数の読みを生やしてよい。短縮 alias も通常エントリと同じ `entries` に追加し、重複禁止は `(key, value, pos)` 単位で見る
- `home/desktop/mozc/build_user_dictionary.py` は `pkgs.mozc.src` の upstream `src/protocol/user_dictionary_storage.proto` を使う。`key` を NFKC 正規化し、カタカナ / 半角カタカナをひらがなへ寄せてから検証する。正規化後にひらがな以外を含む `key`、`personal` 以外の `dictionaryName`、重複する `(key, value, pos)` はビルド時に失敗する
- `pos` は upstream proto 全体ではなく、この repo で許可した明示 allowlist のみを受け付ける。`NO_POS` や将来 upstream に追加された enum はそのままでは使えない
- 旧 QuickPhrase の単一行定型文は `ABBREVIATION` で Mozc ユーザ辞書へ移している。複数行テンプレートは `value` の改行禁止制約により移行せず廃止する
- 個人情報（氏名・住所・電話番号・メールアドレス・GitHub URL・学校名・会社名など）も辞書エントリとして登録している。氏名は `PERSONAL_NAME` / `FAMILY_NAME` / `FIRST_NAME`、学校・会社は `ORGANIZATION_NAME`、地名は `PLACE_NAME`、定型文字列は `ABBREVIATION` を使う
- メールアドレス・電話番号・住所・生年月日・郵便番号・ローマ字氏名のような補完用文字列は `ABBREVIATION` を使う。正式名称の固有名詞を短い読みで引きたい場合は、値に応じて `PERSONAL_NAME` / `FAMILY_NAME` / `FIRST_NAME` / `ORGANIZATION_NAME` を付けた alias を追加する
- `nixos-rebuild switch --flake .#nixos` で `~/.config/mozc/user_dictionary.db` が再生成される。GUI で手動追加した語は次回 switch で上書きされる
- Home Manager activation は毎回 `~/.config/mozc/user_dictionary.db` を同一ディレクトリ内の一時ファイル経由で原子的に置き換える。`fcitx5` 実行中は `systemd-run --user` 経由で自動 reload を試み、失敗時だけ `fcitx5 -r -d` で手動再起動する。reload 時に `fcitx5` バイナリは PATH 解決で探す（`pkgs.fcitx5` は Mozc なしのベースパッケージなので、`${pkgs.fcitx5}/bin/fcitx5` で reload すると NixOS 側の with-addons バイナリがベースバイナリに置き換わり、Mozc がロードされなくなる）
- system 側の XKB 既定値は `hosts/nixos/configuration.nix` で `services.xserver.xkb.layout = "jp"` に揃え、Hyprland の `kb_layout = "jp"` と矛盾しないようにする

## ydotool

- `home/desktop/default.nix` は `YDOTOOL_SOCKET=/run/ydotool/socket` をユーザ環境へ配り、同じソケットを参照する `ydotool` wrapper を `home.packages` に入れる
- `hosts/nixos/configuration.nix` は `ydotoold` を system service として root で起動し、`/dev/uinput` を開いたうえで `/run/ydotool/socket` を `exp:users` / `0660` で公開する
- 旧 `ydotoold` user unit は `home/home.nix` の activation cleanup で停止・`reset-failed` し、user session の degraded 要因を残さない

## Vial

- `home/packages.nix` は `pkgs.vial` 本体に加え、小文字の `vial` コマンドで `${pkgs.vial}/bin/Vial` を起動する wrapper も配る。GUI ランチャーの `Vial.desktop` と端末からの `vial` の両方を同じ実体へ揃えるため
- `hosts/nixos/configuration.nix` は `services.udev.packages = [ pkgs.vial ];` で Vial 付属の udev rule を配り、対象キーボードへ root なしでアクセスできるようにする
- Vial の実キーマップは repo 内や `~/.config/Vial/Vial.conf` には保存されず、キーボード本体の Vial rawhid (`usage_page=0xFF60`, `usage=0x61`) 側に入る。`Vial.conf` はウィンドウ位置・サイズだけ、`~/.local/share/Vial/vial.log` は検出ログだけを持つ
- 2026-05-09 時点で接続中の `W-CORNE` は Vial protocol 6 / VIA protocol 9、4x12 matrix・46 keys・8 layers 構成。実レイヤー割り当ては layer 0 と layer 1 のみが非 `KC_TRNS`、layer 2-7 は全面透過

## GitHub CLI + jj

- `home/cli.nix` は `programs.gh` の設定に加えて `~/.local/bin/gh` wrapper を配る。通常の Git repo や `GIT_DIR` が既にある環境では `${pkgs.gh}/bin/gh` にそのまま委譲する
- `.git` を作らない jj Git backend repo では、wrapper が実行時だけ `jj root` / `jj git root` から `GIT_WORK_TREE` / `GIT_DIR` を設定して `gh` を起動する。repo root に `.git` directory / file / symlink は作らない
- この repo の jj repo-local config は `revset-aliases."trunk()" = "main@origin"` に揃える。remote bookmark は `main@origin` で、`master@origin` を参照すると `Failed to resolve revset-aliases.trunk()` warning が出る。
- `home/cli.nix` は `~/.local/bin/jj` wrapper も配り、通常の `jj commit` / `jj ci` の直後に確定された `@-` が空または description 空白のみなら `jj undo` で戻して失敗させる。`jj describe` / `jj desc` で変更入り `@` の description を空白化する操作も同様に戻す
- `~/.config/jj/conf.d/nix-config.toml` は `git.private-commits` で `empty()` または空白 description の commit を private 扱いにし、`jj git push` で送れないようにする
- jj repo 内の `gh pr checkout` / `gh pr co` / `gh co` は Git checkout ではなく jj-native helper として処理する。PR head を `refs/pull/<番号>/head` から `refs/remotes/origin/pr/<番号>` へ fetch し、`jj git import` 後に既定で `pr/<番号>` bookmark を作り、その commit の上に空の作業 change を作る
- jj-native PR checkout は PR 番号・URL・branch selector を必須とし、引数なしの対話選択は扱わない。`--branch` は local bookmark 名、`--force` は bookmark の後退・横移動許可、`--detach` は bookmark なしの空 change 作成として扱う。`--repo` と `--recurse-submodules` は未対応

## Hyprland

- `home/desktop/hyprland/default.nix` で `configType = "hyprlang"` を明示設定している。Home Manager 26.05 で既定値が `"lua"` に変更されたため、hyprlang 形式を使い続ける場合は明示が必要
- `dwindle:pseudotile` は Hyprland 0.55.1 の `hyprctl descriptions` に存在しないため宣言しない。`dwindle:preserve_split` は継続する。
- donation popup は `ecosystem:no_donation_nag = true` で無効化する。`hyprctl descriptions` で Hyprland 0.55.1 に存在する設定として確認済み。
- `hypr-dynamic-cursor.py` は `grim -t ppm -` の PPM 出力をバイナリとして読み、1x1 pixel の RGB だけを輝度計算に使う。テキストデコードすると任意の RGB バイトで `UnicodeDecodeError` になり、`hypr-dynamic-cursor.service` の再起動ループを起こす。

[claude-md]: ./CLAUDE.md
