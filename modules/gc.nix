{ config, ... }:

{
  nix.gc.automatic = false;

  systemd.services.nix-gc-generations = {
    description = "Nix GC: keep last 3 generations and collect garbage";
    script = ''
      set -eu
      echo "==> Deleting old system generations (keeping last 3)..."
      ${config.nix.package}/bin/nix-env --delete-generations +3 \
        --profile /nix/var/nix/profiles/system

      echo "==> Deleting old user generations (keeping last 3)..."
      for profile in /nix/var/nix/profiles/per-user/*/profile; do
        [ -e "$profile" ] || continue
        echo "    $profile"
        ${config.nix.package}/bin/nix-env --delete-generations +3 \
          --profile "$profile"
      done

      echo "==> Running nix-store --gc..."
      ${config.nix.package}/bin/nix-store --gc
    '';
    serviceConfig.Type = "oneshot";
    restartIfChanged = false;
  };

  systemd.timers.nix-gc-generations = {
    description = "Timer for generation-based Nix GC";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
    };
  };
}
