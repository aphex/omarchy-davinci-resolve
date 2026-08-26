-- DaVinci Resolve window rules for Hyprland under Omarchy.
--
-- Omarchy 4.0.1 ships rules that make Resolve float, stay focused and fully
-- opaque, but its modal dialogs still trap the pointer: focus-follows-mouse
-- warps the cursor back into the dialog, so Preferences > Media Storage > Add
-- becomes a roach motel and the screenshot selector never sees the pointer.
--
-- This is omarchy PR #6919, which had not landed in 4.0.1. Drop these lines
-- into ~/.config/hypr/hyprland.lua (they load after Omarchy's defaults and
-- override them). Remove once an Omarchy release includes the PR.

o.window(".*[Rr]esolve.*", { no_follow_mouse = true })
o.window({
  class = ".*[Rr]esolve.*",
  title = "^(DaVinci Resolve( Studio)? - .+|Project Manager|Preferences|Find Directory|Dialog)$",
}, { stay_focused = false })
