{ pkgs, ... }:

let
  pythonWithPackages = pkgs.python314.withPackages (pythonPackages:
    with pythonPackages; [
      openpyxl
      pytest
      requests
    ]);

  vialWrapped = pkgs.writeShellScriptBin "vial" ''
    exec ${pkgs.vial}/bin/Vial "$@"
  '';
in

{
  home.packages = with pkgs; [
    # CLI ツール
    bitwarden-cli
    bun
    cloudflared
    codex
    file
    glab
    imagemagick
    jq
    jujutsu
    mdcat
    megacmd
    nodejs
    openssl
    parallel
    poppler-utils
    sox
    sysstat
    time
    tree
    tty-clock
    unzip
    waydroid-helper
    yazi

    # Python ツール
    pythonWithPackages
    ruff
    uv

    # Rust ツール
    hyperfine
    rust-analyzer
    rustc
    cargo
    clippy
    rustfmt
    trunk

    # ブラウザ
    firefox
    google-chrome

    # キーボード設定
    vial
    vialWrapped
  ];
}
