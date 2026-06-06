{ pkgs, ... }:

let
  vialWrapped = pkgs.writeShellScriptBin "vial" ''
    exec ${pkgs.vial}/bin/Vial "$@"
  '';
in

{
  home.packages = with pkgs; [
    # CLI ツール
    bitwarden-cli
    bun
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
    time
    tree
    tty-clock
    unzip
    waydroid-helper
    yazi

    # Python ツール
    python314
    python314Packages.pytest
    python314Packages.requests
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
