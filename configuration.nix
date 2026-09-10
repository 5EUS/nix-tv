{ config, lib, pkgs, ... }:

{
  ##########################################################################
  # Boot / firmware
  #
  # You are building this on another machine and moving the disk, so there is
  # no `nixos-generate-config` hardware scan to lean on. Same problem as
  # mkinitcpio's `autodetect`: cast a wide net now, trim it once the board
  # has actually booted and you can run `nixos-generate-config --show-hardware-config`
  # on the real thing.
  ##########################################################################

  boot.loader.systemd-boot.enable = true;

  # Do NOT write boot entries into NVRAM — you're not booted on the target
  # board. bootctl falls back to EFI/BOOT/BOOTX64.EFI, which any firmware
  # will pick up as a removable-media boot entry.
  boot.loader.efi.canTouchEfiVariables = false;

  boot.initrd.availableKernelModules = [
    "ahci" "nvme" "sd_mod" "sr_mod"
    "xhci_pci" "ehci_pci" "usbhid" "usb_storage"
    "sdhci_pci" "rtsx_pci_sdmmc"
  ];

  boot.kernelPackages = pkgs.linuxPackages_latest;

  hardware.enableRedistributableFirmware = true;

  # Harmless to enable both until you know what CPU is on the board.
  hardware.cpu.intel.updateMicrocode = true;
  hardware.cpu.amd.updateMicrocode = true;

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver # Broadwell+ Intel iGPU, VAAPI. Drop if the board is AMD.
    ];
  };

  ##########################################################################
  # It's a motherboard, not a laptop
  #
  # A bare board often still reports a lid switch (or reports it as *closed*,
  # because the hall sensor / hinge switch isn't there). Left at defaults
  # that means it suspends seconds after boot and you never see a picture.
  ##########################################################################

  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandlePowerKey = "poweroff";
    IdleAction = "ignore";
  };

  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };

  powerManagement.cpuFreqGovernor = "schedutil";

  ##########################################################################
  # Plasma Bigscreen
  #
  # There is no `services.desktopManager.plasma6-bigscreen.enable` option, so
  # the session is registered manually via sessionPackages. The session name
  # that lands in /share/wayland-sessions is `plasma-bigscreen-wayland`.
  ##########################################################################

  services.desktopManager.plasma6.enable = true; # escape hatch: a normal
                                                 # desktop session you can pick
                                                 # at the login screen when you
                                                 # need to configure something

  services.displayManager = {
    sessionPackages = [ pkgs.kdePackages.plasma-bigscreen ];
    defaultSession = "plasma-bigscreen-wayland";

    autoLogin = {
      enable = true;
      user = "tv";
    };

    sddm = {
      enable = true;
      wayland.enable = true;
    };
  };

  xdg.portal = {
    enable = true;
    configPackages = [ pkgs.kdePackages.plasma-bigscreen ];
  };

  # KNOWN ISSUE (NixOS unstable, mid-2026): Bigscreen starts, then throws
  # "HomeScreen unavailable / module org.kde.kdeconnect is not installed"
  # because the KDE Connect QML plugin isn't on the session's import path.
  # Try WITHOUT this overlay first — if the package has been fixed upstream,
  # you don't want it. If you hit those errors, uncomment.
  #
  # nixpkgs.overlays = [
  #   (final: prev: {
  #     kdePackages = prev.kdePackages // {
  #       plasma-bigscreen = prev.kdePackages.plasma-bigscreen.overrideAttrs (old: {
  #         buildInputs = (old.buildInputs or [ ]) ++ [ prev.kdePackages.kdeconnect-kde ];
  #         preFixup = ''
  #           wrapQtApp $out/bin/plasma-bigscreen-wayland \
  #             --prefix QML2_IMPORT_PATH : "${prev.kdePackages.kdeconnect-kde}/lib/qt-6/qml"
  #         '';
  #       });
  #     };
  #   })
  # ];

  ##########################################################################
  # Living-room hardware: remotes, controllers, phone-as-remote
  ##########################################################################

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # KDE Connect turns a phone into the remote — Bigscreen has a first-class
  # indicator for it, and it's the least painful way to type on a TV.
  #
  # Do NOT set `package` here. The option defaults to the Qt5 build, which is
  # why setting it looks necessary — but plasma6.nix already redefines it as
  # kdePackages.kdeconnect-kde (the Qt6 one) whenever plasma6 is enabled, and
  # that definition is not a mkDefault. Two definitions of the same option is a
  # hard eval error even though both resolve to the identical derivation.
  # If plasma6.enable is ever turned off, set the package again here.
  programs.kdeconnect.enable = true;

  networking.firewall = {
    allowedTCPPortRanges = [ { from = 1714; to = 1764; } ];
    allowedUDPPortRanges = [ { from = 1714; to = 1764; } ];
  };

  ##########################################################################
  # Apps
  ##########################################################################

  environment.systemPackages = with pkgs; [
    kdePackages.plasma-bigscreen
    mpv
    jellyfin-media-player
    firefox
    vim
    git
  ];

  ##########################################################################
  # System
  ##########################################################################

  networking = {
    hostName = "tv";
    networkmanager.enable = true;
  };

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  users.users.tv = {
    isNormalUser = true;
    description = "TV";
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
    # Set a password on first boot with `passwd`, or set an initial one here.
    # initialPassword = "changeme";
    openssh.authorizedKeys.keys = [
      # "ssh-ed25519 AAAA... you@workstation"
    ];
  };

  # You will not want to walk over to the TV to debug this.
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  system.stateVersion = "26.05";
}
