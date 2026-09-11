-- DaVinci Resolve window rules for Hyprland under Omarchy.
--
-- Verified against Omarchy 4.0.3, Hyprland 0.56.2, Resolve Studio 21.1 build 17.
--
-- Omarchy's own rules (default/hypr/apps/davinci-resolve.lua) put
-- stay_focused = true on *every* Resolve window, then exempt a short allowlist
-- of window titles. The allowlist has never kept up with Resolve:
--
--   * 21.1's "Project Settings" is not on it.
--   * Resolve's transient popups, menus and file pickers all map with the
--     generic title "resolve", so they are not on it either. (Confirm with
--     `xdotool search --class resolve getwindowname %@` while one is open.)
--
-- Every window that misses the allowlist pins the focus. With one modal up
-- that merely looks like a modal grab; open a second from inside the first --
-- Project Settings -> a file picker, Preferences -> Media Storage -> Add --
-- and the two fight over focus, so clicks land on the wrong window or appear
-- to do nothing at all.
--
-- no_follow_mouse is what actually fixes the original complaint (focus follows
-- the mouse, so Hyprland warps the pointer back into the dialog). stay_focused
-- buys nothing on top of it, so drop it for Resolve outright. A later rule of
-- the same type wins, which is what lets this user-side rule neutralise
-- Omarchy's.
--
-- Upstream status:
--   PR #6919 (adds no_follow_mouse)  merged to `quattro` 2026-08-28, but NOT
--                                    in the v4.0.3 tag -- still needs backport.
--   PR #9508 (drops stay_focused)    open as of 2026-09-10.
--
-- Append to ~/.config/hypr/hyprland.lua -- user config loads after Omarchy's
-- defaults -- then `hyprctl reload` and check `hyprctl configerrors`.
-- Delete this block once an Omarchy release ships both PRs.

o.window(".*[Rr]esolve.*", { no_follow_mouse = true, stay_focused = false })

-- Resolve is XWayland-only, so Hyprland honours whatever geometry its dialogs
-- ask for -- and on HiDPI they ask for far too little. Measured on 21.1:
-- "Find Directory" opens at 322x400 every time and has to be dragged out by
-- hand. 875x600 is Omarchy's own floating-window size, and close to where these
-- land once resized. This is the third commit of PR #9508, which reaches it by
-- tagging "+floating-window" instead -- that works from inside Omarchy's own
-- config, but not from here: the rules that act on the tag are declared in
-- default/hypr/apps/system.lua, which has already been evaluated by the time a
-- user config loads. Setting the geometry directly sidesteps the ordering.
--
-- Only "Find Directory" is confirmed present in 21.1; the other titles come
-- from #9508 and simply do not match if Resolve never uses them.
o.window({
  class = ".*[Rr]esolve.*",
  title = "^(Find Directory|Open|Save As|Project Media Location)$",
}, { float = true, center = true, size = { 875, 600 } })

-- Optional: the Project Manager opens undersized on a HiDPI display.
-- o.window({ class = "^resolve$", title = "^Project Manager$" }, { center = true, size = { 1600, 1000 } })
