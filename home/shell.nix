{ pkgs, ... }:

{
  home.file.".local/bin/claude" = {
    executable = true;
    text = ''
      #!${pkgs.runtimeShell}
      exec /run/current-system/sw/bin/claude "$@"
    '';
  };

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    oh-my-zsh = {
      enable = true;
      plugins = [ "git" "sudo" ];
    };
    shellAliases = {
      # eza
      l = "clear && eza -1a --icons=auto";
      la = "clear && eza -1a --icons=auto";
      ls = "clear && eza -1 --icons=auto";
      ll = "eza -lha --icons=auto --sort=name --group-directories-first";
      ld = "eza -lhD --icons=auto";
      tree = "tree -C --dirsfirst";

      # エディタ
      n = "nvim";
      vim = "nvim";
      vc = "code";

      # CLI ツール
      g = "glow";
      claude = "claude --effort max";
      cl = "claude --effort max";
      co = "codex";
      u = "uv run python";

      # ディレクトリ移動
      ".." = "cd ..";
      "..." = "cd ../..";
      ".3" = "cd ../../..";
      ".4" = "cd ../../../..";

      # その他
      c = "clear";
      mkdir = "mkdir -p";

      # NixOS
      rebuild = "sudo nixos-rebuild switch --flake ~/nix-config#nixos";
    };
    initContent = ''
      export TREE_COLORS="di=34:ln=35:so=32:pi=33:ex=31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43"
      export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"

      # Todoist
      t() {
        clear
        case "$1" in
          a|add|m|modify|c|close|d|delete|ap|add-project|quick|sync|gh-import) ;;
          *) todoist sync > /dev/null 2>&1 & ;;
        esac
        if [ "$1" = "hima" ]; then
          shift
          todoist --indent list --filter '##暇な時にやりたい' "$@"
        elif [ "$1" = "l" ] || [ "$1" = "list" ]; then
          shift
          todoist --indent list --filter '!##暇な時にやりたい' "$@"
        elif [ $# -eq 0 ]; then
          todoist --indent list --filter '!##暇な時にやりたい'
        else
          todoist --indent "$@"
        fi
      }

      # todoist dispatch
      tdispatch() { ~/projects/todoist/todoist_dispatch.sh "$@" }

      # land_value_research CLI functions (zsh tab completion via shtab)
      land-value-run() { ~/projects/land_value_research/bin/land-value-run "$@" }
      land-value-rank() { uv run python ~/projects/land_value_research/rank_market_cap_ratio.py "$@" }
    '';
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      format = "$directory$git_branch$git_status$nix_shell$python$nodejs$rust$cmd_duration$line_break$character";

      directory = {
        style = "bold #89b4fa";
        truncation_length = 3;
        truncation_symbol = "…/";
      };

      character = {
        success_symbol = "[❯](bold #a6e3a1)";
        error_symbol = "[❯](bold #f38ba8)";
      };

      git_branch = {
        format = "[$symbol$branch]($style) ";
        style = "bold #cba6f7";
        symbol = " ";
      };

      git_status = {
        format = "[$all_status$ahead_behind]($style) ";
        style = "bold #fab387";
      };

      nix_shell = {
        format = "[$symbol$state( \\($name\\))]($style) ";
        style = "bold #89b4fa";
        symbol = " ";
      };

      python = {
        format = "[$symbol$version]($style) ";
        style = "bold #f9e2af";
        symbol = " ";
      };

      nodejs = {
        format = "[$symbol$version]($style) ";
        style = "bold #a6e3a1";
        symbol = " ";
      };

      rust = {
        format = "[$symbol$version]($style) ";
        style = "bold #fab387";
        symbol = " ";
      };

      cmd_duration = {
        format = "[$duration]($style) ";
        style = "bold #f9e2af";
        min_time = 2000;
      };
    };
  };
}
