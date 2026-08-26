# DaVinci Resolve Studio for Linux — four defects (21.0.4 build 5)

Four issues found while setting up Resolve Studio 21.0.4 on Arch Linux. Two are
robustness problems in how Resolve loads its own libraries, and two are
diagnostics that actively point users at the wrong cause. All are reproducible
and independent of the distribution packaging that surfaced them.

## Environment

| | |
| --- | --- |
| Product | DaVinci Resolve Studio 21.0.4 build 5 (Linux/Clang x86_64) |
| Build UUID | `8e8721af-a6d3-4df6-a3bc-4166faf558e5` |
| OS | Arch Linux (Omarchy 4.0.1), kernel 7.1.9 |
| GPU | NVIDIA RTX 4070 Ti SUPER, driver 610.57.04, CUDA |
| Panel | DaVinci Resolve Mini Panel (USB `1edb:da0a`) |
| Display server | Hyprland (Wayland) with XWayland |

Resolve was installed to `/opt/resolve` from an archive rather than by the
official `.run` installer. Issues 1 and 2 are triggered by that, but the
underlying fragility is in Resolve.

---

## Issue 1 — Panel API library loaded by hardcoded absolute path

**Severity: high.** All DaVinci control panel support silently unavailable.

`DaVinciPanelDaemon` and `libDaVinciPanels.so` load the panel API by absolute
hardcoded path:

```
/usr/lib64/libDaVinciPanelAPI.so
/usr/lib64/libFairlightPanelAPI.so
```

Both libraries **already ship inside the product tree** at
`/opt/resolve/libs/`, and `/opt/resolve/libs` is already on the binary's RPATH.
The daemon nonetheless ignores the copy beside it and looks only in
`/usr/lib64`.

When that path does not exist, the `dlopen` fails, the API version falls back to
its `0.0` default, and the daemon exits before enumerating any hardware. The
panel is never detected. `LD_LIBRARY_PATH` cannot work around this, because the
path is absolute.

### Reproduce

1. Install Resolve to `/opt/resolve` without populating `/usr/lib64`.
2. Connect a Micro or Mini panel. Confirm the USB device is present and
   accessible (`0666`, no kernel driver bound to any interface).
3. Run `/opt/resolve/bin/DaVinciPanelDaemon`.

Observed:

```
opened log file
Opening communication to resolve..
Unsupported DaVinci Panel API Version (0.0), please update
```

### Confirmation

Interposing that single `dlopen` with an `LD_PRELOAD` shim that rewrites
`/usr/lib64/libDaVinciPanelAPI.so` to `/opt/resolve/libs/libDaVinciPanelAPI.so`
— changing nothing else — fixes it completely:

```
DaVinci Panel API Version: 1.0
Panel arrived
DVPB panel: DaVinci Resolve Panel Mini
```

The exported symbols are identical in both locations
(`GetDaVinciPanelInformationInstance_0000`,
`GetDaVinciPanelListenerInstance_0000`), so there is no genuine version skew —
only a failed load.

### Suggested fix

Resolve the library relative to the executable (`$ORIGIN/../libs`) or via the
existing RPATH, and fall back to `/usr/lib64` only if that fails. `/usr/lib64`
does not exist as a real directory on many distributions; on Arch it is a
compatibility symlink to `/usr/lib`.

---

## Issue 2 — `dlopen` failure reported as a version error

**Severity: high (diagnostics).** Directly causes misdirected troubleshooting.

The failure in Issue 1 is reported as:

```
Unsupported DaVinci Panel API Version (0.0), please update
```

Nothing is out of date. The library was never loaded, and `0.0` is an
uninitialised default. The message sends users to update panel firmware and
reinstall Resolve — neither of which can help — and there is no mention of
which library failed or why.

This is compounded by a second misleading message. When Issue 3 below occurs,
Resolve logs:

```
The DaVinci Control Panels Setup application is not compatible with this
version of Resolve. Please re-install Resolve with the DaVinci Control Panels
Setup application option enabled in the installer.
```

That warning names the Control Panels Setup application, which is installed and
intact. It disappears once the unrelated `/opt/resolve/Extras` permission
problem is fixed. Both messages describe a plausible-but-wrong cause with enough
confidence to stop investigation.

