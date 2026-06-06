{ config, lib, pkgs, ... }:

let
  hyprlandSessionPackage = pkgs.writeTextFile {
    name = "hyprland-session";
    text = ''
      [Desktop Entry]
      Name=Hyprland
      Comment=An intelligent dynamic tiling Wayland compositor
      Exec=${config.programs.hyprland.package}/bin/start-hyprland
      Type=Application
      DesktopNames=Hyprland
      Keywords=tiling;wayland;compositor;
    '';
    destination = "/share/wayland-sessions/hyprland.desktop";
    derivationArgs = {
      passthru.providedSessions = [ "hyprland" ];
    };
  };
  usbCDisplayDiagnose = pkgs.writeShellScriptBin "usb-c-display-diagnose" ''
    set -u

    section() {
      printf '\n## %s\n' "$1"
    }

    print_readable_file() {
      [ -r "$1" ] || return 0
      printf '%s:' "$1"
      cat "$1"
    }

    section "Power supply"
    for f in /sys/class/power_supply/*/*; do
      case "$f" in
        */type|*/online|*/status|*/manufacturer|*/model_name|*/power_now|*/voltage_now|*/current_now|*/input_current_limit|*/usb_type|*/scope)
          print_readable_file "$f"
          ;;
      esac
    done

    section "USB-C"
    for f in /sys/class/typec/*/* /sys/class/typec/*/*/*; do
      case "$f" in
        */active|*/mode|*/svid|*/description|*/supports_usb_power_delivery|*/power_role|*/data_role|*/usb_power_delivery_revision|*/usb_capability|*/power_operation_mode|*/plug_type|*/type|*/online|*/current_now|*/voltage_now)
          print_readable_file "$f"
          ;;
      esac
    done

    section "DRM connector state"
    for f in /sys/class/drm/card*-*/status /sys/class/drm/card*-*/enabled; do
      print_readable_file "$f"
    done

    if command -v hyprctl >/dev/null 2>&1; then
      section "Hyprland monitors"
      hyprctl monitors all -j || true
      section "Hyprland config errors"
      hyprctl configerrors || true
    fi

    section "USB devices"
    ${pkgs.usbutils}/bin/lsusb || true
    ${pkgs.usbutils}/bin/lsusb -t || true

    section "PCI devices"
    ${pkgs.pciutils}/bin/lspci -nn || true

    section "DRM info connectors"
    ${pkgs.drm_info}/bin/drm_info | ${pkgs.gnused}/bin/sed -n '/Connectors/,/Encoders/p' || true

    section "Kernel log"
    journalctl -b -k --no-pager -n 200 -g 'ucsi|typec|drm|amdgpu|DisplayPort|HDMI|usb' || true
  '';
in

