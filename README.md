# nix-tv

A NixOS flake that turns a salvaged laptop motherboard into a Plasma Bigscreen
TV box: boots straight into a 10-foot interface, no login prompt, no lid-switch
suspend, phone-as-remote via KDE Connect.

Three files:

| File | What it does |
| --- | --- |
| [flake.nix](flake.nix) | Pins nixpkgs (unstable) + disko, exposes `nixosConfigurations.tv` |
| [disko.nix](disko.nix) | Declarative GPT layout — 1G ESP + ext4 root |
| [configuration.nix](configuration.nix) | The system: boot, Bigscreen session, audio, bluetooth, apps |

The awkward part of this build is that the target has no keyboard, no screen you
want to type on, and possibly no known CPU vendor yet — so the config is written
to be installed **from another machine** and moved. That shapes a few decisions
worth knowing before you edit anything:

- `boot.loader.efi.canTouchEfiVariables = false` — you are not booted on the
  target board, so nothing should be written into its NVRAM. `bootctl` falls
  back to `EFI/BOOT/BOOTX64.EFI`, which any firmware picks up as removable-media
  boot.
- `boot.initrd.availableKernelModules` casts a wide net (AHCI, NVMe, xHCI, SD)
  because there is no `nixos-generate-config` hardware scan to lean on. Trim it
  once the board has actually booted and you can run
  `nixos-generate-config --show-hardware-config` on the real thing.
- Both Intel and AMD microcode updates are enabled. Harmless until you know
  what's on the board; drop one after.
- Sleep, suspend, hibernate and lid-switch handling are all disabled. A bare
  board frequently reports its lid as *closed* — the hinge switch isn't there —
  and will otherwise suspend seconds after boot, so you never see a picture.

---

## Do the VM first

Seriously. It's a much faster loop than reflashing a disk and carrying it to a
board, and it shakes out the Bigscreen session questions — which is where the
actual risk in this build lives — before you touch hardware.

### VM settings that matter

- **BIOS: OVMF (UEFI)**, machine type **q35**. Add an EFI Disk and **uncheck
  "Pre-Enroll keys"**. That option enrolls Secure Boot keys, and NixOS's
  bootloader is unsigned, so the VM will refuse to boot it.
- **Disk: 64 GB.** VirtIO Block if you can — but the bus you pick decides the
  device name later: VirtIO Block gives `/dev/vda`, SATA/SCSI gives `/dev/sda`.
  Don't assume; you'll run `lsblk` before touching disko. The Plasma 6 closure
  plus a couple of generations will chew through 20 GB fast.