### Suggested fix

Distinguish "could not load library" from "loaded library reports an
unsupported version", and include the path and `dlerror()` in the former. Do not
report a version number that was never successfully read.

---

## Issue 3 — DDM fails silently when its storage directory is not writable

**Severity: high.** Entire DaVinci Neural Engine feature set unavailable, with
no user-facing indication.

DDM's storage directory is `/opt/resolve/Extras`. When Resolve cannot create it
— for example because `/opt/resolve` is root-owned and Resolve runs as an
unprivileged user — initialisation fails on every launch:

```
DDM  | ERROR | Failed to initialize DDM: failed to create storage dir
       '/opt/resolve/Extras': failed to create directory ('Permission denied')
DownloadMgr | ERROR | DDM init failed.
```

This is logged and **nothing else happens**. The UI gives no warning. Resolve
runs normally, and features that depend on downloadable content are quietly
unavailable. There is no indication that content is missing, because the
component that would report it is the one that failed.

Creating the directory made Resolve immediately report two packages it had never
been able to fetch:

- Tensor RT Engines — 2.23 GiB
- AI Motion Deblur — 18.5 MiB

The first backs the entire Neural Engine feature set. A user in this state has a
supported NVIDIA GPU, a Studio licence, and no working AI features, with nothing
on screen to explain it.

### Suggested fix

Surface DDM initialisation failure in the UI at least once, rather than only in
the log. Consider falling back to a user-writable location such as
`~/.local/share/DaVinciResolve/Extras` when the system-wide directory is not
writable — a per-user cache needs no privileged location.

The same applies to `/opt/resolve/Fairlight`, which produces repeated
`mkdir failed for directory '/opt/resolve/Fairlight' (errno 13)` errors on every
launch under identical conditions.

---

## Issue 4 — Panel daemon aborts during shutdown

**Severity: low.** Occurs after teardown begins; no data loss observed. Files a
crash report on exit.

`SIGABRT` inside `libudev` during panel daemon teardown, reproduced four times
with an identical stack:

```
/usr/lib/libc.so.6(abort+0x26)
/usr/lib/libudev.so.1(+0x5e52)
/usr/lib/libudev.so.1(+0x1e96e)
/usr/lib/libudev.so.1(+0xaf22)
/usr/lib/libudev.so.1(udev_monitor_unref+0x3d)
libDaVinciPanels.so(HIDLinuxManager::Stop())
libDaVinciPanels.so(HIDLinuxManager::~HIDLinuxManager())
libDaVinciPanels.so(HIDManager::UnregisterDispatcher(...))
libDaVinciPanels.so(BMDLightDispatcher::~BMDLightDispatcher())
libDaVinciPanels.so(PanelController::~PanelController())
libDaVinciPanels.so(BMD_DVP_RunPanelDaemon(int, char**))
Signal Number = 6
```

`abort()` from inside `udev_monitor_unref` is consistent with a double-unref or
use-after-free of the `udev_monitor` — recent libudev aborts on refcount
assertion failure where older versions were permissive. Worth checking the
ownership of the monitor between `HIDLinuxManager::Stop()` and
`~HIDLinuxManager()`, since `Stop()` appears to be reachable from both the
explicit path and the destructor.

`BMDPanelFirmware` also aborts immediately when run with
`QT_QPA_PLATFORM=offscreen`, which may or may not be related.

---

## Summary

| # | Issue | Severity | Fix |
| --- | --- | --- | --- |
| 1 | Panel API library loaded via hardcoded `/usr/lib64` path | High | Prefer `$ORIGIN/../libs`; fall back to `/usr/lib64` |
| 2 | Load failure reported as a version error | High | Report path + `dlerror()`; distinguish the two cases |
| 3 | DDM failure silent; Neural Engine unavailable | High | Surface in UI; fall back to a user-writable directory |
| 4 | Panel daemon `SIGABRT` in `udev_monitor_unref` | Low | Audit `udev_monitor` ownership during teardown |

Issues 1 and 3 each render a purchased hardware or software feature completely
non-functional, and issue 2 makes both substantially harder to diagnose. Fixing
1 alone would make DaVinci control panels work out of the box on any Linux
install that places Resolve outside the official installer's assumptions.
