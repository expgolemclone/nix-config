{ ... }:

{
  programs.kitty = {
    enable = true;
    font = {
      name = "JetBrainsMono Nerd Font";
      size = 12;
    };
    keybindings = {
      "ctrl+shift+n" = "launch --type=os-window --cwd=current";
    };
    settings = {
      allow_remote_control = "socket-only";
      listen_on = "unix:/tmp/kitty-{kitty_pid}";
      background_opacity = "1.0";
      confirm_os_window_close = 0;
      enable_audio_bell = false;
      scrollback_lines = 10000;
      background = "#000000";
      cursor_shape = "beam";
      window_padding_width = 8;
    };
    # Catppuccin Mocha テーマ
    themeFile = "Catppuccin-Mocha";
  };
}
