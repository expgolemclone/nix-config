{ lib, pkgs, ... }:

let
  backupRootUuid = "741133ee-fa8d-4674-8809-2735e197acae";
  externalHddDisk = "/dev/disk/by-id/usb-BUFFALO_External_HDD_0040473060601346-0:0";
  recoveryAddress = "192.168.137.2/24";
  githubAccount = "expgolemclone";
  authorizedKeysPath = "/run/recovery-ssh/authorized_keys";

  configureRecoveryAddress = pkgs.writeShellApplication {
    name = "configure-recovery-address";
    runtimeInputs = with pkgs; [
      coreutils
      gawk
      iproute2
      networkmanager
    ];
    text = ''
      set -euo pipefail

      mapfile -t interfaces < <(
        nmcli -t -f DEVICE,TYPE,STATE device status \
          | awk -F: '$2 == "ethernet" && ($3 == "connected" || $3 == "connecting") { print $1 }'
      )

      if [ "''${#interfaces[@]}" -ne 1 ]; then
        printf 'expected exactly one connected Ethernet interface, found %s\n' "''${#interfaces[@]}" >&2
        printf '%s\n' "''${interfaces[@]:-}" >&2
        exit 1
      fi

      interface="''${interfaces[0]}"
      ip address replace ${recoveryAddress} dev "$interface"
      printf 'recovery address %s configured on %s\n' '${recoveryAddress}' "$interface"
    '';
  };

  fetchRecoveryAuthorizedKeys = pkgs.writeShellApplication {
    name = "fetch-recovery-authorized-keys";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      gnugrep
      openssh
    ];
    text = ''
      set -euo pipefail

      : "''${RUNTIME_DIRECTORY:?RUNTIME_DIRECTORY is not set}"
      tmp="$(mktemp "$RUNTIME_DIRECTORY/authorized_keys.XXXXXX")"
      trap 'rm -f "$tmp"' EXIT

      curl \
        --fail \
        --silent \
        --show-error \
        --location \
        --proto '=https' \
        --tlsv1.2 \
        --connect-timeout 10 \
        --max-time 30 \
        'https://github.com/${githubAccount}.keys' \
        --output "$tmp"

      [ -s "$tmp" ] || {
        printf 'GitHub returned no public SSH keys for ${githubAccount}\n' >&2
        exit 1
      }

      if grep -Ev \
        '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com) [A-Za-z0-9+/=]+$' \
        "$tmp" >/dev/null; then
        printf 'GitHub returned an unsupported or malformed SSH key line\n' >&2
        exit 1
      fi

      ssh-keygen -l -f "$tmp" >/dev/null
      install -m 0600 -o root -g root "$tmp" '${authorizedKeysPath}'
      printf 'installed %s GitHub SSH key lines for ${githubAccount}\n' "$(wc -l < '${authorizedKeysPath}')"
    '';
  };

  recoveryStatus = pkgs.writeShellApplication {
    name = "recovery-status";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      iproute2
      systemd
      util-linux
    ];
    text = ''
      set -euo pipefail

      printf '## Host\n'
      printf 'hostname: %s\n' "$(hostname)"
      printf 'kernel: %s\n' "$(uname -srmo)"

      printf '\n## Network\n'
      ip -brief address

      printf '\n## Mounted root and boot\n'
      findmnt -no SOURCE,FSTYPE,OPTIONS /
      findmnt -no SOURCE,FSTYPE,OPTIONS /boot

      printf '\n## Block devices\n'
      lsblk -e 7 -o NAME,PATH,TRAN,SIZE,TYPE,FSTYPE,LABEL,UUID,MODEL,SERIAL,MOUNTPOINTS

      printf '\n## Stable disk paths\n'
      find /dev/disk/by-id -maxdepth 1 -type l -printf '%f -> %l\n' | sort

      printf '\n## Recovery services\n'
      systemctl --no-pager --full status \
        recovery-network-address.service \
        recovery-ssh-authorized-keys.service \
        sshd.service
    '';
  };

  recoverySsdDiagnose = pkgs.writeShellApplication {
    name = "recovery-ssd-diagnose";
    runtimeInputs = with pkgs; [
      coreutils
      gawk
      gnugrep
      nvme-cli
      smartmontools
      systemd
      util-linux
    ];
    text = ''
      set -euo pipefail

      fail() {
        printf 'recovery-ssd-diagnose: %s\n' "$*" >&2
        exit 1
      }

      if [ "$#" -ne 2 ] || [ "$1" != "--target" ]; then
        fail 'usage: recovery-ssd-diagnose --target /dev/disk/by-id/<ssd>'
      fi

      target="$2"
      case "$target" in
        /dev/disk/by-id/nvme-*|/dev/disk/by-id/ata-*|/dev/disk/by-id/wwn-*) ;;
        *) fail 'target must be an explicit /dev/disk/by-id disk path' ;;
      esac

      [ -b "$target" ] || fail "$target is not a block device"
      [ "$target" != '${externalHddDisk}' ] || fail 'the external backup HDD cannot be diagnosed as the SSD target'

      target_real="$(readlink -f "$target")"
      [ -b "$target_real" ] || fail "could not resolve $target"

      if lsblk -nr -o MOUNTPOINTS "$target_real" | grep -q '[^[:space:]]'; then
        fail "$target has mounted filesystems; diagnostics require an unmounted target"
      fi

      model="$(lsblk -dn -o MODEL "$target_real" | xargs)"
      serial="$(lsblk -dn -o SERIAL "$target_real" | xargs)"
      size="$(lsblk -dn -o SIZE "$target_real" | xargs)"
      transport="$(lsblk -dn -o TRAN "$target_real" | xargs)"
      [ -n "$serial" ] || fail 'target disk has no readable serial number'

      timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
      report_dir="/var/log/recovery"
      report="$report_dir/ssd-diagnose-$timestamp.log"
      install -d -m 0700 "$report_dir"

      exec > >(tee "$report") 2>&1
      printf 'target-by-id: %s\n' "$target"
      printf 'target-device: %s\n' "$target_real"
      printf 'model: %s\n' "$model"
      printf 'serial: %s\n' "$serial"
      printf 'size: %s\n' "$size"
      printf 'transport: %s\n' "$transport"
      printf 'time-utc: %s\n\n' "$timestamp"

      printf '## lsblk\n'
      lsblk -o NAME,PATH,TRAN,SIZE,TYPE,FSTYPE,LABEL,UUID,MODEL,SERIAL,MOUNTPOINTS "$target_real"

      printf '\n## udev\n'
      udevadm info --query=property --name="$target_real" | sort

      diagnostic_rc=0

      printf '\n## SMART\n'
      smartctl --xall "$target_real" || diagnostic_rc=$?
      printf 'smartctl-exit: %s\n' "$diagnostic_rc"

      case "$target_real" in
        /dev/nvme*)
          printf '\n## NVMe SMART log\n'
          nvme_rc=0
          nvme smart-log "$target_real" || nvme_rc=$?
          printf 'nvme-smart-log-exit: %s\n' "$nvme_rc"
          [ "$nvme_rc" -eq 0 ] || diagnostic_rc=1
          printf '\n## NVMe error log\n'
          nvme_rc=0
          nvme error-log "$target_real" || nvme_rc=$?
          printf 'nvme-error-log-exit: %s\n' "$nvme_rc"
          [ "$nvme_rc" -eq 0 ] || diagnostic_rc=1
          ;;
        *)
          [ "$transport" != "nvme" ] || fail "NVMe transport did not resolve to an /dev/nvme device: $target_real"
          ;;
      esac

      printf '\nreport: %s\n' "$report"
      exit "$diagnostic_rc"
    '';
  };

  recoveryRestoreSsd = pkgs.writeShellApplication {
    name = "recovery-restore-ssd";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      util-linux
    ];
    text = ''
      set -euo pipefail

      fail() {
        printf 'recovery-restore-ssd: %s\n' "$*" >&2
        exit 1
      }

      if [ "$#" -ne 5 ] \
        || [ "$1" != "--target" ] \
        || [ "$3" != "--confirm-serial" ] \
        || [ "$5" != "--destroy-target-ssd" ]; then
        fail 'usage: recovery-restore-ssd --target /dev/disk/by-id/<ssd> --confirm-serial <serial> --destroy-target-ssd'
      fi

      target="$2"
      confirmed_serial="$4"
      case "$target" in
        /dev/disk/by-id/nvme-*|/dev/disk/by-id/ata-*|/dev/disk/by-id/wwn-*) ;;
        *) fail 'target must be an explicit /dev/disk/by-id disk path' ;;
      esac

      [ -b "$target" ] || fail "$target is not a block device"
      [ "$target" != '${externalHddDisk}' ] || fail 'target must not be the external backup HDD'
      [ "$(findmnt -n -o UUID /)" = '${backupRootUuid}' ] \
        || fail 'boot the external-hdd-backup specialisation before restoring an SSD'

      target_real="$(readlink -f "$target")"
      model="$(lsblk -dn -o MODEL "$target_real" | xargs)"
      serial="$(lsblk -dn -o SERIAL "$target_real" | xargs)"
      size="$(lsblk -dn -o SIZE "$target_real" | xargs)"
      [ -n "$serial" ] || fail 'target disk has no readable serial number'
      [ "$serial" = "$confirmed_serial" ] \
        || fail "serial confirmation mismatch: target is $serial, confirmation was $confirmed_serial"

      if lsblk -nr -o MOUNTPOINTS "$target_real" | grep -q '[^[:space:]]'; then
        fail "$target has mounted filesystems"
      fi

      printf 'DESTROY TARGET SSD\n'
      printf 'by-id: %s\n' "$target"
      printf 'device: %s\n' "$target_real"
      printf 'model: %s\n' "$model"
      printf 'serial: %s\n' "$serial"
      printf 'size: %s\n' "$size"

      exec /run/current-system/sw/bin/restore-ssd-from-hdd --target "$target" --destroy-target-ssd
    '';
  };
