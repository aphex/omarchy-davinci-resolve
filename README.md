# DaVinci Resolve on Omarchy

Fixes for DaVinci Resolve Studio installed from the AUR on Omarchy / Arch +
Hyprland. Everything here came out of debugging a working install that had
four separate problems, three of which fail **silently** — Resolve starts,
looks fine, and simply never tells you that a feature is missing.

Tested on Omarchy 4.0.1, Hyprland 0.56.2, DaVinci Resolve Studio 21.0.4
build 5 (`davinci-resolve-studio` 21.0.4-1 from the AUR), RTX 4070 Ti SUPER
on `nvidia-open-dkms` 610.57.04, with a DaVinci Resolve Mini Panel.

## What it fixes

| Symptom | Cause |
| --- | --- |
| Micro/Mini panel never detected | Panel API libraries missing from the hardcoded `dlopen` path |
| No AI features; nothing downloads | DDM cannot create `/opt/resolve/Extras` |
| Repeated Fairlight errors on every launch | `/opt/resolve/Fairlight` cannot be created |
| Modal dialogs trap the mouse pointer | Hyprland focus-follows-mouse vs. Resolve's dialogs |
| UI wildly over/undersized on HiDPI | Qt5 picks an integer scale from physical DPI |

## Quick start

```sh
git clone <this repo> && cd omarchy-davinci-resolve
sudo bash install.sh
```

That installs `/usr/local/bin/omarchy-resolve-fix` and a **pacman hook** that
re-applies the fixes automatically on every `davinci-resolve-studio` upgrade —
the packaging problems below come back every time the package is reinstalled,
so a one-shot fix is not enough.

Check status at any time (changes nothing, exits non-zero if anything is
broken):

```sh
omarchy-resolve-fix --check
```

