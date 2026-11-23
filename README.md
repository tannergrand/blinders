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
- Window switch: Crossfade (default) or Instant. macOS makes the new window sharp
  the moment it rises; Crossfade fades the blur in over the old window (a patch
  over its frame plus a 48 pt margin for its shadow, ordered just above it), then
  hands off to the full-screen layer. The patch tints only the window's rounded
  shape, and draws grain on the same screen-fixed grid as the full-screen layer,
  so nothing jumps at the hand-off. Reduce Motion in System Settings makes it instant.
- Speed: Fast, Normal (default), Slow. On/off fade 0.2 / 0.35 / 0.6 s;
  window switch 0.15 / 0.28 / 0.45 s
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
Blinders.app/Contents/MacOS/Blinders --render-patch out.png   # switch patch over a stand-in window
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
- v0.5.1 crossfade, measured with CGWindowList every 25 ms during an
  Outlook → Todoist switch: the new window is on top at once, the patch rises
  0 → 1.00 over the old window by ~200 ms, and the hand-off lands at ~250 ms.
  v0.5.0 had two bugs this fixed: it re-blurred the new window after macOS had
  already made it sharp (sharp → blurred → sharp), and in one direction it
  buried the patch under the full-screen layer, so the old window popped.
  The fixed reverse direction (Todoist → Outlook) is not re-measured yet.
- v0.5.2: the old window's shadow stayed crisp until the hand-off, then snapped
  to blurred. The patch now reaches 48 pt past the window and tints only its
  rounded shape (checked with `--render-patch`). Measured live, the patch sat at
  exactly the old window's frame plus 48 pt on every side, once AppKit's
  menu-bar nudge was turned off for overlay windows (it had moved the patch 22 pt down).
  How the shadow now looks mid-switch is not verified by Claude.
- v0.5.3: an outline of the old window still flashed. The patch's grain tiles
  started at the patch's own corner, so at the hand-off the speckle inside its
  outline jumped to the full-screen layer's pattern, and the margin showed as a
  speckle-free box during the fade. Grain now tiles on a grid fixed to the
  screen in both layers, and the patch draws it across its margin too.
