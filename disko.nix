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
