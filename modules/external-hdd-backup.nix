{ lib, pkgs, ... }:

let
  sourceRootUuid = "34af5ddb-7165-4fe8-b1a8-06e5010df960";
  sourceBootUuid = "0043-1736";
  backupBootUuid = "BACA-0001";
  backupBootVfatId = "BACA0001";
  backupRootUuid = "741133ee-fa8d-4674-8809-2735e197acae";
  storageUuid = "ee3cc7cf-d2d6-4427-829f-f24715ced72f";
  externalHddDisk = "/dev/disk/by-id/usb-BUFFALO_External_HDD_0040473060601346-0:0";

  backupHddInit = pkgs.writeShellApplication {
    name = "backup-hdd-init";
    runtimeInputs = with pkgs; [
      coreutils
      dosfstools
      e2fsprogs
      gnugrep
      gptfdisk
      parted
      systemd
      util-linux
    ];
    text = ''
      set -euo pipefail

      fail() {
        printf 'backup-hdd-init: %s\n' "$*" >&2
        exit 1
      }

      if [ "$#" -ne 1 ] || [ "$1" != "--destroy-buffalo-hdd" ]; then
        fail "usage: backup-hdd-init --destroy-buffalo-hdd"
      fi

      disk="${externalHddDisk}"
      boot_part="''${disk}-part1"
      root_part="''${disk}-part2"
      storage_part="''${disk}-part3"

      [ -b "$disk" ] || fail "$disk is not connected"

      if lsblk -nr -o MOUNTPOINT "$disk" | grep -q '[^[:space:]]'; then
        fail "$disk has mounted partitions; unmount them first"
      fi

      printf 'Destroying and repartitioning %s\n' "$disk"
      sgdisk --zap-all "$disk"
      wipefs --all "$disk"
      sgdisk \
        --new=1:1MiB:+1GiB --typecode=1:EF00 --change-name=1:external-backup-efi \
        --new=2:0:+1024GiB --typecode=2:8304 --change-name=2:external-ssd-backup-root \
        --new=3:0:0 --typecode=3:8300 --change-name=3:external-storage \
        "$disk"
      partprobe "$disk"
      udevadm settle

      for part in "$boot_part" "$root_part" "$storage_part"; do
        for _ in $(seq 1 30); do
          [ -b "$part" ] && break
          sleep 1
        done
        [ -b "$part" ] || fail "$part did not appear"
      done

      mkfs.vfat -F 32 -n BACKUPBOOT -i ${backupBootVfatId} "$boot_part"
      mkfs.ext4 -F -L SSD_BACKUP -U ${backupRootUuid} "$root_part"
      mkfs.ext4 -F -L HDD_STORAGE -U ${storageUuid} "$storage_part"

      printf 'Created external backup HDD layout:\n'
      lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID,PARTLABEL,MOUNTPOINTS "$disk"
    '';
  };

  ssdHourlyBackup = pkgs.writeShellApplication {
    name = "ssd-hourly-backup";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      rsync
      util-linux
    ];
    text = ''
      set -euo pipefail

      fail() {
        printf 'ssd-hourly-backup: %s\n' "$*" >&2
        exit 1
      }

      source_root_uuid="$(findmnt -n -o UUID /)"
      source_boot_uuid="$(findmnt -n -o UUID /boot)"
      [ "$source_root_uuid" = "${sourceRootUuid}" ] || fail "current / UUID is $source_root_uuid, expected ${sourceRootUuid}"
      [ "$source_boot_uuid" = "${sourceBootUuid}" ] || fail "current /boot UUID is $source_boot_uuid, expected ${sourceBootUuid}"

      backup_root="/dev/disk/by-uuid/${backupRootUuid}"
      backup_boot="/dev/disk/by-uuid/${backupBootUuid}"
      [ -b "$backup_root" ] || fail "$backup_root is not present"
      [ -b "$backup_boot" ] || fail "$backup_boot is not present"

      lock="/run/ssd-hourly-backup.lock"
      root_mount="/run/ssd-hourly-backup/root"
      boot_mount="/run/ssd-hourly-backup/boot"

      exec 9>"$lock"
      flock -n 9 || fail "another backup is already running"

      cleanup() {
        umount "$boot_mount" >/dev/null 2>&1 || true
        umount "$root_mount" >/dev/null 2>&1 || true
      }
      trap cleanup EXIT

      mkdir -p "$root_mount" "$boot_mount"
      mountpoint -q "$root_mount" && fail "$root_mount is already mounted"
      mountpoint -q "$boot_mount" && fail "$boot_mount is already mounted"

      mount -t ext4 "$backup_root" "$root_mount"
      mount -t vfat "$backup_boot" "$boot_mount"

      rsync \
        -aAXH \
        --numeric-ids \
        --delete \
        --one-file-system \
        --info=stats2 \
        --exclude='/dev/*' \
        --exclude='/proc/*' \
        --exclude='/sys/*' \
        --exclude='/run/*' \
        --exclude='/tmp/*' \
        --exclude='/media/*' \
        --exclude='/mnt/hdd-storage/*' \
        / "$root_mount"/

      mkdir -p "$root_mount/boot"
      rsync \
        -rt \
        --delete \
        --no-perms \
        --no-owner \
        --no-group \
        --info=stats2 \
        /boot/ "$boot_mount"/
    '';
  };

  restoreSsdFromHdd = pkgs.writeShellApplication {
    name = "restore-ssd-from-hdd";
    runtimeInputs = with pkgs; [
      coreutils
      dosfstools
      e2fsprogs
      gnugrep
      gptfdisk
      parted
      rsync
      systemd
      util-linux
    ];
    text = ''
      set -euo pipefail

      fail() {
        printf 'restore-ssd-from-hdd: %s\n' "$*" >&2
        exit 1
      }

      if [ "$#" -ne 3 ] || [ "$1" != "--target" ] || [ "$3" != "--destroy-target-ssd" ]; then
        fail "usage: restore-ssd-from-hdd --target /dev/disk/by-id/<new-ssd> --destroy-target-ssd"
      fi

      target_disk="$2"
      case "$target_disk" in
        /dev/disk/by-id/nvme-*|/dev/disk/by-id/ata-*|/dev/disk/by-id/wwn-*)
          ;;
        *)
          fail "target must be an explicit /dev/disk/by-id disk path"
          ;;
      esac

      [ "$target_disk" != "${externalHddDisk}" ] || fail "target must not be the external backup HDD"
      [ -b "$target_disk" ] || fail "$target_disk is not a block device"

      current_root_uuid="$(findmnt -n -o UUID /)"
      current_boot_uuid="$(findmnt -n -o UUID /boot)"
      [ "$current_root_uuid" = "${backupRootUuid}" ] || fail "boot external-hdd-backup first; current / UUID is $current_root_uuid"
      [ "$current_boot_uuid" = "${backupBootUuid}" ] || fail "boot external-hdd-backup first; current /boot UUID is $current_boot_uuid"

      if lsblk -nr -o MOUNTPOINT "$target_disk" | grep -q '[^[:space:]]'; then
        fail "$target_disk has mounted partitions; unmount them first"
      fi

      target_boot="''${target_disk}-part1"
      target_root="''${target_disk}-part2"
      root_mount="/run/restore-ssd-from-hdd/root"
      boot_mount="/run/restore-ssd-from-hdd/boot"

      printf 'Destroying and restoring %s from the external HDD backup\n' "$target_disk"
      sgdisk --zap-all "$target_disk"
      wipefs --all "$target_disk"
      sgdisk \
        --new=1:1MiB:+512MiB --typecode=1:EF00 --change-name=1:nixos-efi \
        --new=2:0:0 --typecode=2:8304 --change-name=2:nixos-root \
        "$target_disk"
      partprobe "$target_disk"
      udevadm settle

      for part in "$target_boot" "$target_root"; do
        for _ in $(seq 1 30); do
          [ -b "$part" ] && break
          sleep 1
        done
        [ -b "$part" ] || fail "$part did not appear"
      done

      mkfs.vfat -F 32 -n NIXOSBOOT -i 00431736 "$target_boot"
      mkfs.ext4 -F -L NIXOS_ROOT -U ${sourceRootUuid} "$target_root"

      cleanup() {
        umount "$boot_mount" >/dev/null 2>&1 || true
        umount "$root_mount" >/dev/null 2>&1 || true
      }
      trap cleanup EXIT

      mkdir -p "$root_mount" "$boot_mount"
      mount -t ext4 "$target_root" "$root_mount"
      mount -t vfat "$target_boot" "$boot_mount"

      rsync \
        -aAXH \
        --numeric-ids \
        --delete \
        --one-file-system \
        --info=stats2 \
        --exclude='/dev/*' \
        --exclude='/proc/*' \
        --exclude='/sys/*' \
        --exclude='/run/*' \
        --exclude='/tmp/*' \
        --exclude='/media/*' \
        --exclude='/mnt/hdd-storage/*' \
        / "$root_mount"/

      mkdir -p "$root_mount/boot"
      rsync \
        -rt \
        --delete \
        --no-perms \
        --no-owner \
        --no-group \
        --info=stats2 \
        /boot/ "$boot_mount"/

      bootctl --esp-path="$boot_mount" install --no-variables

      printf 'Restore finished. Reboot from the restored SSD, then run nixos-rebuild switch.\n'
    '';
  };
