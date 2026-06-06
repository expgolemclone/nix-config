{ pkgs, ... }:

let
  updateScript = pkgs.writeShellScript "update-all-json" ''
    #!/usr/bin/env bash
    set -uo pipefail

    PROJECTS="/home/exp/projects"
    JJ="${pkgs.jujutsu}/bin/jj"

    # Move main to @- if needed, then push if main is ahead of origin
    push_main() {
      local repo="$1"
      cd "$repo"
      # Move main to @- if it's behind (auto-push functions create commits above main)
      local main_rev parent_rev
      main_rev=$($JJ log --no-graph -r 'main' -T 'commit_id' 2>/dev/null || true)
      parent_rev=$($JJ log --no-graph -r '@-' -T 'commit_id' 2>/dev/null || true)
      if [ -n "$main_rev" ] && [ -n "$parent_rev" ] && [ "$main_rev" != "$parent_rev" ]; then
        $JJ bookmark move main --to @- 2>/dev/null || true
      fi
      # Push if main is ahead of origin
      local main_local main_origin
      main_local=$($JJ log --no-graph -r 'main' -T 'commit_id' 2>/dev/null || true)
      main_origin=$($JJ log --no-graph -r 'main@origin' -T 'commit_id' 2>/dev/null || true)
      if [ -n "$main_local" ] && [ -n "$main_origin" ] && [ "$main_local" != "$main_origin" ]; then
        echo "  Pushing $repo"
        $JJ git push 2>/dev/null || true
      fi
    }

    echo "=== $(date -Iseconds) start ==="

    # 1) formula_screening
    echo "--- formula_screening ---"
    cd "$PROJECTS/formula_screening"
    uv run python -m formula_screening screen -s strategies/net_cash_fcf.toml --show-all --json /tmp/fs_dummy.json || echo "FAIL: formula_screening"
    push_main "$PROJECTS/formula_screening"

    # 2) invest_like_legends
    echo "--- invest_like_legends ---"
    cd "$PROJECTS/invest_like_legends"
    uv run python scripts/enrich_investors.py || echo "FAIL: invest_like_legends"
    push_main "$PROJECTS/invest_like_legends"

    # 3) land_value_research
    echo "--- land_value_research ---"
    cd "$PROJECTS/land_value_research"
    uv run python -m src.web --export-json docs/assets/ranking.json || echo "FAIL: land_value_research"
    jj_diff=$($JJ diff --stat -- docs/assets/ 2>/dev/null || true)
    if [ -n "$jj_diff" ] && ! echo "$jj_diff" | grep -q "0 files changed"; then
      $JJ commit -m "Update ranking data" -- docs/assets/ || true
    fi
    push_main "$PROJECTS/land_value_research"

    echo "=== $(date -Iseconds) done ==="
  '';
in

{
  systemd.user.services.update-json = {
    Unit = {
      Description = "Update all project JSON data";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      Environment = "PATH=${pkgs.uv}/bin:${pkgs.jujutsu}/bin:${pkgs.python314}/bin:%h/.nix-profile/bin:/run/current-system/sw/bin";
      ExecStart = "${updateScript}";
    };
  };

  systemd.user.timers.update-json = {
    Unit.Description = "Run update-json after boot";
    Timer = {
      OnBootSec = "2min";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
