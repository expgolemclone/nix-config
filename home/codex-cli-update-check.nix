{ pkgs, ... }:

let
  repo = "/home/exp/nix-config";
  stateName = "codex-cli-update-check";
  path = pkgs.lib.makeBinPath [
    pkgs.coreutils
    pkgs.jq
    pkgs.kitty
    pkgs.nix
    pkgs.systemd
  ];
  updateCheckScript = pkgs.writeShellScript "codex-cli-update-check" ''
    set -euo pipefail

    repo="${repo}"
    state_home="''${XDG_STATE_HOME:-$HOME/.local/state}"
    state_dir="$state_home/${stateName}"
    state_file="$state_dir/last-trigger.json"
    prompt_file="$state_dir/update-prompt.md"
    trigger_tmp="$state_dir/current-trigger.json.tmp"

    nix_bin="${pkgs.nix}/bin/nix"
    jq_bin="${pkgs.jq}/bin/jq"
    kitty_bin="${pkgs.kitty}/bin/kitty"
    codex_bin="${pkgs.codex}/bin/codex"
    systemctl_bin="${pkgs.systemd}/bin/systemctl"

    dry_run=0
    force_trigger=0

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --dry-run)
          dry_run=1
          ;;
        --force-trigger)
          force_trigger=1
          ;;
        *)
          printf 'Unknown argument: %s\n' "$1" >&2
          exit 2
          ;;
      esac
      shift
    done

    mkdir -p "$state_dir"

    current_codex="$("$nix_bin" eval --raw "$repo#nixosConfigurations.nixos.pkgs.codex.version")"
    current_claude="$("$nix_bin" eval --raw "$repo#nixosConfigurations.nixos.pkgs.claude-code.version")"
    latest_codex="$("$nix_bin" eval --refresh --raw github:NixOS/nixpkgs/nixos-unstable#codex.version)"
    latest_claude="$(NIXPKGS_ALLOW_UNFREE=1 "$nix_bin" eval --refresh --impure --raw github:NixOS/nixpkgs/nixos-unstable#claude-code.version)"
    current_nixpkgs_rev="$("$nix_bin" flake metadata --json "$repo" | "$jq_bin" -r '.locks.nodes.nixpkgs.locked.rev // "unknown"')"
    latest_nixpkgs_rev="$("$nix_bin" flake metadata --refresh --json github:NixOS/nixpkgs/nixos-unstable | "$jq_bin" -r '.revision // "unknown"')"

    needs_update=0
    if [ "$current_codex" != "$latest_codex" ] || [ "$current_claude" != "$latest_claude" ]; then
      needs_update=1
    fi
    if [ "$force_trigger" -eq 1 ]; then
      needs_update=1
    fi

    if [ "$needs_update" -eq 0 ]; then
      rm -f "$state_file" "$trigger_tmp"
      printf 'codex and claude-code are current for nixos-unstable: codex=%s claude-code=%s\n' "$current_codex" "$current_claude"
      exit 0
    fi

    "$jq_bin" -n \
      --arg currentCodex "$current_codex" \
      --arg latestCodex "$latest_codex" \
      --arg currentClaude "$current_claude" \
      --arg latestClaude "$latest_claude" \
      --arg currentRev "$current_nixpkgs_rev" \
      --arg latestRev "$latest_nixpkgs_rev" \
      --arg forced "$force_trigger" \
      '{
        current_codex: $currentCodex,
        latest_codex: $latestCodex,
        current_claude_code: $currentClaude,
        latest_claude_code: $latestClaude,
        current_nixpkgs_rev: $currentRev,
        latest_nixpkgs_rev: $latestRev,
        forced: ($forced == "1")
      }' > "$trigger_tmp"

    if [ "$dry_run" -eq 0 ] && [ -f "$state_file" ] && cmp -s "$trigger_tmp" "$state_file"; then
      rm -f "$trigger_tmp"
      printf 'update prompt already opened for this nixos-unstable version set\n'
      exit 0
    fi

    cat > "$prompt_file" <<EOF
Codex and Claude Code are behind the current nixos-unstable package versions.

Versions:
- codex: current ''${current_codex}, nixos-unstable ''${latest_codex}
- claude-code: current ''${current_claude}, nixos-unstable ''${latest_claude}
- current locked nixpkgs rev: ''${current_nixpkgs_rev}
- latest nixos-unstable rev: ''${latest_nixpkgs_rev}

Work in /home/exp/nix-config.

Mandatory instructions:
- Answer in Japanese.
- Read RULES.md before changing anything.
- Use jj, not git. Use the Codex root jj wrapper scripts for every mutating jj operation.
- Update the Nix-managed CLI versions by updating flake inputs, starting with: nix flake update nixpkgs home-manager nixvim
- Do not update or touch the local yazi-fork flake input unless it is strictly required to repair evaluation.
- Do not run codex self-update or Claude Code self-update; these CLIs are managed by Nix here.
- Verify with nixos-rebuild build --flake .#nixos.
- Commit with jj, then run sudo -n nixos-rebuild switch --flake .#nixos.
- After switch succeeds, integrate the work into main and push with the jj wrapper flow.
EOF

    if [ "$dry_run" -eq 1 ]; then
      cat "$prompt_file"
      rm -f "$trigger_tmp"
      exit 0
    fi

    if [ -z "''${WAYLAND_DISPLAY:-}" ] && [ -z "''${DISPLAY:-}" ]; then
      while IFS='=' read -r name value; do
        case "$name" in
          DBUS_SESSION_BUS_ADDRESS|DISPLAY|HYPRLAND_INSTANCE_SIGNATURE|WAYLAND_DISPLAY|XDG_CURRENT_DESKTOP|XDG_SESSION_DESKTOP|XDG_SESSION_TYPE)
            export "$name=$value"
            ;;
        esac
      done < <("$systemctl_bin" --user show-environment 2>/dev/null || true)
    fi

    if [ -z "''${WAYLAND_DISPLAY:-}" ] && [ -z "''${DISPLAY:-}" ]; then
      printf 'No graphical display is available; not launching kitty.\n' >&2
      rm -f "$trigger_tmp"
      exit 0
    fi
    if [ -z "''${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
      printf 'No DBUS_SESSION_BUS_ADDRESS is available; not launching kitty.\n' >&2
      rm -f "$trigger_tmp"
      exit 0
    fi

    mv "$trigger_tmp" "$state_file"

    exec "$kitty_bin" -T "Codex CLI updates" -d "$repo" -e "$codex_bin" -C "$repo" "$(cat "$prompt_file")"
  '';
in

{
  systemd.user.services.codex-cli-update-check = {
    Unit = {
      Description = "Check Codex and Claude Code package updates";
      After = [ "network-online.target" "graphical-session.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      Environment = "PATH=${path}:%h/.local/bin:%h/.nix-profile/bin:/run/current-system/sw/bin";
      ExecStart = "${updateCheckScript}";
    };
  };

  systemd.user.timers.codex-cli-update-check = {
    Unit.Description = "Check Codex and Claude Code package updates daily";
    Timer = {
      OnBootSec = "5min";
      OnCalendar = "daily";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
