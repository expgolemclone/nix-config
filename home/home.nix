{ lib, pkgs, nixvim, ... }:

{
	imports = [
		nixvim.homeModules.nixvim
		./shell.nix
		./git.nix
		./neovim.nix
		./packages.nix
		./yazi.nix
		./cli.nix
		./update-json.nix
		./codex-cli-update-check.nix
		./desktop
	];

	home.username = "exp";
	home.homeDirectory = "/home/exp";
	home.stateVersion = "24.11";

	programs.home-manager.enable = true;

	home.activation.cleanupLegacyJournalUnits = lib.hm.dag.entryBetween [ "reloadSystemd" ] [ "writeBoundary" ] ''
		verboseEcho "Removing legacy journal user units"
		run rm -f \
			"$HOME/.config/systemd/user/fetch-journal.service" \
			"$HOME/.config/systemd/user/journal-fetch.service" \
			"$HOME/.config/systemd/user/journal-fetch.timer" \
			"$HOME/.config/systemd/user/journal-push.service" \
			"$HOME/.config/systemd/user/journal-push.timer" \
			"$HOME/.config/systemd/user/default.target.wants/fetch-journal.service" \
			"$HOME/.config/systemd/user/default.target.wants/journal-fetch.service" \
			"$HOME/.config/systemd/user/timers.target.wants/journal-fetch.timer" \
			"$HOME/.config/systemd/user/timers.target.wants/journal-push.timer"
		run --silence systemctl --user reset-failed \
			fetch-journal.service \
			journal-fetch.service \
			journal-fetch.timer \
			journal-push.service \
			journal-push.timer || true
	'';

	home.activation.cleanupLegacyYdotoolUserUnit = lib.hm.dag.entryBetween [ "reloadSystemd" ] [ "writeBoundary" ] ''
		verboseEcho "Removing legacy ydotool user unit state"
		run --silence systemctl --user stop ydotoold.service || true
		run --silence systemctl --user reset-failed ydotoold.service || true
		run rm -f "$HOME/.ydotool_socket"
	'';

	# --- GTK ---
	gtk = {
		enable = true;
		gtk4.theme = null;
		font = {
			name = "Noto Sans CJK JP";
			size = 10;
		};
	};

	# --- Qt ---
	qt = {
		enable = true;
		platformTheme.name = "qt6ct";
	};
}
