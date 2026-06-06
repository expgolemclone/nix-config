{ ... }:

{
  programs.waybar = {
    enable = true;
    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 30;
        spacing = 4;

        modules-left = [ "hyprland/workspaces" "hyprland/window" ];
        modules-center = [ "clock" ];
        modules-right = [ "tray" "privacy" "network" "pulseaudio" "battery" ];

        "hyprland/workspaces" = {
          format = "{id}";
          on-click = "activate";
        };

        "hyprland/window" = {
          max-length = 50;
        };

        clock = {
          format = "{:%H:%M}";
          format-alt = "{:%Y-%m-%d %H:%M}";
          tooltip-format = "<span>{calendar}</span>";
          calendar = {
            mode = "month";
            mode-mon-col = 3;
            on-scroll = 1;
            format = {
              months = "<span color='#ffead3'><b>{}</b></span>";
              weekdays = "<span color='#ffcc66'><b>{}</b></span>";
              today = "<span color='#ff6699'><b>{}</b></span>";
            };
          };
        };

        privacy = {
          icon-size = 14;
          icon-spacing = 5;
          modules = [
            { type = "screenshare"; tooltip = true; }
            { type = "audio-in"; tooltip = true; }
          ];
        };

        tray = {
          icon-size = 16;
          spacing = 5;
        };

        battery = {
          states = {
            good = 95;
            warning = 30;
            critical = 20;
          };
          format = "{icon} {capacity}%";
          format-charging = " {capacity}%";
          format-plugged = " {capacity}%";
          format-alt = "{time} {icon}";
          format-icons = [ "󰂎" "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹" ];
        };

        network = {
          tooltip = true;
          format-wifi = "  {essid}";
          format-ethernet = "󰈀 {ifname}";
          format-disconnected = "󰖪 ";
          tooltip-format = "IP: {ipaddr}/{cidr}\nGateway: {gwaddr}\nSignal: {signaldBm}dBm";
          format-alt = " {bandwidthDownBytes}  {bandwidthUpBytes}";
          interval = 2;
        };

        pulseaudio = {
          format = "{icon} {volume}%";
          format-muted = "󰝟 muted";
          on-click = "pavucontrol -t 3";
          on-scroll-up = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+";
          on-scroll-down = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
          format-icons = {
            headphone = "";
            default = [ "" "" "" ];
          };
        };
      };
    };

    style = ''
      * {
        font-family: "JetBrainsMono Nerd Font", "Noto Sans CJK JP";
        font-size: 13px;
      }

      window#waybar {
        background-color: rgba(30, 30, 46, 0.85);
        color: #cdd6f4;
        border-bottom: 2px solid rgba(137, 180, 250, 0.3);
      }

      #workspaces button {
        padding: 0 5px;
        color: #6c7086;
        border-bottom: 3px solid transparent;
      }

      #workspaces button.active {
        color: #89b4fa;
        border-bottom: 3px solid #89b4fa;
      }

      #workspaces button:hover {
        background: rgba(137, 180, 250, 0.2);
      }

      #clock, #battery, #network, #pulseaudio, #tray {
        padding: 0 10px;
      }

      #battery.charging {
        color: #a6e3a1;
      }

      #battery.warning:not(.charging) {
        color: #fab387;
      }

      #battery.critical:not(.charging) {
        color: #f38ba8;
      }

      #network.disconnected {
        color: #f38ba8;
      }

      #pulseaudio.muted {
        color: #6c7086;
      }
    '';
  };
}
