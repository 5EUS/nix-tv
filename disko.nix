{
  # Declarative partitioning. This replaces hand-rolled fdisk/mkfs and, more
  # usefully here, generates the fileSystems entries by UUID for you — so the
  # config doesn't care that the disk is in a USB enclosure now and in the
  # board later.
  #
  # WARNING: applying this WIPES the named device. Get the id right.
  #   ls -l /dev/disk/by-id/

  disko.devices.disk.main = {
    device = "/dev/disk/by-id/CHANGE-ME";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          priority = 1;
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        # Not for the TV's sake — 8 GB of RAM running Bigscreen barely needs
        # it. This exists so `nixos-install` has somewhere to spill: the
        # installer ISO's Nix store is a tmpfs, and building the Plasma
        # closure in RAM alone runs it out of space. disko swapon's this as
        # soon as it mounts, i.e. before you run nixos-install.
        swap = {
          priority = 2;
          size = "8G";
          content = {
            type = "swap";
            discardPolicy = "both";
            resumeDevice = false; # hibernation is disabled in configuration.nix
          };
        };

        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
