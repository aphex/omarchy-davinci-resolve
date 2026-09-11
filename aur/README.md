# Building the AUR package by hand

The AUR `davinci-resolve-studio` PKGBUILD trails Blackmagic's releases — when
21.1 shipped, the AUR was still pinned to 21.0.4 — so upgrading means bumping
`pkgver` and the checksum yourself. yay wipes and re-clones its cache directory
on every update, so those edits do not survive; that is why the patch lives
here instead.

[`pkgbuild-21.1.patch`](pkgbuild-21.1.patch) is the diff against AUR commit
`26f7d83` (`Updated package davinci-resolve-studio 21.0.4-1`).

## Recipe

1. Download the Linux installer zip from Blackmagic — it needs a registration
   form, so it cannot be fetched automatically — and drop it in the build dir
   as `DaVinci_Resolve_Studio_<version>_Linux.zip`.

2. Bump `pkgver`, then replace the **first** `sha256sums` entry with the real
   hash of that zip:

   ```sh
   sha256sum DaVinci_Resolve_Studio_21.1_Linux.zip
   ```

   Verified for 21.1:
   `06e9ac88060a95d81908f3ca334b0464e6d9a82761b4cb9654ad54aee802ff97`

   The second entry is for `davinci-control-panels-setup.sh` and does not
   change between Resolve releases.

3. Confirm the sources validate *before* committing to a ~20 minute build:

   ```sh
   makepkg -f --verifysource
   ```

4. Build and install, then clean up (see below).

## Two traps

**The checksum array.** Writing `sha256sums=('SKIP','<hash>'` produces a single
element `SKIP,<hash>` — bash does not split on the comma — which is neither
`SKIP` nor a valid hash, so the build only proceeds under `--skipinteg` and the
zip is never verified at all. Either give the real hash (preferred, it catches a
truncated download) or `'SKIP'` alone on its own line. Check what you actually
wrote:

```sh
( source ./PKGBUILD; printf '%s\n' "${sha256sums[@]}" )
```

**The bundled-library globs.** Upstream's `prepare()` removes Resolve's bundled
glib and libc++ by exact filename, including the soversion:

```sh
rm squashfs-root/libs/libglib-2.0.so.0{,.6800.4}
```

That breaks the moment Blackmagic bumps the bundled glib, which is what the
patch fixes — `rm -f ...so*` is version-agnostic, and `ln -sf` makes the
relinking idempotent on a re-run.

## Cleanup

`makepkg` leaves `src/` (the unpacked `.run`) and `pkg/` (the staging tree)
behind — 39 GB for Resolve 21.1. Both are regenerable from the zip:

```sh
rm -rf src pkg
```

Keep the zip (re-downloading needs the registration form again) and the built
`.pkg.tar.zst` (lets you reinstall without a rebuild).