The Hyprland and Qt scaling fixes are per-user and are **not** installed by
`install.sh`; see [Window rules](#window-rules-modal-dialogs-trapping-the-pointer)
and [HiDPI scaling](#hidpi-scaling) below.

---

## Root causes

### 1. Micro / Mini panel is never detected

The most damaging one, and the least obvious. `DaVinciPanelDaemon` and
`libDaVinciPanels.so` load the panel API library by **absolute hardcoded
path**:

```
/usr/lib64/libDaVinciPanelAPI.so
/usr/lib64/libFairlightPanelAPI.so
```

Blackmagic's official `.run` installer puts them there. The AUR package ships
them only inside `/opt/resolve/libs`, so the `dlopen` fails. The API version
then falls back to its `0.0` default and the daemon gives up **before it ever
enumerates hardware**:

```
Unsupported DaVinci Panel API Version (0.0), please update
```

That message is misleading — nothing needs updating, and the panel firmware is
irrelevant. Because the path is absolute, `LD_LIBRARY_PATH` cannot help; the
files must exist at that path. On Arch `/usr/lib64` is a symlink to `/usr/lib`,
so linking into `/usr/lib` is what makes it resolve.

Confirmed by intercepting that single `dlopen` with an `LD_PRELOAD` shim:

```
before:  Unsupported DaVinci Panel API Version (0.0), please update
after:   DaVinci Panel API Version: 1.0
         Panel arrived
         DVPB panel: DaVinci Resolve Panel Mini
```

Worth ruling out first, since they look like the obvious suspects and are not:
udev permissions are already correct (the package's `99-BlackmagicDevices.rules`
sets `MODE="0666"` for vendor `1edb`), and no kernel driver claims any of the
panel's six interfaces.

### 2. DDM is dead, so no AI features

`/opt/resolve/Extras` is never created, and it lives under root-owned
`/opt/resolve`, so Resolve — running as your user — cannot create it:

```
Failed to initialize DDM: failed to create storage dir '/opt/resolve/Extras'
  (error 'Permission denied')
DDM init failed.
```

DDM is the DaVinci Download Manager, which fetches Resolve's downloadable
content packages. With it dead, Resolve never even reports that anything is
missing. On the machine this was found on, fixing it immediately pulled:

- **Tensor RT Engines — 2.23 GiB.** The NVIDIA inference engines behind the
  whole DaVinci Neural Engine feature set: Magic Mask, Voice Isolation, Super
  Scale, Depth Map, Object Removal, Smart Reframe, Text-Based Editing.
- **AI Motion Deblur — 18.5 MiB.**

If you have an NVIDIA GPU and Resolve's AI features have felt absent or slow,
check this before anything else:

```sh
grep -i ddm ~/.local/share/DaVinciResolve/logs/ddm.log | tail
```

Healthy output names installed packages; broken output repeats the permission
error once per launch.

Fixing this also silences a *third* unrelated-looking warning, which turns out
to be collateral from the same cause:

```
The DaVinci Control Panels Setup application is not compatible with this
version of Resolve. Please re-install Resolve with the DaVinci Control Panels
Setup application option enabled in the installer.
```

### 3. Fairlight scratch directory

Same shape, smaller blast radius. `/opt/resolve/Fairlight` is never created:

```
mkdir failed for directory '/opt/resolve/Fairlight' (errno 13)
```

### Window rules: modal dialogs trapping the pointer

Not a packaging bug — a compositor interaction. With focus-follows-mouse,
Hyprland warps the cursor back into Resolve's modal dialogs, so
**Preferences → Media Storage → Add** becomes inescapable and the screenshot
selector never receives pointer input.

This is [omarchy PR #6919](https://github.com/basecamp/omarchy/pull/6919),
which had not landed as of Omarchy 4.0.1. Until it ships, append
[`hypr/davinci-resolve.lua`](hypr/davinci-resolve.lua) to
`~/.config/hypr/hyprland.lua` — user config loads after Omarchy's defaults, so
it overrides them — then `hyprctl reload`. Verify with `hyprctl configerrors`.

Both `no_follow_mouse` and `stay_focused` are valid keys in Hyprland's Lua
config API as of 0.56.2. Delete these lines once an Omarchy release includes
the PR.

### HiDPI scaling

Resolve bundles Qt5 with **only** the `xcb` platform plugin — there is no
Wayland plugin in `/opt/resolve/libs/plugins/platforms` — while Omarchy exports
`QT_QPA_PLATFORM="wayland;xcb"` session-wide. Resolve probes Wayland, fails,
and falls back. Harmless but worth pinning.

The real problem is scale. With `xwayland { force_zero_scaling = true }`
(Omarchy's default), Hyprland hands XWayland the native pixel buffer and the
client must scale itself. Qt5 instead derives an **integer** devicePixelRatio
from the monitor's physical DPI. A 27" 4K panel reports ~163 DPI, so Qt picks
2.0 — but if you run that display at 1.5, Resolve's UI ends up ~33% larger than
every other window, and its logical workspace collapses to 1920x1080 instead of
2560x1440.

[`bin/davinci-resolve`](bin/davinci-resolve) pins the platform to `xcb` and sets
`QT_SCALE_FACTOR` from the Hyprland scale of the display Resolve runs on:

```sh
install -Dm755 bin/davinci-resolve ~/.local/bin/davinci-resolve
```

Then point a user desktop entry at it. Copy the packaged one and change only
`Exec=`, keeping `StartupWMClass=resolve` so the window rules still match:

```sh
sed 's|^Exec=.*|Exec='"$HOME"'/.local/bin/davinci-resolve %u|' \
  /usr/share/applications/DaVinciResolve.desktop \
  > ~/.local/share/applications/DaVinciResolve.desktop
update-desktop-database ~/.local/share/applications
```

`~/.local/share/applications` takes precedence over `/usr/share/applications`,
so the override survives package upgrades.

Edit `preferred_monitor` in the script, or override per launch:

```sh
davinci-resolve                      # preferred display's scale
RESOLVE_SCALE=1.5 davinci-resolve    # explicit factor
RESOLVE_MONITOR=DP-1 davinci-resolve # follow another display's scale
```

**Multi-monitor caveat.** Qt applies one `QT_SCALE_FACTOR` to every screen and
reads it once at startup, so a Resolve session spanning displays of *different*
Hyprland scale cannot be correct on both. Spanning two displays that share a
scale is pixel-correct; otherwise pick the value that suits your primary and
accept the secondary being off.

Do not diagnose scaling from the `Screen:` line in
`~/.local/share/DaVinciResolve/logs/resolve_graphics_log.txt` — it reports the
primary X screen, not the monitor the window is on. Use
`hyprctl clients` and look at the window's `monitor` field.

---

## Known-unfixed

The panel daemon aborts during shutdown inside
`HIDLinuxManager::Stop` → `udev_monitor_unref`, adding an entry to
`~/.local/share/DaVinciResolve/crash_archive.txt` on some exits. It happens
after teardown has begun and appears to be harmless, but it is a genuine bug
in Resolve's Linux build and there is no workaround from outside the binary.

## Files

| Path | Purpose |
| --- | --- |
| `install.sh` | Installs the repair script + pacman hook, then applies fixes |
| `bin/omarchy-resolve-fix` | Idempotent repair; `--check` to audit, `--user` to set owner |
| `bin/davinci-resolve` | Launcher wrapper: pins `xcb`, sets `QT_SCALE_FACTOR` |
| `hypr/davinci-resolve.lua` | Hyprland window rules (PR #6919 backport) |

## Upstream

The two packaging problems are AUR `davinci-resolve-studio` bugs — the PKGBUILD
should create both directories and link both panel libraries. The underlying
fragility is Blackmagic's: loading a bundled library through an absolute
`/usr/lib64` path, and reporting the resulting failure as a version error
rather than a load error.
