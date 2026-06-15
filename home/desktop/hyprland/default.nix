{ pkgs, ... }:

let
  workspaceNums = builtins.genList (i: i + 1) 3;
  wsKey = n: if n == 10 then "0" else toString n;
  wsBinds = builtins.concatMap (n: [
    "Alt, ${wsKey n}, workspace, ${toString n}"
    "Alt+Shift, ${wsKey n}, movetoworkspace, ${toString n}"
    "$mainMod+Alt, ${wsKey n}, movetoworkspacesilent, ${toString n}"
  ]) workspaceNums;

  modifier-reset = pkgs.writeShellScriptBin "modifier-reset" ''
    # 全modifierキーをpress(1)→release(0)して強制リセット
    # keycodes: LSHIFT=42 RSHIFT=54 LCTRL=29 RCTRL=97 LALT=56 RALT=100 LMETA=125 RMETA=126
    ${pkgs.ydotool}/bin/ydotool key 42:1 42:0 54:1 54:0 29:1 29:0 97:1 97:0 56:1 56:0 100:1 100:0 125:1 125:0 126:1 126:0
  '';

  hypr-cursor-warp = pkgs.writeShellScriptBin "hypr-cursor-warp" ''
    socket="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

    ${pkgs.socat}/bin/socat -U - UNIX-CONNECT:"$socket" | while IFS= read -r line; do
      case "$line" in
        "activewindowv2>>"*)
          win=$(hyprctl activewindow -j 2>/dev/null)
          [ -z "$win" ] || [ "$win" = "null" ] && continue

          win_x=$(echo "$win" | ${pkgs.jq}/bin/jq '.at[0]')
          win_y=$(echo "$win" | ${pkgs.jq}/bin/jq '.at[1]')
          win_w=$(echo "$win" | ${pkgs.jq}/bin/jq '.size[0]')
          win_h=$(echo "$win" | ${pkgs.jq}/bin/jq '.size[1]')

          cursor=$(hyprctl cursorpos -j 2>/dev/null)
          cur_x=$(echo "$cursor" | ${pkgs.jq}/bin/jq '.x')
          cur_y=$(echo "$cursor" | ${pkgs.jq}/bin/jq '.y')

          # カーソルが新ウィンドウ内ならスキップ（マウスクリック）
          if [ "$cur_x" -ge "$win_x" ] && [ "$cur_x" -le "$((win_x + win_w))" ] && \
             [ "$cur_y" -ge "$win_y" ] && [ "$cur_y" -le "$((win_y + win_h))" ]; then
            continue
          fi

          # ウィンドウ下端の中央にカーソル移動
          new_x=$((win_x + win_w / 2))
          new_y=$((win_y + win_h - 5))
          hyprctl dispatch movecursor "$new_x" "$new_y"
          ;;
      esac
    done
  '';

  hypr-apply-wallpaper = pkgs.writeShellScriptBin "hypr-apply-wallpaper" ''
    wallpaper="${./wallpapers/black.png}"

    for _ in $(${pkgs.coreutils}/bin/seq 1 60); do
      ready_outputs=$(${pkgs.hyprland}/bin/hyprctl monitors -j 2>/dev/null | ${pkgs.jq}/bin/jq '[.[] | select(.disabled == false)] | length' 2>/dev/null || echo 0)

      if ${pkgs.awww}/bin/awww query >/dev/null 2>&1 && [ "$ready_outputs" -ge 1 ]; then
        ${pkgs.coreutils}/bin/sleep 2
        exec ${pkgs.awww}/bin/awww img "$wallpaper" --resize crop --filter Lanczos3 --transition-type fade --transition-duration 2
      fi

      ${pkgs.coreutils}/bin/sleep 0.5
    done

    exec ${pkgs.awww}/bin/awww img "$wallpaper" --resize crop --filter Lanczos3 --transition-type none
  '';

  hypr-session-restore = pkgs.writeShellScriptBin "hypr-session-restore" ''
    export PATH=${pkgs.hyprland}/bin:${pkgs.jq}/bin:${pkgs.kitty}/bin:${pkgs.coreutils}/bin:$PATH
    exec ${pkgs.bash}/bin/bash ${./hypr-session-restore.sh}
  '';

  hypr-monitor-layout = pkgs.writeShellScriptBin "hypr-monitor-layout" ''
    export PATH=${pkgs.hyprland}/bin:${pkgs.jq}/bin:${pkgs.socat}/bin:${pkgs.coreutils}/bin:$PATH
    exec ${pkgs.bash}/bin/bash ${./hypr-monitor-layout.sh}
  '';
