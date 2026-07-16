#!/usr/bin/env bash
set -Eeuo pipefail

mode="${1:-all}"
repo="${2:-.}"
script="$repo/recover-external-hdd"

[ -f "$script" ] || { echo "missing $script" >&2; exit 1; }

static_checks() {
  if grep -En '(^|[^[:alnum:]_])(mkfs|wipefs|fdisk|sfdisk|parted|fsck|badblocks)([^[:alnum:]_]|$)' "$script"; then
    echo 'destructive disk command found in recovery script' >&2
    exit 1
  fi

  grep -Fq -- '--system "$SYSTEM_PATH"' "$script"
  grep -Fq 'initrd-module-' "$script"
  grep -Fq 'installed-initrd-hash' "$script"
  grep -Fq 'github-write-proof' "$script"
  grep -Fq 'mount -o remount,rw "$TARGET/boot"' "$script"
  printf 'static recovery checks passed\n'
}

nix_checks() {
  local stub
  local config
  local root_device
  local boot_device
  local modules
  local root_options

  stub="$(mktemp -d)"
  trap 'rm -rf "$stub"' EXIT
  cat > "$stub/flake.nix" <<'STUB'
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { self, nixpkgs }: {
    overlays.default = final: prev: { };
  };
}
STUB

  config="$repo#nixosConfigurations.nixos"

  nix_eval() {
    nix --extra-experimental-features 'nix-command flakes' eval \
      --override-input yazi-fork "path:$stub" \
      --no-write-lock-file "$@"
  }

  root_device="$(nix_eval --raw "$config" \
    --apply 'n: n.config.specialisation."external-hdd-backup".configuration.fileSystems."/".device')"
  boot_device="$(nix_eval --raw "$config" \
    --apply 'n: n.config.specialisation."external-hdd-backup".configuration.fileSystems."/boot".device')"
  modules="$(nix_eval --json "$config" \
    --apply 'n: n.config.specialisation."external-hdd-backup".configuration.boot.initrd.kernelModules')"
  root_options="$(nix_eval --json "$config" \
    --apply 'n: n.config.specialisation."external-hdd-backup".configuration.fileSystems."/".options')"

  [ "$root_device" = '/dev/disk/by-uuid/741133ee-fa8d-4674-8809-2735e197acae' ]
  [ "$boot_device" = '/dev/disk/by-uuid/BACA-0001' ]
  for module in xhci_pci sd_mod uas usb_storage; do
    printf '%s' "$modules" | jq -e --arg module "$module" 'index($module) != null' >/dev/null
  done
  printf '%s' "$root_options" | jq -e 'index("x-systemd.device-timeout=5min") != null' >/dev/null

  nix_eval --raw \
    "$repo#nixosConfigurations.nixos.config.system.build.toplevel.drvPath" >/dev/null
  printf 'Nix recovery checks passed\n'
}

case "$mode" in
  static) static_checks ;;
  nix) nix_checks ;;
  all) static_checks; nix_checks ;;
  *) echo "unknown validation mode: $mode" >&2; exit 2 ;;
esac
