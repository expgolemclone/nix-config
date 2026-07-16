{ lib, ... }:

let
  backupRootUuid = "741133ee-fa8d-4674-8809-2735e197acae";
in
{
  specialisation.external-hdd-backup.configuration = {
    # The backup root lives behind a USB-SATA bridge. Make the complete
    # storage path available before udev-based coldplug and force it to load.
    boot.initrd.kernelModules = [
      "xhci_pci"
      "sd_mod"
      "uas"
      "usb_storage"
    ];

    # external-hdd-backup.nix defines the entire root filesystem with
    # lib.mkForce (priority 50). A child options definition in another module
    # is discarded with that parent definition, so replace the complete root
    # definition at a stronger priority and preserve NixOS's initrd marker.
    fileSystems."/" = lib.mkOverride 40 {
      device = "/dev/disk/by-uuid/${backupRootUuid}";
      fsType = "ext4";
      options = [
        "x-initrd.mount"
        "x-systemd.device-timeout=5min"
      ];
    };
  };
}
