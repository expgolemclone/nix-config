{ pkgs, ... }:

{
  programs.btop = {
    enable = true;
    settings = {
      color_theme = "catppuccin_mocha";
      theme_background = false;
      vim_keys = true;
    };
  };

  programs.eza = {
    enable = true;
  };

  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;
    settings = {
      git_protocol = "https";
      prompt = "enabled";
      color_labels = "disabled";
      aliases = {
        co = "pr checkout";
        w = "issue list";
        wa = ''!sh -c 'if [ -z "$1" ]; then gh issue create --assignee @me --editor; else gh issue create --assignee @me --title "$1"; fi' --'';
        wd = ''issue close "$1"'';
        we = ''!sh -c 'tmp=$(mktemp); gh issue view "$1" --json title,body -q ".title + \"\\n\\n\" + .body" > "$tmp"; ''${EDITOR:-vim} "$tmp"; title=$(head -1 "$tmp"); body=$(tail -n +3 "$tmp"); gh issue edit "$1" -t "$title" -b "$body"; rm "$tmp"' --'';
      };
    };
  };

  home.file.".local/bin/gh" = {
    executable = true;
    text = ''
      #!${pkgs.runtimeShell}
      set -euo pipefail

      real_gh="${pkgs.gh}/bin/gh"
      git="${pkgs.git}/bin/git"
      jj="${pkgs.jujutsu}/bin/jj"

      die() {
        printf 'gh: %s\n' "$*" >&2
        exit 1
      }

      has_git_context() {
        if [ -n "''${GIT_DIR:-}" ]; then
          return 0
        fi

        "$git" rev-parse --is-inside-work-tree >/dev/null 2>&1
      }

      setup_jj_git_context() {
        if has_git_context; then
          return 1
        fi

        jj_root="$("$jj" --ignore-working-copy --quiet root 2>/dev/null || true)"
        if [ -z "$jj_root" ]; then
          return 1
        fi

        jj_git_dir="$("$jj" --ignore-working-copy --quiet git root 2>/dev/null || true)"
        if [ -z "$jj_git_dir" ]; then
          return 1
        fi

        export GIT_WORK_TREE="$jj_root"
        export GIT_DIR="$jj_git_dir"
        return 0
      }

      is_jj_pr_checkout_command() {
        case "''${1:-}" in
          co)
            return 0
            ;;
          pr)
            case "''${2:-}" in
              checkout|co)
                return 0
                ;;
            esac
            ;;
        esac

        return 1
      }

      jj_pr_checkout() {
        local selector=""
        local bookmark=""
        local force=0
        local detach=0

        while [ "$#" -gt 0 ]; do
          case "$1" in
            -b|--branch)
              shift
              if [ "$#" -eq 0 ]; then
                die 'missing value for --branch'
              fi
              bookmark="$1"
              ;;
            --branch=*)
              bookmark="''${1#--branch=}"
              if [ -z "$bookmark" ]; then
                die 'missing value for --branch'
              fi
              ;;
            -f|--force)
              force=1
              ;;
            --detach)
              detach=1
              ;;
            --recurse-submodules)
              die '--recurse-submodules is not supported in jj-backed gh pr checkout'
              ;;
            -R|--repo|--repo=*)
              die '--repo is not supported in jj-backed gh pr checkout'
              ;;
            --)
              shift
              if [ "$#" -eq 0 ]; then
                break
              fi
              if [ -n "$selector" ]; then
                die 'only one PR selector is supported'
              fi
              selector="$1"
              shift
              if [ "$#" -ne 0 ]; then
                die "unexpected argument: $1"
              fi
              break
              ;;
            -*)
              die "unsupported option for jj-backed gh pr checkout: $1"
              ;;
            *)
              if [ -n "$selector" ]; then
                die 'only one PR selector is supported'
              fi
              selector="$1"
              ;;
          esac
          shift
        done

        if [ -z "$selector" ]; then
          die 'jj-backed gh pr checkout requires a PR number, URL, or branch'
        fi

        if [ "$detach" -eq 1 ] && [ -n "$bookmark" ]; then
          die '--detach cannot be combined with --branch'
        fi

        local pr_number
        local pr_title
        pr_number="$("$real_gh" pr view "$selector" --json number --jq .number)"
        pr_title="$("$real_gh" pr view "$selector" --json title --jq .title)"

        if [[ ! "$pr_number" =~ ^[0-9]+$ ]]; then
          die "could not resolve PR selector: $selector"
        fi

        local remote_bookmark="pr/$pr_number"
        local remote_ref="refs/remotes/origin/$remote_bookmark"
        "$git" fetch origin "+refs/pull/$pr_number/head:$remote_ref"
        "$jj" --repository "$GIT_WORK_TREE" git import

        local remote_revset="exactly(remote_bookmarks(exact:\"$remote_bookmark\", exact:\"origin\"), 1)"
        local parent_commit
        parent_commit="$("$jj" --repository "$GIT_WORK_TREE" log --no-graph -r "$remote_revset" -T 'commit_id ++ "\n"')"
        if [ -z "$parent_commit" ]; then
          die "could not import PR #$pr_number into jj"
        fi

        if [ "$detach" -eq 0 ]; then
          if [ -z "$bookmark" ]; then
            bookmark="$remote_bookmark"
          fi

          local -a bookmark_args=(bookmark set --revision "$parent_commit")
          if [ "$force" -eq 1 ]; then
            bookmark_args+=(--allow-backwards)
          fi
          bookmark_args+=(-- "$bookmark")
          "$jj" --repository "$GIT_WORK_TREE" "''${bookmark_args[@]}"
        fi

        "$jj" --repository "$GIT_WORK_TREE" new -m "PR #$pr_number: $pr_title" "$parent_commit"
        printf 'Checked out PR #%s in jj as a new working change\n' "$pr_number"
      }

      jj_context=0
      if setup_jj_git_context; then
        jj_context=1
      fi

      if [ "$jj_context" -eq 1 ] && is_jj_pr_checkout_command "$@"; then
        case "''${1:-}" in
          co)
            shift
            ;;
          pr)
            shift 2
            ;;
        esac
        jj_pr_checkout "$@"
        exit 0
      fi

      exec "$real_gh" "$@"
    '';
  };

  home.file.".local/bin/jj" = {
    executable = true;
    text = ''
      #!${pkgs.runtimeShell}
      set -euo pipefail

      real_jj="${pkgs.jujutsu}/bin/jj"
      guarded_command=""
      declare -a global_args=()

      parse_command() {
        while [ "$#" -gt 0 ]; do
          case "$1" in
            -R|--repository|--config|--config-file|--color|--at-operation)
              global_args+=("$1")
              shift
              if [ "$#" -eq 0 ]; then
                return
              fi
              global_args+=("$1")
              ;;
            --repository=*|--config=*|--config-file=*|--color=*|--at-operation=*)
              global_args+=("$1")
              ;;
            --ignore-working-copy|--no-integrate-operation|--ignore-immutable|--debug|--quiet|--no-pager)
              global_args+=("$1")
              ;;
            -*)
              return
              ;;
            *)
              guarded_command="$1"
              return
              ;;
          esac
          shift
        done
      }

      inspect_revision() {
        "$real_jj" "''${global_args[@]}" --ignore-working-copy log --no-graph -r "$1" -T 'if(self.empty(), "empty", "nonempty") ++ "\n" ++ if(description.trim(), "described", "undescribed") ++ "\n" ++ change_id.short() ++ " " ++ commit_id.short() ++ "\n"'
      }

      field() {
        printf '%s\n' "$1" | sed -n "$2p"
      }

      reject_and_undo() {
        local revision="$1"
        local details="$2"
        local empty_state="$3"
        local description_state="$4"
        local target
        local reason=""

        target="$(field "$details" 3)"
        if [ "$empty_state" = "empty" ]; then
          reason="empty commit"
        fi
        if [ "$description_state" = "undescribed" ]; then
          if [ -n "$reason" ]; then
            reason="$reason, missing commit message"
          else
            reason="missing commit message"
          fi
        fi

        if ! "$real_jj" "''${global_args[@]}" undo >/dev/null 2>&1; then
          printf 'jj: rejected %s %s (%s), but automatic undo failed\n' "$revision" "$target" "$reason" >&2
          exit 1
        fi

        printf 'jj: rejected %s %s (%s). The operation was undone.\n' "$revision" "$target" "$reason" >&2
        exit 1
      }

      guard_committed_parent() {
        local details
        local empty_state
        local description_state

        details="$(inspect_revision '@-')"
        empty_state="$(field "$details" 1)"
        description_state="$(field "$details" 2)"

        if [ "$empty_state" = "empty" ] || [ "$description_state" = "undescribed" ]; then
          reject_and_undo '@-' "$details" "$empty_state" "$description_state"
        fi
      }

      guard_current_description() {
        local details
        local empty_state
        local description_state

        details="$(inspect_revision '@')"
        empty_state="$(field "$details" 1)"
        description_state="$(field "$details" 2)"

        if [ "$empty_state" = "nonempty" ] && [ "$description_state" = "undescribed" ]; then
          reject_and_undo '@' "$details" "$empty_state" "$description_state"
        fi
      }

      parse_command "$@"

      case "$guarded_command" in
        commit|ci)
          "$real_jj" "$@"
          guard_committed_parent
          ;;
        describe|desc)
          "$real_jj" "$@"
          guard_current_description
          ;;
        *)
          exec "$real_jj" "$@"
          ;;
      esac
    '';
  };

  xdg.configFile."jj/conf.d/nix-config.toml".text = ''
    [git]
    private-commits = 'empty() | description(regex:"^\\s*$")'
  '';

  programs.fastfetch = {
    enable = true;
    settings = {
      logo.type = "small";
      display.separator = " -> ";
      modules = [
        "title" "separator" "os" "host" "kernel" "uptime"
        "packages" "shell" "display" "de" "wm" "terminal"
        "cpu" "gpu" "memory" "disk" "break" "colors"
      ];
    };
  };

  home.sessionPath = [
    "$HOME/go/bin"
    "$HOME/.local/bin"
    "$HOME/.npm-global/bin"
  ];

  programs.go = {
    enable = true;
    env.GOPATH = "go";
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.yt-dlp = {
    enable = true;
  };
}
