{
  stdenvNoCC,
  lib,
  fetchurl,
  dpkg,
  buildFHSEnv,
  appimageTools,
  makeDesktopItem,
  writeShellScript,
  qt6,
  libnotify,
  pipewire,
  alsa-lib,
  libxcb,
  libxcb-image,
  libxcb-keysyms,
  libxcb-render-util,
  libxcb-wm,
  libxkbcommon,
  zstd,
}:
let
  pname = "moomoo";
  version = "16.11.15608";

  src = fetchurl {
    url = "https://softwaredownload.futustatic.com/moomoo_desktop_${version}_amd64.deb";
    hash = "sha256-89PYrXao3h5/5JwFCAAfHxaLixug4TjRicASxHS7XWQ=";
  };

  desktopItem = makeDesktopItem {
    name = pname;
    desktopName = "moomoo";
    exec = "moomoo %U";
    icon = "moomoo";
    categories = [ "Finance" ];
    startupNotify = true;
  };

  moomoo-unwrapped = stdenvNoCC.mkDerivation {
    inherit pname version src;

    nativeBuildInputs = [ dpkg ];

    unpackPhase = ''
      runHook preUnpack
      mkdir moomoo-src
      dpkg -x "$src" moomoo-src
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -a moomoo-src/. "$out"/
      runHook postInstall
    '';

    meta = {
      mainProgram = pname;
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    };
  };
in
buildFHSEnv {
  inherit pname version;

  targetPkgs =
    pkgs:
    [
      moomoo-unwrapped
      qt6.qtwayland
    ]
    ++ appimageTools.defaultFhsEnvArgs.targetPkgs pkgs;

  multiPkgs =
    pkgs:
    appimageTools.defaultFhsEnvArgs.multiPkgs pkgs
    ++ [
      alsa-lib
      libnotify
      pipewire
      libxcb
      libxcb-image
      libxcb-keysyms
      libxcb-render-util
      libxcb-wm
      libxkbcommon
      zstd
    ];

  runScript = writeShellScript "moomoo-launcher" ''
    export MOOMOO_HOME="/opt/moomoo"
    export LD_LIBRARY_PATH="/opt/moomoo:/opt/moomoo/lib:/opt/moomoo/plugins/platforms''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export QT_PLUGIN_PATH="/opt/moomoo/plugins:/opt/moomoo/plugins/platforms''${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"
    export QT_QPA_PLATFORM="xcb"

    cd "/opt/moomoo"
    exec ./moomoo "$@"
  '';

  extraInstallCommands = ''
    mkdir -p "$out/share/applications" "$out/share/pixmaps"
    cp ${desktopItem}/share/applications/* "$out/share/applications/"
    install -Dm644 ${moomoo-unwrapped}/opt/moomoo/app.png "$out/share/pixmaps/moomoo.png"
  '';

  passthru = {
    inherit moomoo-unwrapped;
  };

  meta = {
    description = "Desktop trading application from moomoo";
    homepage = "https://www.moomoo.com/download/linux";
    license = lib.licenses.unfree;
    mainProgram = pname;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