in
{
  environment.systemPackages = [
    backupHddInit
    ssdHourlyBackup
    restoreSsdFromHdd
  ];

  fileSystems."/mnt/hdd-storage" = {
    device = "/dev/disk/by-uuid/${storageUuid}";
    fsType = "ext4";
    options = [
      "nofail"
      "x-systemd.automount"
      "x-systemd.idle-timeout=10min"
    ];
  };

  systemd.tmpfiles.rules = [
    "d /mnt/hdd-storage 0755 root root -"
  ];

  systemd.services.ssd-hourly-backup = {
    description = "Mirror the internal SSD to the external backup HDD";
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${ssdHourlyBackup}/bin/ssd-hourly-backup";
      IOSchedulingClass = "best-effort";
      IOSchedulingPriority = 7;
      Nice = 10;
    };
  };

  systemd.timers.ssd-hourly-backup = {
    description = "Run the external HDD SSD mirror every hour";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
      AccuracySec = "5min";
    };
  };

  specialisation.external-hdd-backup.configuration = {
    fileSystems."/" = lib.mkForce {
      device = "/dev/disk/by-uuid/${backupRootUuid}";
      fsType = "ext4";
    };

    fileSystems."/boot" = lib.mkForce {
      device = "/dev/disk/by-uuid/${backupBootUuid}";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };

    systemd.timers.ssd-hourly-backup.wantedBy = lib.mkForce [ ];
  };
}