in
{
  environment.systemPackages = [
    recoveryStatus
    recoverySsdDiagnose
    recoveryRestoreSsd
  ];

  specialisation.external-hdd-backup.configuration = {
    networking.hostName = lib.mkForce "nixos-recovery";

    networking.firewall = {
      allowedTCPPorts = lib.mkForce [ 22 ];
      allowedTCPPortRanges = lib.mkForce [ ];
      allowedUDPPorts = lib.mkForce [ ];
      allowedUDPPortRanges = lib.mkForce [ ];
    };

    services.openssh = {
      enable = true;
      openFirewall = false;
      authorizedKeysFiles = lib.mkForce [ authorizedKeysPath ];
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
        AuthenticationMethods = "publickey";
        AllowUsers = [ "exp" ];
      };
    };

    systemd.services.recovery-network-address = {
      description = "Configure the fixed direct-LAN recovery address";
      after = [ "NetworkManager.service" ];
      requires = [ "NetworkManager.service" ];
      before = [ "network-online.target" ];
      wantedBy = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${configureRecoveryAddress}/bin/configure-recovery-address";
      };
    };

    systemd.services.recovery-ssh-authorized-keys = {
      description = "Fetch verified GitHub SSH keys for recovery access";
      after = [
        "network-online.target"
        "recovery-network-address.service"
      ];
      requires = [ "recovery-network-address.service" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = "recovery-ssh";
        RuntimeDirectoryMode = "0700";
        ExecStart = "${fetchRecoveryAuthorizedKeys}/bin/fetch-recovery-authorized-keys";
      };
    };

    systemd.services.sshd = {
      after = [ "recovery-ssh-authorized-keys.service" ];
      requires = [ "recovery-ssh-authorized-keys.service" ];
    };
  };
}
