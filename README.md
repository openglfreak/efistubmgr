# efistubmgr

A script for managing EFI boot entries that directly start Linux using
the EFISTUB functionality of the kernel.

## Dependencies

- A sufficiently POSIX-compliant shell at /bin/sh (bash will work)
- Various other POSIX tools, in `$PATH` or as shell built-ins: sed, printf, [,
    mkdir, echo, cat, sort, comm (you probably have these already)
- [efibootmgr](https://github.com/rhboot/efibootmgr)
    (get it from your distro's package manager if possible)

## Prerequisites

The script searches in /boot for a config file and for microcode initrds.
If it finds any microcode initrds, it assumes that /boot is the root directory
of the system's EFI system partition.

The script writes the boot entries it manages to
/var/lib/efistubmgr/managed_entries. If it can't create the directory or write
the file, the script fails.

## How to use

Make a file in /boot named efistubmgr.conf and add a valid configuration
there (look in the "examples" directory for example configs).

Afterwards, run `update-efi` as root. The boot entries specified in the
config file should now be added to the boot menu. You can verify this by
running `efibootmgr`.

If you later edit the config file, run `update-efi` as root again to update
the boot entries.