{
  imports = [
    ./hardware-configuration.nix
  ];

  # --- ブートローダー ---
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # --- ネットワーク ---
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;
  networking.networkmanager.settings.connectivity.enabled = false;
  networking.extraHosts = ''
    0.0.0.0 youtube.com www.youtube.com m.youtube.com
    0.0.0.0 x.com www.x.com twitter.com www.twitter.com mobile.twitter.com t.co
    0.0.0.0 tiktok.com www.tiktok.com
    0.0.0.0 instagram.com www.instagram.com
  '';
  # 四季報オンラインの誌面画像に必要（ルーター DNS がブロックするため上書き）
  # 起動時に外部 DNS (1.1.1.1) で解決して /etc/hosts を動的更新
  systemd.services.update-hosts = {
    description = "Resolve blocked domains via external DNS and update /etc/hosts";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.python3}/bin/python3 ${./update-hosts.py}";
    };
  };

  # --- ロケール・タイムゾーン ---
  time.timeZone = "Asia/Tokyo";
  i18n.defaultLocale = "ja_JP.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "ja_JP.UTF-8";
    LC_IDENTIFICATION = "ja_JP.UTF-8";
    LC_MEASUREMENT = "ja_JP.UTF-8";
    LC_MONETARY = "ja_JP.UTF-8";
    LC_NAME = "ja_JP.UTF-8";
    LC_NUMERIC = "ja_JP.UTF-8";
    LC_PAPER = "ja_JP.UTF-8";
    LC_TELEPHONE = "ja_JP.UTF-8";
    LC_TIME = "ja_JP.UTF-8";
  };

  # --- IME (fcitx5 + mozc) ---
  i18n.inputMethod = {
    type = "fcitx5";
    enable = true;
    fcitx5.addons = with pkgs; [
      fcitx5-mozc
      fcitx5-gtk
    ];
  };
  services.xserver.xkb.layout = "jp";

  # dbus 実装を従来の dbus に固定（broker は起動時にハングする）
  services.dbus.implementation = "dbus";

  # --- オーディオ (PipeWire) ---
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
    wireplumber.enable = true;
  };
  security.rtkit.enable = true;

  # --- Bluetooth ---
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = true;

  # --- GPU (AMD) ---
  hardware.graphics.enable = true;

  # --- ディスプレイマネージャ + Hyprland ---
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
    wayland.compositor = "kwin";
    theme = "where_is_my_sddm_theme";
    extraPackages = with pkgs.qt6; [
      qt5compat
      qtsvg
    ];
  };
  services.displayManager.defaultSession = "hyprland";
  # Hyprland upstream package ships both plain and UWSM desktop entries even when
  # withUWSM is false, so force SDDM to only see the known-good plain session.
  services.displayManager.sessionPackages = lib.mkForce [ hyprlandSessionPackage ];
  programs.hyprland = {
    enable = true;
    withUWSM = false;
  };

  # --- sudo ---
  security.sudo.wheelNeedsPassword = false;

  # --- ユーザー ---
  systemd.sysusers.enable = false;
  users.users.exp = {
    isNormalUser = true;
    description = "exp";
    extraGroups = [ "networkmanager" "wheel" "video" "audio" ];
    shell = pkgs.zsh;
  };
  programs.zsh.enable = true;

  # --- フォント ---
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    nerd-fonts.jetbrains-mono
  ];
  fonts.fontconfig.defaultFonts = {
    sansSerif = [ "Noto Sans CJK JP" "Noto Color Emoji" ];
    serif = [ "Noto Serif" "Noto Color Emoji" ];
    monospace = [ "JetBrainsMono Nerd Font" "Noto Color Emoji" ];
    emoji = [ "Noto Color Emoji" ];
  };
  fonts.fontconfig.useEmbeddedBitmaps = true;
  fonts.fontconfig.localConf = ''
    <fontconfig>
      <match>
        <edit name="family" mode="append">
          <string>Noto Color Emoji</string>
        </edit>
      </match>
    </fontconfig>
  '';

  # --- システムパッケージ ---
  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    git-lfs
    glow
    usbutils
    pciutils
    drm_info
    edid-decode
    claude-code
    where-is-my-sddm-theme
    usbCDisplayDiagnose
    (writeShellScriptBin "mozc_tool" ''exec ${mozc}/lib/mozc/mozc_tool "$@"'')
  ];

  # --- XDG Portal ---
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-hyprland
      pkgs.xdg-desktop-portal-gtk
    ];
  };

  # --- iPhone USB テザリング ---
  services.usbmuxd.enable = true;

  # --- Docker ---
  virtualisation.docker.enable = false;

  # --- Waydroid (Android コンテナ) ---
  virtualisation.waydroid.enable = true;
  # カーネルに ip_tables モジュールがないため nftables バックエンドを使用
  nixpkgs.overlays = [(final: prev: {
    waydroid = prev.waydroid.override { withNftables = true; };
  })];

  # --- Waydroid TTS 自動設定 ---
  systemd.services.waydroid-tts-setup = {
    description = "Configure Google TTS as default TTS engine in Waydroid";
    after = [ "waydroid-container.service" ];
    requires = [ "waydroid-container.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "waydroid-tts-setup" ''
        for i in $(seq 1 30); do
          if ${pkgs.waydroid}/bin/waydroid status 2>/dev/null | grep -q "RUNNING"; then
            break
          fi
          sleep 2
        done
        sleep 5

        ${pkgs.waydroid}/bin/waydroid shell settings put secure tts_default_synth com.google.android.tts
        ${pkgs.waydroid}/bin/waydroid shell settings put secure tts_enabled_plugins com.google.android.tts
        ${pkgs.waydroid}/bin/waydroid shell settings put system tts_default_lang jpn
        ${pkgs.waydroid}/bin/waydroid shell settings put system tts_default_rate 100
        ${pkgs.waydroid}/bin/waydroid shell settings put system tts_default_pitch 100
      '';
    };
  };

  # --- ydotoold ---
  systemd.services.ydotoold = {
    description = "ydotool daemon";
    after = [ "systemd-modules-load.service" "systemd-udevd.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      RuntimeDirectory = "ydotool";
      RuntimeDirectoryMode = "0755";
      ExecStart = "${pkgs.ydotool}/bin/ydotoold --socket-path /run/ydotool/socket --socket-own 1000:100 --socket-perm 0660";
      Restart = "on-failure";
    };
  };

  # --- Logitech (LogiOps) ---
  boot.kernelModules = [ "hid-logitech-dj" "hid-logitech-hidpp" "uinput" ];
  environment.etc."logid.cfg".text = ''
    devices: ({
      name: "MX Ergo S";
      dpi: 1000;
    });
  '';
  systemd.services.logid = {
    description = "Logitech Configuration Daemon";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.logiops}/bin/logid -c /etc/logid.cfg";
      Restart = "on-failure";
    };
  };

  # --- SSD TRIM ---
  services.fstrim.enable = true;

  # --- udev (Vial キーボード設定ツール用) ---
  services.udev.packages = [ pkgs.vial ];

  # --- MySQL (MariaDB) ---
  services.mysql = {
    enable = true;
    package = pkgs.mariadb;
  };

  # --- ファイアウォール ---
  networking.firewall.enable = true;

  # --- Nix 設定 ---
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;
  nix.settings.keep-derivations = true;
  nix.settings.keep-outputs = true;
  # uv/pip が配置する ruff などの汎用 Linux ELF バイナリを NixOS 上で起動できるようにする。
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      glibc
      stdenv.cc.cc.lib
      zlib
    ];
  };
  nixpkgs.config.allowUnfree = true;

  system.stateVersion = "24.11";
}
