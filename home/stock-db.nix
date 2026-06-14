{ pkgs, ... }:

let
	projectRoot = "/home/exp/projects/stock_db";
	# uv run が呼ぶ先(下流 repo スクリプトが jj を使うため jujutsu も必須)
	pathEnv = "PATH=${pkgs.uv}/bin:${pkgs.jujutsu}/bin:${pkgs.python314}/bin:%h/.nix-profile/bin:/run/current-system/sw/bin";
in
{
	systemd.user.services.stock-db-price-refresh = {
		Unit = {
			Description = "Stock DB scheduled price refresh";
			After = [ "network-online.target" ];
			Wants = [ "network-online.target" ];
		};
		Service = {
			Type = "oneshot";
			WorkingDirectory = projectRoot;
			Environment = pathEnv;
			ExecStart = "${pkgs.uv}/bin/uv run scheduled-refresh-prices --headless";
			Restart = "on-failure";
			RestartSec = "5min";
		};
	};

	systemd.user.timers.stock-db-price-refresh = {
		Unit.Description = "Run stock price refresh on JPX business days at 16:00 JST";
		Timer = {
			OnCalendar = "Mon..Fri *-*-* 16:00:00 Asia/Tokyo";
			Persistent = true;
		};
		Install.WantedBy = [ "timers.target" ];
	};

	systemd.user.services.stock-db-edinet-refresh = {
		Unit = {
			Description = "Refresh EDINET XBRL data and downstream JSON";
			After = [ "network-online.target" ];
			Wants = [ "network-online.target" ];
		};
		Service = {
			Type = "oneshot";
			WorkingDirectory = projectRoot;
			Environment = pathEnv;
			ExecStart = "${pkgs.uv}/bin/uv run scheduled-refresh-edinet --days 7";
			Restart = "on-failure";
			RestartSec = "5min";
		};
	};

	systemd.user.timers.stock-db-edinet-refresh = {
		Unit.Description = "Run EDINET XBRL refresh daily at 18:30 JST";
		Timer = {
			OnCalendar = "*-*-* 18:30:00 Asia/Tokyo";
			Persistent = true;
		};
		Install.WantedBy = [ "timers.target" ];
	};

	systemd.user.services.stock-db-downstream-refresh = {
		Unit = {
			Description = "Refresh downstream project JSON data after price update";
			# 元 unit に network-online 依存は無かったので追加しない。price-refresh の完了のみ待つ。
			After = [ "stock-db-price-refresh.service" ];
		};
		Service = {
			Type = "oneshot";
			WorkingDirectory = projectRoot;
			Environment = pathEnv;
			ExecStart = "${pkgs.uv}/bin/uv run python services/downstream_refresh.py";
			Restart = "on-failure";
			RestartSec = "5min";
		};
	};

	systemd.user.timers.stock-db-downstream-refresh = {
		Unit.Description = "Run downstream JSON refresh on weekdays at 16:05 JST";
		Timer = {
			OnCalendar = "Mon..Fri *-*-* 16:05:00 Asia/Tokyo";
			Persistent = true;
		};
		Install.WantedBy = [ "timers.target" ];
	};
}
