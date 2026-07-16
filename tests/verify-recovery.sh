#!/usr/bin/env bash
set -Eeuo pipefail

mode="${1:-all}"
repo="${2:-.}"
script="$repo/recover-external-hdd"

[ -f "$script" ] || { echo "missing $script" >&2; exit 1; }

assert_equal() {
  local name="$1"
  local actual="$2"
  local expected="$3"
  if [ "$actual" != "$expected" ]; then
    printf 'FAIL %s: expected %q, got %q\n' "$name" "$expected" "$actual" >&2
    return 1
  fi
  printf 'PASS %s: %s\n' "$name" "$actual"
}

assert_json_contains() {
  local name="$1"
  local json="$2"
  local value="$3"
  if ! printf '%s' "$json" | jq -e --arg value "$value" 'index($value) != null' >/dev/null; then
    printf 'FAIL %s: %q not found in %s\n' "$name" "$value" "$json" >&2
    return 1
  fi
  printf 'PASS %s: %s\n' "$name" "$value"
}

static_checks() {
  local initrd_hash_line
  local esp_rw_line
  local install_line

  if grep -En '(^|[^[:alnum:]_])(mkfs|wipefs|fdisk|sfdisk|parted|fsck|badblocks)([^[:alnum:]_]|$)' "$script"; then
    echo 'destructive disk command found in recovery script' >&2
    exit 1
  fi

  grep -Fq -- '--system "$SYSTEM_PATH"' "$script"
  grep -Fq 'initrd-module-' "$script"
  grep -Fq 'installed-initrd-hash' "$script"
  grep -Fq 'github-write-proof' "$script"

  initrd_hash_line="$(grep -nF 'pass built-initrd-hash' "$script" | head -n 1 | cut -d: -f1)"
  esp_rw_line="$(grep -nF 'mount -o remount,rw "$TARGET/boot"' "$script" | head -n 1 | cut -d: -f1)"
  install_line="$(grep -n '^nixos-install \\' "$script" | head -n 1 | cut -d: -f1)"
  [ -n "$initrd_hash_line" ] && [ -n "$esp_rw_line" ] && [ -n "$install_line" ]
  if ! (( initrd_hash_line < esp_rw_line && esp_rw_line < install_line )); then
    printf 'unsafe ordering: initrd-hash=%s esp-rw=%s install=%s\n' \
      "$initrd_hash_line" "$esp_rw_line" "$install_line" >&2
    exit 1
  fi

  printf 'PASS ordering: initrd verified before ESP write and installation\n'
  printf 'static recovery checks passed\n'
}

nix_checks() {
  local stub
  local config
  local root_device
  local boot_device
  local modules
  local root_options
  local drv_path
  local specialisation_drv
  local initrd_drv

  stub="$(mktemp -d)"
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

  assert_equal root-device "$root_device" '/dev/disk/by-uuid/741133ee-fa8d-4674-8809-2735e197acae'
  assert_equal boot-device "$boot_device" '/dev/disk/by-uuid/BACA-0001'
  for module in xhci_pci sd_mod uas usb_storage; do
    assert_json_contains "initrd-module-$module" "$modules" "$module"
  done
  assert_json_contains root-initrd-mount "$root_options" 'x-initrd.mount'
  assert_json_contains root-device-timeout "$root_options" 'x-systemd.device-timeout=5min'

  drv_path="$(nix_eval --raw \
    "$repo#nixosConfigurations.nixos.config.system.build.toplevel.drvPath")"
  specialisation_drv="$(nix_eval --raw "$config" \
    --apply 'n: n.config.specialisation."external-hdd-backup".configuration.system.build.toplevel.drvPath')"
  initrd_drv="$(nix_eval --raw "$config" \
    --apply 'n: n.config.specialisation."external-hdd-backup".configuration.system.build.initialRamdisk.drvPath')"

  [ -n "$drv_path" ] || { echo 'FAIL toplevel drvPath is empty' >&2; return 1; }
  [ -n "$specialisation_drv" ] || { echo 'FAIL specialisation drvPath is empty' >&2; return 1; }
  [ -n "$initrd_drv" ] || { echo 'FAIL specialisation initialRamdisk drvPath is empty' >&2; return 1; }
  printf 'PASS toplevel-drv: %s\n' "$drv_path"
  printf 'PASS specialisation-drv: %s\n' "$specialisation_drv"
  printf 'PASS initialRamdisk-drv: %s\n' "$initrd_drv"
  printf 'Nix recovery checks passed\n'

  rm -rf "$stub"
}

case "$mode" in
  static) static_checks ;;
  nix) nix_checks ;;
  all) static_checks; nix_checks ;;
  *) echo "unknown validation mode: $mode" >&2; exit 2 ;;
esac
