{ pkgs, ... }:

let
  catppuccin-mocha = pkgs.writeText "catppuccin-mocha.rasi" ''
    * {
      bg:    #1e1e2e;
      bg-alt: #313244;
      fg:    #cdd6f4;
      fg-alt: #bac2de;
      accent: #b4befe;
      urgent: #f38ba8;

      background-color: transparent;
      text-color: @fg;
      margin:  0;
      padding: 0;
      spacing: 0;
    }

    window {
      width:            600px;
      background-color: @bg;
      border:           2px;
      border-color:     @accent;
      border-radius:    12px;
    }

    mainbox {
      padding: 12px;
    }

    inputbar {
      background-color: @bg-alt;
      border-radius:    8px;
      padding:          8px 12px;
      spacing:          8px;
      children:         [ prompt, entry ];
    }

    prompt {
      text-color: @accent;
    }

    entry {
      placeholder:       "Search...";
      placeholder-color: @fg-alt;
    }

    message {
      margin:           12px 0 0 0;
      background-color: @bg-alt;
      border-radius:    8px;
      padding:          8px 12px;
    }

    listview {
      lines:        8;
      columns:      1;
      fixed-height: false;
      margin:       12px 0 0 0;
      spacing:      4px;
    }

    element {
      padding:       8px 12px;
      border-radius: 8px;
      spacing:       8px;
    }

    element selected {
      background-color: @bg-alt;
    }

    element urgent {
      text-color: @urgent;
    }

    element-icon {
      size:           24px;
      vertical-align: 0.5;
    }

    element-text {
      vertical-align: 0.5;
    }

    element-text selected {
      text-color: @accent;
    }
  '';
in {
  programs.rofi = {
    enable = true;
    package = pkgs.rofi;
    terminal = "kitty";
    extraConfig = {
      modi = "drun,window,run";
      show-icons = true;
      display-drun = "Apps";
      display-window = "Windows";
      display-run = "Run";
      drun-display-format = "{name}";
    };
    theme = "${catppuccin-mocha}";
  };
}
