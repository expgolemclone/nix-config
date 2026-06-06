# claude-code バージョンオーバーライド
# nixpkgs の claude-code が npm から削除されたバージョンを参照している場合に使用
# nixpkgs が修正されたらこのオーバーレイは削除可能
{ prev }:
let
  version = "2.1.90";
in
prev.buildNpmPackage {
  pname = "claude-code";
  inherit version;

  src = prev.fetchzip {
    url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
    hash = "sha256-4/hqWrY2fncQ8p0TxwBAI+mNH98ZDhjvFqB9us7GJK0=";
  };

  npmDepsHash = "sha256-kWbbIAoNAQ/BtsICmsabkfnS/1Nta5MQ4iX9+oH7WRw=";

  strictDeps = true;

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    substituteInPlace cli.js \
      --replace-fail '#!/bin/sh' '#!/usr/bin/env sh' \
      --replace-fail 'color:"clawd_body"' 'color:"clawd_background"'
  '';

  dontNpmBuild = true;

  env.AUTHORIZED = "1";

  postInstall = ''
    wrapProgram $out/bin/claude \
      --set DISABLE_AUTOUPDATER 1 \
      --set-default FORCE_AUTOUPDATE_PLUGINS 1 \
      --set DISABLE_INSTALLATION_CHECKS 1 \
      --unset DEV \
      --prefix PATH : ${
        prev.lib.makeBinPath [
          prev.procps
          prev.bubblewrap
          prev.socat
        ]
      }
  '';

  meta = {
    description = "Agentic coding tool that lives in your terminal";
    homepage = "https://github.com/anthropics/claude-code";
    license = prev.lib.licenses.unfree;
    mainProgram = "claude";
  };
}
