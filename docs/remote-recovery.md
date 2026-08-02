# External HDD remote recovery

The external BUFFALO HDD is the temporary operating system and recovery environment. The internal SSD is not modified unless `recovery-restore-ssd` is called with the exact disk path, serial number, and destructive flag.

## Network layout

Connect the VAIO and Dell with the LAN cable. On Windows 11, share the VAIO internet connection to Ethernet. Windows Internet Connection Sharing normally uses `192.168.137.1`. The external-HDD specialisation adds `192.168.137.2/24` to the single connected Ethernet interface without replacing its DHCP address.

The recovery system fetches the verified public SSH keys published for the GitHub account `expgolemclone`. SSH starts only after that fetch succeeds. Password login, keyboard-interactive login, and root login are disabled. The recovery firewall permits TCP port 22 and no other configured TCP or UDP ports.

The private key on the VAIO must correspond to a public key registered in the GitHub account.

## Human actions

1. Connect the BUFFALO HDD, LAN cable, and AC power to the Dell.
2. Turn on the Dell and select the BUFFALO HDD once in the firmware boot menu.
3. Select the newest `external-hdd-backup` entry.

After those actions, Codex on the VAIO can use `windows/nixos-recovery.ps1` for the remaining command work.

## VAIO commands

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\windows\nixos-recovery.ps1 Status
```

List the disk identities from `Status`. Diagnose the internal SSD without mounting or repairing it:

```powershell
.\windows\nixos-recovery.ps1 Diagnose -Target '/dev/disk/by-id/nvme-EXACT_DEVICE_ID'
```

The diagnostic command reads `lsblk`, udev, SMART, and NVMe health data and writes a report under `/var/log/recovery`. It does not run `fsck`, mount the SSD, change partitions, or write to the SSD.

Continue using the HDD while the SSD condition is uncertain. Do not run `Restore` merely because the SSD failed to boot once.

## Destructive SSD restore

Only use this after deciding to replace or overwrite the SSD. The wrapper requires the exact serial number reported by `Status`:

```powershell
.\windows\nixos-recovery.ps1 Restore `
  -Target '/dev/disk/by-id/nvme-EXACT_DEVICE_ID' `
  -ConfirmSerial 'EXACT_SERIAL'
```

The underlying restore process recreates the SSD partition table and filesystems. The BUFFALO HDD is explicitly rejected as a target.

## Reboot verification

```powershell
.\windows\nixos-recovery.ps1 RebootAndWait
```

The script requires the host to become unreachable and then reachable on SSH before it accepts the reboot as successful. It finishes by running `recovery-status` on the returned system.

## Live USB repair of the HDD boot entry

When the BUFFALO HDD itself does not boot, start the official NixOS installer in UEFI mode and run one local command:

```console
curl -fsSL https://raw.githubusercontent.com/expgolemclone/nix-config/main/bootstrap-live-recovery | sudo bash
```

The live installer then accepts key-only SSH at `nixos@192.168.137.2`. From the VAIO, Codex can run:

```console
ssh nixos@192.168.137.2
curl -fsSL https://raw.githubusercontent.com/expgolemclone/nix-config/main/recover-external-hdd | sudo bash
```

`recover-external-hdd` keeps the HDD root and ESP read-only through disk validation and configuration resolution. It builds and inspects the pinned system before making the ESP writable. GitHub issue reporting is disabled by default and is never required for disk recovery.

To request an optional GitHub report explicitly:

```console
curl -fsSL https://raw.githubusercontent.com/expgolemclone/nix-config/main/recover-external-hdd \
  | sudo RECOVERY_REPORT_MODE=github bash
```

The private `yazi_fork` remains a local flake input. Live recovery therefore uses the backed-up copy at `/home/exp/projects/yazi_fork` through `--override-input`. A repository-only installation without that directory is intentionally unsupported.
