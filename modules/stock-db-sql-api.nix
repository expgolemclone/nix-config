{ lib, pkgs, ... }:

let
  projectRoot = "/home/exp/projects/stock_db";
  dbPath = "${projectRoot}/var/db/stocks.db";
  environmentFile = "/etc/stock-db/sql-api.env";
  user = "exp";
  host = "127.0.0.1";
  port = 8788;
  urlFile = "${projectRoot}/var/run/sql-api-public-url";
  candidateUrlFile = "${urlFile}.candidate";
  logFile = "${projectRoot}/var/log/sql-api-public-cloudflared.log";
  targetUrl = "http://127.0.0.1:${toString port}";

  sqlApiPackages = [
    pkgs.cargo
    pkgs.rustc
    pkgs.stdenv.cc
    pkgs.uv
  ];

  quickTunnelPackages = [
    pkgs.cloudflared
    pkgs.coreutils
    pkgs.curl
    pkgs.gawk
  ];

  quickTunnelScript = pkgs.writeShellScript "stock-db-sql-api-quick-tunnel" ''
    set -euo pipefail

    project_root=${lib.escapeShellArg projectRoot}
    url_file=${lib.escapeShellArg urlFile}
    candidate_url_file=${lib.escapeShellArg candidateUrlFile}
    log_file=${lib.escapeShellArg logFile}
    target_url=${lib.escapeShellArg targetUrl}
    url_ready_timeout=90
    public_ready_timeout=300
    public_health_successes=2
    monitor_interval=30
    monitor_failure_limit=6
    restart_delay=5

    mkdir -p "$(dirname "$url_file")" "$(dirname "$log_file")" "$project_root/var/run"

    cloudflared_pid=
    log_pid=
    fifo=

    cleanup_current() {
      set +e
      if [ -n "$cloudflared_pid" ] && kill -0 "$cloudflared_pid" 2>/dev/null; then
        kill "$cloudflared_pid" 2>/dev/null
        wait "$cloudflared_pid" 2>/dev/null
      fi
      if [ -n "$log_pid" ] && kill -0 "$log_pid" 2>/dev/null; then
        kill "$log_pid" 2>/dev/null
        wait "$log_pid" 2>/dev/null
      fi
      if [ -n "$fifo" ]; then
        rm -f "$fifo"
      fi
      cloudflared_pid=
      log_pid=
      fifo=
    }

    on_signal() {
      cleanup_current
      exit 143
    }

    wait_for_candidate_url() {
      deadline=$((SECONDS + url_ready_timeout))
      until [ -s "$candidate_url_file" ]; do
        if [ "$SECONDS" -ge "$deadline" ]; then
          return 1
        fi
        if ! kill -0 "$cloudflared_pid" 2>/dev/null; then
          return 1
        fi
        sleep 1
      done
    }

    wait_for_public_health() {
      url="$1"
      deadline=$((SECONDS + public_ready_timeout))
      successes=0
      until [ "$successes" -ge "$public_health_successes" ]; do
        if curl -fsS --max-time 15 "$url/health" >/dev/null 2>&1; then
          successes=$((successes + 1))
          sleep 2
          continue
        fi
        successes=0
        if [ "$SECONDS" -ge "$deadline" ]; then
          return 1
        fi
        if ! kill -0 "$cloudflared_pid" 2>/dev/null; then
          return 1
        fi
        sleep 1
      done
    }

    monitor_public_health() {
      url="$1"
      failures=0
      while kill -0 "$cloudflared_pid" 2>/dev/null; do
        sleep "$monitor_interval"
        if curl -fsS --max-time 15 "$url/health" >/dev/null 2>&1; then
          failures=0
          continue
        fi
        failures=$((failures + 1))
        if [ "$failures" -ge "$monitor_failure_limit" ]; then
          return 1
        fi
      done
      return 1
    }

    start_cloudflared() {
      fifo="$(mktemp -u "$project_root/var/run/cloudflared-output.XXXXXX")"
      mkfifo "$fifo"

      awk -v url_file="$candidate_url_file" '
        {
          print
          fflush()
          if (match($0, /https:\/\/[[:alnum:]-]+\.trycloudflare\.com/)) {
            url = substr($0, RSTART, RLENGTH)
            print url > url_file
            close(url_file)
          }
        }
      ' < "$fifo" | tee -a "$log_file" &
      log_pid=$!

      cloudflared tunnel --no-autoupdate --protocol http2 --url "$target_url" > "$fifo" 2>&1 &
      cloudflared_pid=$!
    }

    trap on_signal INT TERM

    while true; do
      rm -f "$url_file" "$candidate_url_file"
      start_cloudflared

      if wait_for_candidate_url; then
        candidate_url="$(tr -d '\n' < "$candidate_url_file")"
        if wait_for_public_health "$candidate_url"; then
          printf '%s\n' "$candidate_url" > "$url_file"
          if monitor_public_health "$candidate_url"; then
            exit 0
          fi
          rm -f "$url_file"
          printf 'Quick Tunnel URL became unhealthy: %s\n' "$candidate_url" | tee -a "$log_file"
          cleanup_current
          sleep "$restart_delay"
          continue
        fi
        printf 'Quick Tunnel URL was not reachable: %s\n' "$candidate_url" | tee -a "$log_file"
      else
        printf 'cloudflared did not produce a Quick Tunnel URL\n' | tee -a "$log_file"
      fi

      cleanup_current
      sleep "$restart_delay"
    done
  '';
in

{
  assertions = [
    {
      assertion = environmentFile != "";
      message = "stock-db-sql-api environmentFile must be non-empty.";
    }
  ];

  systemd.services.stock-db-sql-api = {
    description = "Authenticated Stock DB SQL API";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = sqlApiPackages;
    serviceConfig = {
      Type = "simple";
      User = user;
      WorkingDirectory = projectRoot;
      EnvironmentFile = environmentFile;
      Restart = "on-failure";
      RestartSec = "5min";
    };
    script = ''
      exec ${pkgs.uv}/bin/uv run serve-sql-api \
        --host ${lib.escapeShellArg host} \
        --port ${toString port} \
        --db ${lib.escapeShellArg dbPath}
    '';
  };

  systemd.services.stock-db-sql-api-quick-tunnel = {
    description = "Cloudflare Quick Tunnel for Stock DB SQL API";
    after = [ "network-online.target" "stock-db-sql-api.service" ];
    wants = [ "network-online.target" ];
    requires = [ "stock-db-sql-api.service" ];
    wantedBy = [ "multi-user.target" ];
    path = quickTunnelPackages;
    serviceConfig = {
      Type = "simple";
      User = user;
      WorkingDirectory = projectRoot;
      ExecStart = "${quickTunnelScript}";
      Restart = "on-failure";
      RestartSec = "5min";
    };
  };
}
