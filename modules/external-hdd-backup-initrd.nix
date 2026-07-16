{ lib, ... }:

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

    # Large external HDDs can take longer than systemd's default device
    # timeout to spin up and expose their partition UUIDs.
    fileSystems."/".options = lib.mkForce [
      "x-systemd.device-timeout=5min"
    ];
  };
}
