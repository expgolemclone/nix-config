#!/usr/bin/env bash
set -Eeuo pipefail

repo="${1:-.}"
script="$repo/recover-external-hdd"

[ -f "$script" ] || { echo "missing $script" >&2; exit 1; }
bash -n "$script"

nixpkgs_rev="$(sed -n 's/^NIXPKGS_REV="\([0-9a-f]\{40\}\)"$/\1/p' "$script")"
[ -n "$nixpkgs_rev" ] || { echo 'NIXPKGS_REV is not a pinned 40-character revision' >&2; exit 1; }

nix --extra-experimental-features 'nix-command flakes' \
  shell "github:NixOS/nixpkgs/$nixpkgs_rev#shellcheck" \
  --command shellcheck "$script"

if grep -En '(^|[^[:alnum:]_])(mkfs|wipefs|fdisk|sfdisk|parted|fsck|badblocks)([^[:alnum:]_]|$)' "$script"; then
  echo 'destructive disk command found in recovery script' >&2
  exit 1
fi

grep -Fq -- '--system "$SYSTEM_PATH"' "$script"
grep -Fq 'initrd-module-' "$script"
grep -Fq 'installed-initrd-hash' "$script"
grep -Fq 'github-write-proof' "$script"

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

nix_base=(nix --extra-experimental-features 'nix-command flakes')
config="$repo#nixosConfigurations.nixos"

nix_eval() {
  "${nix_base[@]}" eval \
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

printf 'recovery validation passed\n'
