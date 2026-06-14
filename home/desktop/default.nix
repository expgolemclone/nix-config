{ pkgs, ... }:

let
  hyprWindowInvertToggle = pkgs.writeShellScriptBin "hypr-window-invert-toggle" ''
    set -eu

    hyprctl=${pkgs.hyprland}/bin/hyprctl
    jq=${pkgs.jq}/bin/jq
    state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/hypr-window-invert"
    shader="$state_dir/active.frag"
    previous="$state_dir/previous-screen-shader"
    legacy_shader="$XDG_RUNTIME_DIR/hypr-window-invert/active.frag"

    notify() {
      ${pkgs.libnotify}/bin/notify-send "Hyprland" "$1" 2>/dev/null || true
    }

    sanitize_shader() {
      case "''${1:-}" in
        ""|"[[EMPTY]]")
          printf '%s' '[[EMPTY]]'
          ;;
        *)
          if [ -f "$1" ]; then
            printf '%s' "$1"
          else
            printf '%s' '[[EMPTY]]'
          fi
          ;;
      esac
    }

    mkdir -p "$state_dir"

    current_raw="$("$hyprctl" getoption decoration:screen_shader -j 2>/dev/null | "$jq" -r '.str // "[[EMPTY]]"' || printf '[[EMPTY]]')"
    current="$(sanitize_shader "$current_raw")"
    if [ "$current_raw" = "$shader" ] || [ "$current_raw" = "$legacy_shader" ]; then
      restore="$(sanitize_shader "$(cat "$previous" 2>/dev/null || printf '[[EMPTY]]')")"
      "$hyprctl" keyword decoration:screen_shader "$restore" >/dev/null
      notify "Window inversion: off"
      printf '%s\n' "Hyprland window inversion: off"
      exit 0
    fi

    win="$("$hyprctl" activewindow -j 2>/dev/null || true)"
    if ! printf '%s\n' "$win" | "$jq" -e '.at and .size' >/dev/null 2>&1; then
      notify "No active window"
      printf '%s\n' "No active Hyprland window" >&2
      exit 1
    fi

    monitors="$("$hyprctl" monitors -j 2>/dev/null)"
    if ! rect="$(printf '%s\n' "$monitors" | "$jq" -r --argjson win "$win" '
      def max2(a;b): if a > b then a else b end;
      def min2(a;b): if a < b then a else b end;
      ($win.monitor // null) as $monitorId |
      [ .[] | select(.id == $monitorId) | . as $m |
        if ($m.transform >= 4) then error("unsupported monitor transform") else
          (if ($m.transform == 1 or $m.transform == 3) then $m.height else $m.width end) as $sourceW |
          (if ($m.transform == 1 or $m.transform == 3) then $m.width else $m.height end) as $sourceH |
          (if ($m.transform == 1 or $m.transform == 3) then $sourceH else $sourceW end) as $targetW |
          (if ($m.transform == 1 or $m.transform == 3) then $sourceW else $sourceH end) as $targetH |
          (($win.at[0] - $m.x) * $m.scale) as $sx |
          (($win.at[1] - $m.y) * $m.scale) as $sy |
          ($win.size[0] * $m.scale) as $sw |
          ($win.size[1] * $m.scale) as $sh |
          (if $m.transform == 0 then {x: $sx, y: $sy, w: $sw, h: $sh}
           elif $m.transform == 1 then {x: ($sourceH - $sy - $sh), y: $sx, w: $sh, h: $sw}
           elif $m.transform == 2 then {x: ($sourceW - $sx - $sw), y: ($sourceH - $sy - $sh), w: $sw, h: $sh}
           elif $m.transform == 3 then {x: $sy, y: ($sourceW - $sx - $sw), w: $sh, h: $sw}
           else error("unsupported monitor transform") end) as $r |
          [$m.id, max2(0; $r.x), max2(0; $r.y), min2($targetW; $r.x + $r.w), min2($targetH; $r.y + $r.h)] | @tsv
        end
      ][0] // empty
    ')"; then
      notify "Unsupported monitor transform"
      printf '%s\n' "Unsupported monitor transform" >&2
      exit 1
    fi

    if [ -z "$rect" ]; then
      notify "Active window monitor not found"
      printf '%s\n' "Active window monitor not found" >&2
      exit 1
    fi

    IFS="$(printf '\t')" read -r monitor_id x1 y1 x2 y2 <<EOF
$rect
EOF

    if [ -z "$monitor_id" ] || [ -z "$x1" ] || [ -z "$y1" ] || [ -z "$x2" ] || [ -z "$y2" ]; then
      notify "Failed to calculate window rectangle"
      printf '%s\n' "Failed to calculate active window rectangle" >&2
      exit 1
    fi

    cat > "$shader" <<EOF
#version 300 es

precision highp float;
in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;

uniform sampler2D tex;
uniform vec2 fullSize;
uniform int wl_output;

const int targetOutput = $monitor_id;
const vec4 targetRect = vec4($x1, $y1, $x2, $y2);

void main() {
    vec4 color = texture(tex, v_texcoord);
    vec2 pixel = v_texcoord * fullSize;

    if (wl_output == targetOutput &&
        pixel.x >= targetRect.x && pixel.x <= targetRect.z &&
        pixel.y >= targetRect.y && pixel.y <= targetRect.w) {
        color.rgb = vec3(1.0) - color.rgb;
    }

    fragColor = color;
}
EOF

    printf '%s' "$current" > "$previous"
    "$hyprctl" keyword decoration:screen_shader "$shader" >/dev/null
    notify "Window inversion: on"
    printf '%s\n' "Hyprland window inversion: on"
  '';
  waydroidInvertToggle = pkgs.writeShellScriptBin "waydroid-invert-toggle" ''
    exec ${hyprWindowInvertToggle}/bin/hypr-window-invert-toggle "$@"
  '';
  ydotoolWrapped = pkgs.writeShellScriptBin "ydotool" ''
    export YDOTOOL_SOCKET=/run/ydotool/socket
    exec ${pkgs.ydotool}/bin/ydotool "$@"
  '';
in

{
  imports = [
    ./cursor.nix
    ./fcitx5.nix
    ./hyprland
    ./waybar.nix
    ./kitty.nix
    ./dunst.nix
    ./rofi.nix
    ./wlogout.nix
  ];

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "google-chrome.desktop";
      "x-scheme-handler/http" = "google-chrome.desktop";
      "x-scheme-handler/https" = "google-chrome.desktop";
      "x-scheme-handler/about" = "google-chrome.desktop";
      "x-scheme-handler/unknown" = "google-chrome.desktop";
    };
  };

  home.sessionVariables = {
    YDOTOOL_SOCKET = "/run/ydotool/socket";
  };

  home.packages =
    with pkgs;
    [
      # Wayland / Hyprland ユーティリティ
      brightnessctl
      cliphist
      grim
      grimblast
      hyprpicker
      hyprsunset
      playerctl
      slurp
      swappy
      awww
      udiskie
      wl-clipboard
      hyprWindowInvertToggle
      waydroidInvertToggle
      ydotoolWrapped
      wtype

      # GUI アプリ
      kdePackages.dolphin
      pavucontrol

      # ネットワーク / Bluetooth (systray)
      networkmanagerapplet

      # セッション保存・復元
      (writeShellScriptBin "hypr-session-save" (builtins.readFile ./hyprland/hypr-session-save.sh))
      (writeShellScriptBin "hypr-session-restore" (builtins.readFile ./hyprland/hypr-session-restore.sh))
    ];
}
