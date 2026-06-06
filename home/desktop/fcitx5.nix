# Mozc ユーザ辞書の変更は、fcitx5 実行中なら activation 後に自動反映する
{ lib, pkgs, ... }:

let
  mozcUserDictionary = import ./mozc-user-dictionary.nix;

  # pkgs.fcitx5 は Mozc なしのベースパッケージのため、PATH 上の with-addons バイナリを使う
  fcitx5Bin = "fcitx5";
  fcitx5RemoteBin = "fcitx5-remote";
  mozcUserDictionaryProto = "${pkgs.mozc.src}/src/protocol/user_dictionary_storage.proto";
  systemdRunBin = "${pkgs.systemd}/bin/systemd-run";
  python = pkgs.python3.withPackages (ps: [ ps.protobuf ]);
  mozcUserDictionaryJson = pkgs.writeText "mozc-user-dictionary.json" (builtins.toJSON mozcUserDictionary);

  # Mozc は writable な ~/.config/mozc/user_dictionary.db を期待するため、
  # upstream proto を使って store 上で生成したバイナリを activation でホームへコピーする。
  mozcUserDictionaryDb = pkgs.runCommandLocal "mozc-user-dictionary.db" {
    nativeBuildInputs = [
      pkgs.protobuf
      python
    ];
  } ''
    workdir="$TMPDIR/mozc-user-dictionary"
    mkdir -p "$workdir"
    cd "$workdir"

    cp ${mozcUserDictionaryProto} ./user_dictionary_storage.proto
    cp ${./mozc/build_user_dictionary.py} ./build_user_dictionary.py
    protoc \
      --proto_path=. \
      --python_out=. \
      ./user_dictionary_storage.proto

    export PYTHONPATH="$workdir"
    ${python}/bin/python ./build_user_dictionary.py \
      --input ${mozcUserDictionaryJson} \
      --proto-dir . \
      --output ./user_dictionary.db

    protoc \
      --decode=mozc.user_dictionary.UserDictionaryStorage \
      ./user_dictionary_storage.proto \
      < ./user_dictionary.db \
      > ./decoded.txt
    grep -F 'name: "personal"' ./decoded.txt > /dev/null

    cp ./user_dictionary.db "$out"
  '';
in
{
  # QuickPhrase は upstream 既定 hotkey があるため、トリガー削除ではなく addon ごと無効化する。
  xdg.configFile."fcitx5/config" = {
    text = ''
      [Behavior/DisabledAddons]
      0=quickphrase
    '';
    force = true;
  };

  # --- fcitx5 profile ---
  xdg.configFile."fcitx5/profile" = {
    text = ''
      [Groups/0]
      # Group Name
      Name=デフォルト
      # Layout
      Default Layout=jp
      # Default Input Method
      DefaultIM=mozc

      [Groups/0/Items/0]
      # Name
      Name=keyboard-jp
      # Layout
      Layout=

      [Groups/0/Items/1]
      # Name
      Name=mozc
      # Layout
      Layout=

      [GroupOrder]
      0=デフォルト
    '';
    force = true;
  };

  # --- Mozc ユーザ辞書 ---
  home.activation.mozcUserDictionary = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    target_dir="$HOME/.config/mozc"
    target_file="$target_dir/user_dictionary.db"

    run mkdir -p "$target_dir"

    if [[ -v DRY_RUN ]]; then
      verboseEcho "Would atomically replace $target_file"
    else
      temp_file="$(mktemp "$target_dir/.user_dictionary.db.tmp.XXXXXX")"
      trap 'rm -f "$temp_file"' EXIT
      install -m 600 ${mozcUserDictionaryDb} "$temp_file"
      mv -f "$temp_file" "$target_file"
      trap - EXIT
    fi

    if run --silence ${fcitx5RemoteBin} --check; then
      verboseEcho "Reloading fcitx5 after Mozc user dictionary update"
      if ! run --silence ${systemdRunBin} --user --collect --quiet ${fcitx5Bin} -r; then
        warnEcho "Failed to reload fcitx5 automatically; run 'fcitx5 -r -d' manually if needed."
      fi
    fi
  '';

  # --- fcitx5 環境変数 ---
  programs.zsh.initContent = ''
    export GTK_IM_MODULE=fcitx
    export QT_IM_MODULE=fcitx
    export XMODIFIERS=@im=fcitx
  '';
}
