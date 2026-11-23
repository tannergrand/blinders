# Blinders

Mac app that blurs everything except the active window. Lives in the Dock, not
the menu bar. Closing the window keeps it running; click the Dock icon to get it back.

- Toggle: ⌃⌥B, shake the cursor (side to side or up and down), the switch in the
  window, or right-click the Dock icon
- Opened at login, it starts without showing the window
- Blur: Light, Medium, Heavy
- Grain: Off, Subtle, Strong (film-grain speckle over the blur, see `docs/grain-sample.png`)
- Shake Sensitivity: High, Medium (default), Low
- Fades in and out, easing blur radius and opacity together
- Fade speed: Fast, Normal (default), Slow (0.2 / 0.35 / 0.6 s on and off).
  Switching windows is instant.
- Debug log: `defaults write com.tannergrandstaff.blinders debugLog -bool true`,
  relaunch, then read `~/Library/Logs/Blinders.log`
- Hides during Mission Control (`.transient` collection behavior)
- Automation: `open -g blinders://on`, `blinders://off`, `blinders://toggle`, `blinders://settings`

## Install

1. Download `Blinders-0.5.1.zip` from [Releases](https://github.com/tannergrand/blinders/releases/latest).
2. Unzip it and drag `Blinders.app` into Applications.
3. The app isn't notarized, so macOS blocks the first open. Right-click it and choose **Open**.
   On newer macOS, go to System Settings → Privacy & Security and click **Open Anyway**.

Needs no permissions. Uses a private macOS API for the blur, so a future macOS update could break it.

## Build

```bash
./build.sh             # builds Blinders.app here
./build.sh --install   # copies to ~/Applications and launches it
Blinders.app/Contents/MacOS/Blinders --selftest
Blinders.app/Contents/MacOS/Blinders --shake-bench   # scores shake settings
Blinders.app/Contents/MacOS/Blinders --render-window out.png [--dark]
./tools/make-icon.sh   # redraws Resources/AppIcon.icns from tools/MakeIcon.swift
```

## How it works

- One click-through, borderless window per screen, ordered directly behind the
  frontmost window (`CGWindowListCopyWindowInfo` + `order(.below, relativeTo:)`).
- Blur comes from SkyLight's private `SLSSetWindowBackgroundBlurRadius`, looked
  up with `dlsym`. If it ever disappears, it falls back to `NSVisualEffectView`.
- No TCC permissions: the hotkey is Carbon, and the shake reads mouse-move
  events, which need no Accessibility grant. That's why ad-hoc signing is fine.

## Shake presets

Picked with `--shake-bench`: 600 simulated shakes per size (gentle 40–80 pt,
normal 80–160 pt, vigorous 160–300 pt; 3–6.5 Hz, both axes) and 20 simulated
hours of ordinary mouse use. Synthetic, not recorded from a real hand.

| Preset | Gentle | Normal | Vigorous | False toggles/hr |
|---|---|---|---|---|
| High (legs ≥ 25 pt) | 49% | 100% | 100% | 0 |
| Medium (legs ≥ 35 pt) | 28% | 100% | 100% | 0 |
| Low (legs ≥ 70 pt) | 0% | 81% | 100% | 0 |

All three need four quick turns inside 0.6 s, with no leg slower than 0.3 s.
That last rule took false toggles from about 1.5/hr to 0: it rejects
text-selection scrubs and scrollbar drags. Three turns caught more gentle
shakes but false-toggled 6–33 times an hour, so no preset uses it.

## Verified / not verified (v0.5.2, 2026-11-23)

- Verified: shake-detector logic (13 synthetic cases, both axes, including the sensitivity
  ends), blur symbols resolve on macOS 27.2, overlay lands directly behind the
  frontmost window, off removes it, grain levels measured on a rendered sample.
- Not verified by Claude: the blur's look (no screen capture on this Mac) and a
  real hand shake (synthetic mouse events are dropped without Accessibility),
  and Mission Control hiding (the Mac was locked).
- v0.5.0–0.5.4 tried a crossfade when switching windows. Each round fixed a
  measured cause (re-blurring the new window, a buried patch, the old window's
  shadow, grain that jumped, a frame between two window-server requests), but
  the old window's edge still snapped at the end. v0.6.0 removed the option:
  switching is instant again.
