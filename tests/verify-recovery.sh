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

make_stub() {
  local stub="$1"
  mkdir -p "$stub"
  cat > "$stub/flake.nix" <<'STUB'
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { self, nixpkgs }: {
    overlays.default = final: prev: { };
  };
}
STUB
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
  make_stub "$stub"
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

build_initrd_checks() {
  local stub
  local config
  local initrd_drv
  local initrd_out
  local initrd_image
  local nixpkgs_rev
  local listing="ci-initrd-files.txt"
  local -a candidates=()

  stub="$(mktemp -d)"
  make_stub "$stub"
  config="$repo#nixosConfigurations.nixos"

  initrd_drv="$(
    nix --extra-experimental-features 'nix-command flakes' eval \
      --override-input yazi-fork "path:$stub" \
      --no-write-lock-file --raw "$config" \
      --apply 'n: n.config.specialisation."external-hdd-backup".configuration.system.build.initialRamdisk.drvPath'
  )"
  [ -n "$initrd_drv" ] || { echo 'FAIL initialRamdisk drvPath is empty' >&2; return 1; }

  initrd_out="$(nix-store --realise "$initrd_drv")"
  if [ -f "$initrd_out" ]; then
    initrd_image="$initrd_out"
  elif [ -d "$initrd_out" ]; then
    mapfile -t candidates < <(find "$initrd_out" -maxdepth 2 -type f -name 'initrd*' -print | sort)
    [ "${#candidates[@]}" -eq 1 ] || {
      printf 'FAIL expected one initrd image under %s, found %s\n' "$initrd_out" "${#candidates[@]}" >&2
      find "$initrd_out" -maxdepth 2 -printf '%y %p\n' >&2
      return 1
    }
    initrd_image="${candidates[0]}"
  else
    printf 'FAIL realised initrd output has unexpected type: %s\n' "$initrd_out" >&2
    return 1
  fi
  printf 'PASS built-initrd-output: %s\n' "$initrd_out"
  printf 'PASS built-initrd-image: %s\n' "$initrd_image"

  nixpkgs_rev="$(sed -n 's/^NIXPKGS_REV="\([0-9a-f]\{40\}\)"$/\1/p' "$script")"
  [ -n "$nixpkgs_rev" ] || { echo 'FAIL NIXPKGS_REV is not pinned' >&2; return 1; }
  nix --extra-experimental-features 'nix-command flakes' \
    shell "github:NixOS/nixpkgs/$nixpkgs_rev#dracut" \
    --command lsinitrd "$initrd_image" > "$listing"

  for module_spec in \
    'xhci_pci:xhci[-_]pci\.ko' \
    'sd_mod:sd_mod\.ko' \
    'uas:uas\.ko' \
    'usb_storage:usb-storage\.ko'
  do
    module_name="${module_spec%%:*}"
    module_pattern="${module_spec#*:}"
    grep -Eq "/${module_pattern}(\.(xz|zst|gz))?$" "$listing" \
      || { printf 'FAIL module missing from built initrd: %s\n' "$module_name" >&2; return 1; }
    printf 'PASS built-initrd-module: %s\n' "$module_name"
  done

  sha256sum "$initrd_image" | tee ci-initrd-sha256.txt
  rm -rf "$stub"
  printf 'built initrd inspection passed\n'
}

case "$mode" in
  static) static_checks ;;
  nix) nix_checks ;;
  build-initrd) build_initrd_checks ;;
  all) static_checks; nix_checks; build_initrd_checks ;;
  *) echo "unknown validation mode: $mode" >&2; exit 2 ;;
esac
