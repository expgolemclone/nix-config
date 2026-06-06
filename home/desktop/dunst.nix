{ ... }:

{
  services.dunst = {
    enable = true;
    settings = {
      global = {
        follow = "mouse";
        width = 300;
        height = "(0, 300)";
        origin = "top-right";
        offset = "20x20";
        notification_limit = 20;
        progress_bar = true;
        progress_bar_height = 10;
        progress_bar_frame_width = 0;
        progress_bar_min_width = 125;
        frame_width = 2;
        frame_color = "#89b4fa";
        separator_color = "frame";
        font = "Noto Sans CJK JP 10";
        corner_radius = 10;
        icon_theme = "Adwaita";
        enable_recursive_icon_lookup = true;
      };

      urgency_low = {
        background = "#1e1e2e";
        foreground = "#cdd6f4";
        timeout = 5;
      };

      urgency_normal = {
        background = "#1e1e2e";
        foreground = "#cdd6f4";
        timeout = 10;
      };

      urgency_critical = {
        background = "#1e1e2e";
        foreground = "#cdd6f4";
        frame_color = "#f38ba8";
        timeout = 0;
      };
    };
  };
}