in
{
  home.packages = [ hypr-monitor-layout ];

  wayland.windowManager.hyprland = {
    enable = true;
    configType = "hyprlang";
    settings = {

      # --- モニター ---
      monitor = [
        "eDP-1, disable"
        "desc:ASUSTek COMPUTER INC ASUS VA32U 0x00015DB6, 3840x2160@30, 0x0, 1.5, transform, 1"
        "desc:LG Electronics LG HDR 4K 601NTRLN4694, 3840x2160@30, 1440x0, 1.5, transform, 1"
        "desc:LG Electronics LG Ultra HD 0x00009D2A, 3840x2160@30, 2880x0, 1.5, transform, 3"
      ];

      # --- 環境変数 ---
      env = [
        "XCURSOR_SIZE, 32"
        "XDG_CURRENT_DESKTOP, Hyprland"
        "XDG_SESSION_TYPE, wayland"
        "XDG_SESSION_DESKTOP, Hyprland"
        "QT_QPA_PLATFORM, wayland;xcb"
        "QT_QPA_PLATFORMTHEME, qt6ct"
        "QT_WAYLAND_DISABLE_WINDOWDECORATION, 1"
        "QT_AUTO_SCREEN_SCALE_FACTOR, 1"
        "MOZ_ENABLE_WAYLAND, 1"
        "GDK_SCALE, 1"
      ];

      # --- 自動起動 ---
      exec-once = [
        "dbus-update-activation-environment --systemd --all"
        "systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE"
        "waybar"
        "blueman-applet"
        "udiskie --no-automount --smart-tray"
        "nm-applet --indicator"
        "dunst"
        "wl-paste --type text --watch cliphist store"
        "wl-paste --type image --watch cliphist store"
        "fcitx5 -d"
        "awww-daemon"
        "${hypr-apply-wallpaper}/bin/hypr-apply-wallpaper"
        "hyprsunset -t 2000"
        "${hypr-session-restore}/bin/hypr-session-restore"
        "${hypr-cursor-warp}/bin/hypr-cursor-warp"
      ];

      # --- 入力 ---
      input = {
        kb_layout = "jp";
        kb_options = "altwin:swap_alt_win";
        follow_mouse = 1;
        touchpad = {
          natural_scroll = false;
        };
        sensitivity = 1;
        force_no_accel = false;
        accel_profile = "flat";
        numlock_by_default = true;
      };

      # --- レイアウト ---
      dwindle = {
        preserve_split = true;
      };

      master = {
        new_status = "master";
      };

      # --- 装飾 ---
      decoration = {
        rounding = 10;
        blur = {
          enabled = true;
          size = 8;
          passes = 3;
        };
      };

      # --- その他 ---
      misc = {
        vrr = 0;
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
        force_default_wallpaper = 0;
        mouse_move_enables_dpms = true;
        key_press_enables_dpms = true;
      };

      ecosystem = {
        no_donation_nag = true;
      };

      # --- カーソル ---
      cursor = {
        no_warps = true;
        sync_gsettings_theme = true;
      };

      xwayland = {
        enabled = true;
        force_zero_scaling = true;
      };

      # --- 変数 ---
      "$mainMod" = "Super";
      "$term" = "kitty";
      "$editor" = "code";
      "$file" = "dolphin";
      "$browser" = "google-chrome-stable";

      # --- キーバインド ---
      bind = [
        # ウィンドウ操作
        "Alt, Q, killactive,"
        "Ctrl, E, killactive,"
        "Alt+Shift, M, movetoworkspacesilent, special:minimized"
        "Alt+Shift, T, togglefloating,"
        "Alt+Shift, F, fullscreen, 1"
        "Alt+Shift, R, exec, hyprctl reload"
        "Alt, X, layoutmsg, togglesplit"
        "Alt, Y, layoutmsg, orientationcycle"
        "$mainMod, Delete, exit,"
        "$mainMod, G, togglegroup,"
        "$mainMod, L, exec, hyprlock"

        # アプリケーション
        "$mainMod, E, exec, $file"
        "$mainMod, C, exec, $editor"
        "$mainMod, F, exec, $browser"
        "$mainMod, T, exec, kitty -d ~/projects -e zsh -lc \"ls -a; exec zsh\""
        "Ctrl+Shift, Escape, exec, kitty -e btop"

        # rofi
        "$mainMod, A, exec, pkill -x rofi || rofi -show drun"
        "$mainMod, Tab, exec, pkill -x rofi || rofi -show window"
        "$mainMod, R, exec, pkill -x rofi || rofi -show run"

        # スクリーンショット
        "$mainMod+Shift, S, exec, grimblast --notify copy area"
        "$mainMod+Alt, P, exec, grimblast --notify copy output"
        ", Print, exec, grimblast --notify copy screen"

        # カラーピッカー
        "$mainMod+Shift, P, exec, hyprpicker -a"

        # Waydroid
        "Alt, D, exec, hypr-window-invert-toggle"

        # クリップボード
        "$mainMod, V, exec, cliphist list | rofi -dmenu | cliphist decode | wl-copy && sleep 0.1 && if [ \"$(hyprctl activewindow -j | jq -r '.class')\" = \"kitty\" ]; then kitty @ --to unix:/tmp/kitty-$(hyprctl activewindow -j | jq -r '.pid') action paste_from_clipboard; else wtype -M ctrl v -m ctrl; fi"

        # ロック / ログアウト
        "$mainMod, Backspace, exec, wlogout"

        # waybar トグル
        "Ctrl+Alt, W, exec, killall -SIGUSR1 waybar"

        # フォーカス移動 (hjkl)
        "Alt, H, movefocus, l"
        "Alt, J, movefocus, d"
        "Alt, K, movefocus, u"
        "Alt, L, movefocus, r"

        # ウィンドウ移動 (hjkl)
        "Alt+Shift, H, movewindow, l"
        "Alt+Shift, J, movewindow, d"
        "Alt+Shift, K, movewindow, u"
        "Alt+Shift, L, movewindow, r"

        # グループ操作
        "Alt, Left, moveintogroup, l"
        "Alt, Down, moveintogroup, d"
        "Alt, Up, moveintogroup, u"
        "Alt, Right, moveintogroup, r"
        "Alt, Semicolon, moveoutofgroup,"
        "Alt, bracketleft, changegroupactive, b"
        "Alt, bracketright, changegroupactive, f"

        # スクラッチパッド
        "$mainMod+Alt, S, movetoworkspacesilent, special"
        "$mainMod, S, togglespecialworkspace,"

        # モディファイヤリセット（ZMK Bluetooth スティック対策）
        "$mainMod, colon, exec, ${modifier-reset}/bin/modifier-reset"
      ] ++ wsBinds;

      # 音量・輝度（リピート対応）
      bindel = [
        ", F11, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ", F12, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
        ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ", XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
        ", XF86MonBrightnessUp, exec, brightnessctl set +5%"
        ", XF86MonBrightnessDown, exec, brightnessctl set 5%-"
      ];

      # 音量ミュート・メディア（ロック画面でも動作）
      bindl = [
        ", F10, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ", XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioPause, exec, playerctl play-pause"
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPrev, exec, playerctl previous"
      ];

      # リサイズ
      binde = [
        "Alt, equal, resizeactive, 30 0"
        "Alt, minus, resizeactive, -30 0"
        "Alt+Shift, equal, resizeactive, 0 -30"
        "Alt+Shift, minus, resizeactive, 0 30"
      ];

      # マウスバインド
      bindm = [
        "$mainMod, mouse:272, movewindow"
        "$mainMod, mouse:273, resizewindow"
        "$mainMod, Z, movewindow"
        "$mainMod, X, resizewindow"
      ];

      # --- ウィンドウルール ---
      windowrule = [
        # 透明度
        "match:class ^(code-oss)$, opacity 0.80 0.80"
        "match:class ^([Cc]ode)$, opacity 0.80 0.80"
        "match:class ^(kitty)$, opacity 1.00 1.00"
        "match:class ^(org.kde.dolphin)$, opacity 0.80 0.80"
        "match:class ^(org.pulseaudio.pavucontrol)$, opacity 0.80 0.70"
        "match:class ^(blueman-manager)$, opacity 0.80 0.70"
        "match:class ^(nm-applet)$, opacity 0.80 0.70"
        "match:class ^(nm-connection-editor)$, opacity 0.80 0.70"
        "match:class ^(polkit-gnome-authentication-agent-1)$, opacity 0.80 0.70"

        # フロート
        "match:class ^(org.kde.dolphin)$, match:title ^(Progress Dialog — Dolphin)$, float on"
        "match:class ^(org.kde.dolphin)$, match:title ^(Copying — Dolphin)$, float on"
        "match:class ^(kitty)$, match:title ^(btop)$, float on"
        "match:class ^(vlc)$, float on"
        "match:class ^(org.pulseaudio.pavucontrol)$, float on"
        "match:class ^(blueman-manager)$, float on"
        "match:class ^(nm-applet)$, float on"
        "match:class ^(nm-connection-editor)$, float on"

        # 共通モーダル
        "match:title ^(Open)$, float on"
        "match:title ^(Choose Files)$, float on"
        "match:title ^(Save As)$, float on"
        "match:title ^(Confirm to replace files)$, float on"
        "match:title ^(File Operation Progress)$, float on"
        "match:class ^(xdg-desktop-portal-gtk)$, float on"

      ];

      # --- レイヤールール ---
      layerrule = [
        "blur on, ignore_alpha 0, match:namespace ^(rofi)$"
        "blur on, ignore_alpha 0, match:namespace ^(notifications)$"
      ];
    };
  };

  # hyprlock
  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        disable_loading_bar = true;
        grace = 3;
        hide_cursor = true;
        no_fade_in = false;
      };

      background = [{
        path = "screenshot";
        blur_passes = 3;
        blur_size = 8;
      }];

      "input-field" = [{
        size = "200, 50";
        outline_thickness = 3;
        dots_size = 0.33;
        dots_spacing = 0.15;
        dots_center = false;
        dots_rounding = -1;
        outer_color = "rgb(b4befe)";
        inner_color = "rgb(313244)";
        font_color = "rgb(cdd6f4)";
        fade_on_empty = true;
        fade_timeout = 1000;
        placeholder_text = "<span foreground=\"#bac2de\"><i>Password...</i></span>";
        hide_input = false;
        rounding = -1;
        check_color = "rgb(fab387)";
        fail_color = "rgb(f38ba8)";
        fail_text = "<i>$FAIL <b>($ATTEMPTS)</b></i>";
        fail_timeout = 2000;
        fail_transition = 300;
        capslock_color = "rgb(f9e2af)";
        numlock_color = -1;
        bothlock_color = -1;
        invert_numlock = false;
        swap_font_color = false;
        position = "0, -20";
        halign = "center";
        valign = "center";
      }];

      label = [
        {
          text = "cmd[update:1000] echo \"$(date +\"%H:%M\")\"";
          color = "rgb(cdd6f4)";
          font_size = 90;
          font_family = "JetBrainsMono Nerd Font Bold";
          position = "0, 200";
          halign = "center";
          valign = "center";
        }
        {
          text = "cmd[update:43200000] echo \"$(date +\"%A, %d %B %Y\")\"";
          color = "rgb(bac2de)";
          font_size = 25;
          font_family = "Noto Sans CJK JP";
          position = "0, 120";
          halign = "center";
          valign = "center";
        }
        {
          text = "Hi, $USER";
          color = "rgb(bac2de)";
          font_size = 20;
          font_family = "Noto Sans CJK JP";
          position = "0, -120";
          halign = "center";
          valign = "center";
        }
      ];
    };
  };

  # セッション自動保存
  systemd.user.services.hypr-session-save = {
    Unit.Description = "Save Hyprland session state";
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "hypr-session-save-wrapper" ''
        # Hyprland が動いている場合のみ実行
        if [ -d /run/user/$(id -u)/hypr ]; then
          hypr-session-save
        fi
      ''}";
    };
  };

  systemd.user.timers.hypr-session-save = {
    Unit.Description = "Periodically save Hyprland session state";
    Timer = {
      OnUnitActiveSec = "1min";
      OnStartupSec = "1min";
    };
    Install.WantedBy = [ "timers.target" ];
  };

  # polkit agent
  systemd.user.services.polkit-gnome-agent = {
    Unit.Description = "polkit-gnome-authentication-agent-1";
    Install.WantedBy = [ "graphical-session.target" ];
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
    };
  };

  # Dynamic cursor theme switching based on pixel luminance
  systemd.user.services.hypr-dynamic-cursor = {
    Unit = {
      Description = "Switch cursor theme based on pixel luminance under cursor";
      PartOf = [ "graphical-session.target" ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.python3}/bin/python3 ${./hypr-dynamic-cursor.py}";
      Environment = "PATH=${pkgs.hyprland}/bin:${pkgs.grim}/bin:${pkgs.dconf}/bin:${pkgs.glib.bin}/bin:%h/.nix-profile/bin:/run/current-system/sw/bin";
      Restart = "on-failure";
      RestartSec = "2";
    };
  };

  systemd.user.services.hypr-monitor-layout = {
    Unit = {
      Description = "Switch Hyprland monitor layout for docked and laptop modes";
      PartOf = [ "graphical-session.target" ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
    Service = {
      Type = "simple";
      ExecStart = "${hypr-monitor-layout}/bin/hypr-monitor-layout";
      Restart = "always";
      RestartSec = "2";
    };
  };
}