- **CPU: host**, 4 cores. **RAM: 16 GB for the install**, then drop to 8 GB
  afterwards. This is not about performance — the installer's Nix store is a
  tmpfs sized at half of RAM, and 8 GB is not enough room to evaluate nixpkgs
  and build a Plasma closure. See
  [No space left on device](#no-space-left-on-device).
- **Disable memory ballooning**, or the VM may have less RAM than you set.
- **Display: VirtIO-GPU.** The default `std` adapter works, but `kwin_wayland`
  falls back to llvmpipe and it's rough. If the session refuses to start at all,
  this is the first thing to change.
- **Network: VirtIO**, bridged.

### Install

Boot the NixOS ISO. You land at a shell as user `nixos`. First thing — get off
the noVNC console, typing in it is miserable:

```sh
passwd            # set a password for the nixos user
ip a              # note the DHCP address
```

sshd is already running on the ISO, so `ssh nixos@<ip>` from your workstation
and now you can paste. Copy the flake over:

```sh
scp -r nix-tv nixos@<ip>:
```

**Two edits before you run anything.**

In [disko.nix](disko.nix), point `device` at the disk. **Look it up rather than
assuming** — the name follows the bus you gave the VM:

```sh
lsblk
```

```
NAME  MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
loop0   7:0    0  1.5G  1 loop /nix/.ro-store
sda     8:0    0   64G  0 disk
sr0    11:0    1  1.6G  1 rom  /iso
```

The 64 GB `disk` row is your target — `sda` here, which means SATA/SCSI, not
VirtIO Block. `loop0` is the ISO's read-only store and `sr0` is the ISO itself;
never those. So:

```nix
device = "/dev/sda";
```

Short names like this are fine in a throwaway VM. On real hardware use
`/dev/disk/by-id/...`, because `sda` is assigned in probe order and can move
between boots — and disko *wipes whatever it is pointed at*.

The second edit is your SSH key, and it is not optional in practice. The `tv`
user autologins straight into Bigscreen, so there is no password prompt at the
TV — and `services.openssh.settings.PasswordAuthentication` is `false`, so a
password won't get you in over the network either. Install without a key and
your only way to a shell is a physical keyboard on `Ctrl+Alt+F2`.

**Do you already have one?**

```sh
ls -l ~/.ssh/*.pub
```

If you see `id_ed25519.pub`, use it — skip to the next step. If the only thing
there is `id_rsa.pub`, generate a new one anyway; ed25519 keys are shorter,
faster, and what you want on a box you'll be pasting config into.

**Make one:**

```sh
ssh-keygen -t ed25519 -C "you@workstation"
```

Press Enter to accept the default path (`~/.ssh/id_ed25519`). Set a passphrase —
`ssh-agent` on both macOS and Linux will hold it so you only type it once per
login. Then print the **public** half:

```sh
cat ~/.ssh/id_ed25519.pub
```

That single line — starting `ssh-ed25519 AAAA…` and ending with the comment —
is what goes in the config. The other file, `id_ed25519` with no extension, is
the private key: it never leaves your workstation and never goes in the repo.

**Paste it into [configuration.nix](configuration.nix)** on the `tv` user, at
[the placeholder around line 178](configuration.nix#L178):

```nix
users.users.tv = {
  # ...
  openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... you@workstation"
  ];
};
```

Note what you are *not* doing here: there is no `ssh-copy-id` at the target and
no hand-editing of `~/.ssh/authorized_keys`. On NixOS that file is generated
from this list, so the config is the source of truth — which is the whole point.
Add a second string to the list for a laptop or a phone; they're just more lines.

While you're in there, it's worth uncommenting `initialPassword` too:

```nix
initialPassword = "changeme";
```

That's your console fallback. The key gets you in over the network; the password
gets you past a VT login when the network is the thing that's broken. Change it
after first boot with `passwd`.

Then — and this is the step people skip — stage it, because flakes only read
tracked files:

```sh
git add -A
```

> **Aside:** `ssh-copy-id nixos@<ip>` against the *live ISO* is still worth
> running before the `scp`, purely so you stop retyping the installer password.
> That's a throwaway — the ISO's filesystem is a tmpfs and evaporates on reboot.
> It has nothing to do with the key on the installed system.

Then partition and install:

```sh
cd nix-tv

sudo nix --experimental-features "nix-command flakes" \
  run github:nix-community/disko/latest -- \
  --mode destroy,format,mount --flake .#tv

sudo nixos-install --flake .#tv
```

disko wipes the device, formats it, mounts everything under `/mnt`, and enables
the swap partition. `nixos-install` builds the closure, installs the bootloader
to the ESP, and prompts for a root password at the end. Reboot and detach the
ISO.

If that first command dies with `error: writing to file: No space left on
device`, it is not talking about your 64 GB disk — see
[No space left on device](#no-space-left-on-device). The short version is to
build disko from your own flake instead, which avoids pulling down a second copy
of nixpkgs:

```sh
nix --experimental-features "nix-command flakes" \
  build .#nixosConfigurations.tv.config.system.build.diskoScript

sudo ./result
```

### The gotcha that gets everyone

Flakes only see files that **git tracks**. If `nix-tv` is a git repo (it is),
an untracked or unstaged `configuration.nix` means `nixos-install` fails with a
confusing "path does not exist" — or, worse, silently builds a config missing
your changes. After every edit:

```sh
git add -A
```

---

## No space left on device

The failure looks like it's about the disk. It isn't:

```
error:
       … while evaluating a branch condition
         at /nix/store/…-disko/share/disko/cli.nix:106:5
       error: writing to file: No space left on device
```

That's thrown during **evaluation**, before disko has looked at a partition
table, so the `device` value has nothing to do with it — fixing `vda` → `sda`
will not make it go away. What's full is the **installer's Nix store**, which
lives in RAM. The ISO mounts a read-only squashfs (`/nix/.ro-store`, the `loop0`
in your `lsblk`) with a tmpfs layered on top, and that tmpfs defaults to half
your RAM. Confirm it:

```sh
df -h /nix/.rw-store
free -h
```

Fixes, most effective first.

**1. Give the VM more RAM.** The tmpfs is sized as a fraction of RAM, so this
directly buys store space. 16 GB during install, back to 8 GB after. If Proxmox
memory ballooning is on, turn it off — the guest can otherwise hold less than
the number you configured.

**2. Don't make it fetch nixpkgs twice.** `nix run github:nix-community/disko/latest`
resolves *disko's own* lock file, which pins its own nixpkgs — a second full
nixpkgs source in a store that's already tight. Your flake already has disko as
an input with `inputs.nixpkgs.follows = "nixpkgs"`, so build the script from the
local flake and only one nixpkgs is ever fetched:

```sh
nix --experimental-features "nix-command flakes" \
  build .#nixosConfigurations.tv.config.system.build.diskoScript

sudo ./result
```

Same destroy/format/mount behaviour, meaningfully less to download. (`git add -A`
first, as always.)

**3. Grow the tmpfs**, if there's free RAM it isn't using:

```sh
sudo mount -o remount,size=12G /nix/.rw-store
```

Lost on reboot, which is fine — you only need it to survive the install.

### It comes back during `nixos-install`

Expect this: the Plasma 6 closure is far bigger than anything disko needed. By
that point disko has mounted the target at `/mnt`, so there's real disk to use —
which is what the swap partition in [disko.nix](disko.nix) is for. tmpfs pages
can be swapped out, so it lets the store overflow onto the disk instead of
dying. disko enables it automatically at mount time; verify before installing:

```sh
swapon --show
```

If you'd rather not carry a swap partition on the finished box, drop it from
[disko.nix](disko.nix) and make a temporary swapfile after disko has mounted:

```sh
sudo dd if=/dev/zero of=/mnt/swapfile bs=1M count=8192
sudo chmod 600 /mnt/swapfile
sudo mkswap /mnt/swapfile
sudo swapon /mnt/swapfile
```

Then `sudo swapoff /mnt/swapfile && sudo rm /mnt/swapfile` once the install
finishes.

## The real thing

Same flow, two differences.

**Get the device id right.** disko *wipes the named device*. On real hardware
use a stable path, not `/dev/sdX`:

```sh
ls -l /dev/disk/by-id/
```

and put that in [disko.nix](disko.nix). Using by-id is also why the config
doesn't care that the disk is in a USB enclosure now and in the board later —
disko generates the `fileSystems` entries by UUID.

**Drop what doesn't apply.** `hardware.graphics.extraPackages` has
`intel-media-driver` in it for VAAPI on Broadwell+ Intel iGPUs. If the board is
AMD, remove it.

Then install to the enclosure from your workstation, move the disk to the
board, and boot.

---

## `option ... is defined multiple times`

```
error: The option `programs.kdeconnect.package' is defined multiple times
       while it's expected to be unique.
       - In `.../configuration.nix': <derivation kdeconnect-kde-26.08.0>
       - In `.../modules/services/desktop-managers/plasma6.nix': <derivation kdeconnect-kde-26.08.0>
```

Note that both definitions are *the same derivation*. Nix doesn't care — a
non-`mkDefault` option can only be defined once, regardless of whether the
values agree.

The cause is a trap specific to this config. `programs.kdeconnect.package`
defaults to the **Qt5** build, so setting it explicitly to
`pkgs.kdePackages.kdeconnect-kde` looks obviously correct. But
`services.desktopManager.plasma6.enable = true` — on here as the fallback
session — pulls in `plasma6.nix`, which already redefines that option to the
Qt6 package, and not as a default. Setting it yourself collides.

Fix is to drop the `package` line and keep the enable:

```nix
programs.kdeconnect.enable = true;
```

Already applied in [configuration.nix](configuration.nix). Only put `package`
back if you ever disable plasma6, at which point you'd land on the Qt5 build
again. The general escape hatch, if you hit this on some other option where you
genuinely need your value to win, is `lib.mkForce`.

---

## When Bigscreen doesn't come up

There is no `services.desktopManager.plasma6-bigscreen.enable` option, so the
session is registered by hand through `sessionPackages`. The session name that
lands in `/share/wayland-sessions` is `plasma-bigscreen-wayland`, and that
string is what `defaultSession` points at.

Plain Plasma 6 is enabled alongside it as a deliberate escape hatch — if
Bigscreen is broken you can always pick the normal desktop at the login screen
and debug from a working session.

If SDDM comes up but Bigscreen bounces straight back to the login screen,
switch to a VT with `Ctrl+Alt+F2`, log in, and check:

```sh
journalctl --user -b -u 'plasma-*'
cat ~/.local/share/sddm/*.log
```

The known failure mode looks like `HomeScreen unavailable` /
`module org.kde.kdeconnect is not installed` — the KDE Connect QML plugin isn't
on the session's import path. There's a commented-out overlay in
[configuration.nix](configuration.nix) that fixes it by wrapping the session
binary with the right `QML2_IMPORT_PATH`.

**Try without the overlay first.** If the package has been fixed upstream, you
don't want a local override shadowing it.

---

## Notes

- **Channel:** this tracks `nixos-unstable`, on purpose. Bigscreen's Plasma 6
  revival landed in nixpkgs after 26.05 branched. Before moving to stable:

  ```sh
  nix eval nixpkgs#kdePackages.plasma-bigscreen.version
  nix eval github:NixOS/nixpkgs/nixos-26.05#kdePackages.plasma-bigscreen.version
  ```

  If stable still shows 5.27.x, stay on unstable for this host.
- **KDE Connect:** ports 1714–1764 are open TCP and UDP. Bigscreen has a
  first-class indicator for it, and it's by far the least painful way to type on
  a TV.
- **Power button** halts the machine (`HandlePowerKey = "poweroff"`); idle does
  nothing.
- **GC** runs weekly, deleting generations older than 30 days. On a 64 GB disk
  with Plasma closures, leave this on.
- **Timezone** is `America/New_York` — change it in
  [configuration.nix](configuration.nix).

### Rebuilding later

Once it's on the network, you never need to touch the TV again:

```sh
ssh tv@<ip>
cd nix-tv && git pull
sudo nixos-rebuild switch --flake .#tv
```

### If you installed without a key

Recoverable, just annoying — you need a keyboard on the box once.

1. `Ctrl+Alt+F2` for a VT, log in as `tv` with the `initialPassword` (or as
   `root` with the password `nixos-install` prompted you for).
2. Edit `configuration.nix`, add the key to `openssh.authorizedKeys.keys`.
3. `git add -A && sudo nixos-rebuild switch --flake .#tv`

If you set neither a key nor `initialPassword`, `tv` has no password at all and
you'll need the root account from step 1 to `passwd tv`.
