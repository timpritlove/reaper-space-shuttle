# Feasibility: SpaceMouse navigation inside REAPER

Status: in progress, started 2026-10-01. This file is also the hand-over from the conversation in the stagehand
repository in which the idea was developed (2026-09-30/10-01); a new session here should read it first.

## The idea (Tim)

Scroll and zoom REAPER's arrange view with a 3Dconnexion SpaceMouse, **continuously and at variable speed**: how
hard the cap is pushed sets how fast the view moves, for as long as it is held — an "endless trackpad". Scroll and
zoom at the same time. With a trackpad the speed can be varied by hand, but the finger reaches the edge; the
SpaceMouse has no edge.

Decided along the way:

- A native REAPER extension that provides this "from inside" REAPER. stagehand is not involved; how the two could
  coexist later is a separate question (both want the device).
- Modern Swift throughout.
- First try it with 3Dconnexion's own driver (3DxWare) running; if that does not work, read the device ourselves
  (code and knowledge from stagehand and Spacer).
- Controls: slide left/right = scroll, push/pull = zoom, slide forward/back = track list, twist = track height;
  deflection sets speed everywhere.
- Left button toggles autoscroll; while the SpaceMouse steers, autoscroll is off temporarily and comes back after a
  short rest.
- 60 Hz by default; if that proves too fine or too costly, skip values and go down to 30 Hz.
- If feasibility is shown, this becomes its own product/repository (this one).

## Why not synthesized trackpad events

Posting `CGEventCreateScrollWheelEvent2` (pixel units, continuous, with phases) would make REAPER believe a trackpad
scrolls. Rejected: pinch zoom cannot be synthesized with public API (zoom would need modifier + wheel from REAPER's
mouse modifier settings, and modifiers are per event, so scroll and zoom would have to alternate); events go to the
window under the pointer; posting needs Accessibility; REAPER applies its own acceleration. stagehand's ADR-0083 also
rules out mouse/keyboard emulation there.

## Why GetSet_ArrangeView2

The REAPER API sets the visible time range directly (`GetSet_ArrangeView2`, seconds as doubles), so scroll and zoom
are one call per tick, stepless, independent of pointer and focus. Other API (`CSurf_OnScroll`, `CSurf_OnZoom`,
`adjustZoom`) moves in whole steps. Vertical scrolling has no equivalent: steps via `CSurf_OnScroll(0, n)`, track
heights via `CSurf_OnZoom(0, n)` (or `I_HEIGHTOVERRIDE` + `TrackList_AdjustWindows`, or the arrange window's scroll
bar through SWELL, as SWS and js_ReaScriptAPI do). The formula is in ADR-0004.

A ReaScript (Lua, `defer` loop) could do the same motion, but Lua in REAPER has no sockets and no HID access, so the
data would have to come from outside (MIDI CC via IAC, web interface ext state). A native extension reads the device
itself. Prior art searched 2026-10-01: nothing that connects a SpaceMouse to REAPER natively; "SmoothWheelScroll"
(Windows only) animates wheel notches by running REAPER actions in small portions.

## What we build on

- **Show Notes extension** (`~/src/timpritlove/reaper`): Swift REAPER extension, spike 2026-09-24 with REAPER 7.80
  — Swift dylib loads, `ReaperPluginEntry`/`timer`/control surface/`DispatchQueue.main` on one thread, portable
  development REAPER, install by copy+rename.
- **stagehand** (`~/src/timpritlove/stagehand`, `docs/spacemouse-findings.md`, ADR-0083/0084): SpaceMouse Compact
  report format, axis signs, crosstalk, seize behaviour, the vendor driver's architecture, the client API's routing
  (manual client `'++++'` + `'3dac'`), `spacemouse-probe`.
- **Spacer** (`~/src/timpritlove/spacer`, ADR-0012/0013/0015): `SpaceMouseHID` (seized HID reader, ported here),
  rate control with dead zone 0.12 and exponent 2, motion by elapsed time.
- Seen on Tim's Mac 2026-10-01: Ultraschall.app = REAPER 7.81, hardened runtime with
  `disable-library-validation`; `UserPlugins` holds SWS, js_ReaScriptAPI, `reaper_ultraschall.dylib`. 3DxWare
  running (helper, NLServer, radial menu, virtual numpad).

## Test plan

Everything is built and unit-tested. What only REAPER and the device can answer, in order:

1. **Loading**: `make run` → development REAPER starts, console shows "Space Shuttle: diagnostics on, REAPER 7.81 …,
   autoscroll actions found". Actions "Space Shuttle: …" appear in the action list.
2. **Driver path** (3DxWare running): console "using 3DxWare driver", "connected: … client N". Move the cap with
   REAPER in front: axis events per second appear; view scrolls/zooms. Watch:
   - events per second while holding still (does the driver repeat unchanged states?) → ADR-0003 watchdog rule;
   - peaks at full deflection → `full_scale`;
   - directions (x right = later, z push = zoom in) → inversion settings;
   - switch to another app: events stop, the other app gets its SpaceMouse back; switch back: it works again.
3. **Motion**: smoothness at 60 Hz and 30 Hz (`tick_rate`), in an empty and in a large project; CPU; slow speeds
   still move (pixel rounding); clamping at project start and maximum zoom.
4. **Vertical**: direction and feel of track-list scrolling and track height.
5. **Autoscroll**: play, scroll with the cap → autoscroll turns off, comes back 0.75 s after release; left button
   toggles; the same while recording.
6. **Native path**: quit the 3DxWare helper (stagehand findings: `launchctl bootout gui/<uid>/com.3dconnexion.helper`
   plus `killall 3DconnexionHelper 3DxRadialMenu 3DxVirtualNumpad`; back with `open /Applications/3DconnexionHelper.app`),
   set `input=native` or rely on the fallback; repeat 2–5. Input Monitoring prompt for REAPER?
7. **Ultraschall**: copy the dylib into Ultraschall's `UserPlugins` only after 1–6 look good.

Settings go into `.dev/reaper/reaper-extstate.ini`, section `[spaceshuttle]` (keys in `NavigationSettings`), then
action "Space Shuttle: Reload settings".

## Results

### 2026-10-01, first runs (development REAPER 7.81, 3DxWare 1.4.2)

- **Loading works**: the Swift dylib loads in REAPER 7.81 (ad-hoc signed; REAPER has
  `disable-library-validation`) and registers its actions.
- **Action lookup**: `kbd_getTextFromCmd(cmd, nil)` finds nothing. During `ReaperPluginEntry` the action list holds
  only the 7 actions registered so far; REAPER's own actions appear later. Looked up by name 2 s after start:
  40036 = "View: Toggle auto-view-scroll during playback", 40262 = "View: Toggle auto-view-scroll while recording".
- **3DconnexionHelper crashed** (00:17:24, SIGABRT, `-[__NSArrayM insertObject:atIndex:]: object cannot be nil`,
  thrown in a notification observer while handling an input report of the physical SpaceMouse). Just before, the
  development REAPER had been ended with `pkill` while (probably) holding a registered manual client. Hypothesis: a
  client whose process dies without `UnregisterConnexionClient` leaves the helper with a stale client, and the next
  device report crashes it. Not yet proven. Consequence already taken: `make run` quits REAPER through
  `NSRunningApplication.terminate` (by PID, never kill), so the extension unregisters. The helper does not restart
  by itself.
- With the helper dead, `RegisterConnexionClient` returns 0 after about **2.5 s blocking the main thread**; the
  fallback to native HID then works (device seized). A dead helper therefore costs 2.5 s at REAPER start.

### 2026-10-01, Tim's first test (native HID, helper crashed before)

- 62 axis events/s while deflected, 60 ticks and 60 view sets per second; all-zero pairs on release arrive; peaks
  350 on x, z, rz (y 336). The core works "quite well".
- Changes asked for and made: more acceleration at high deflection (exponent 3, top speeds doubled), twist scrolls
  like sliding, track height off (stepped, does not fit), autoscroll back later (1.5 s) and first a glide back to the
  play position (ADR-0006).
- Found while testing: scroll during zoom was integrated with the end-of-tick width, a small tick-rate dependence;
  now integrated exactly.

### 2026-10-01, driver path: the helper crashes

- Five crashes of 3DconnexionHelper 1.4.2 (00:17, 00:55, 00:57, 00:58, 00:59), all with the identical stack
  (helper offsets 96928/87024 ← notification ← 160320/150076 ← HID input report callback, `insertObject: nil`).
- 00:55 and 00:57: 0.4 s after the extension called `RegisterConnexionClient` inside REAPER (clocks matched via
  `systemUptime`); the call then timed out after 2 s ("Failed to connect to dedicated communication channel").
  Launching REAPER through LaunchServices instead of executing the binary did not change it.
- 00:58 and 00:59: the helper crashed 1.5 s after its own start, without any registration, while the development
  REAPER was the active app (holding the device through the native fallback).
- The same manual registration from stagehand's `spacemouse-probe` (command line, no bundle) works with 1.4.2:
  client 4096, activation ok, no crash. On 2026-09-26 (helper 1.4.1) it worked too.
- Without a running REAPER the helper stays up.
- Hypothesis: the helper looks up its configuration for the *active application*; for REAPER it has none and inserts
  nil. Next test (Tim's idea): add REAPER manually as an application in the 3DxWare settings.
- The proper `pkill` hypothesis from the first crash is refuted (no client was registered at 00:55/00:57).

### 2026-10-01, driver path works

- After Tim added both REAPERs as applications in the 3DxWare settings, and with the registration changed to the
  application style (`'****'` + process name) 2 s after start (ADR-0008): client 4096, no crash, everything works.
  Data only while REAPER is frontmost; about 60 events per second while deflected; zero state on release.
- With the 3DxWare speed slider in the middle the speeds equal the native path (Tim). Driver values are pre-scaled
  (peaks up to 2640), so our curve saturates early; slider positions above the middle add nothing. Open.
- Added an overall `speed` factor (default 1) for the native path, and for everyone who wants more.
- 3DxWare forgot the application entries after its settings were reopened. Tested again without them (`input=auto`
  chose the driver): works, no crash. No setup step in 3DxWare needed.
- Vertical lock added: a movement that starts horizontal does not scroll the track list (ADR-0005).
- A sixth helper crash at 01:02:44 (helper started 01:00:18, same stack, from an input report); not noticed at the
  time. Unclear whether it happened with the application registration. Its LaunchAgent has `KeepAlive` false, so
  the helper stayed down until started by hand.

### 2026-10-01, release 0.1 in Ultraschall

- Installed with the package; on first launch `SetConnexionHandlers returned -36` and fallback to native HID. Cause:
  the helper was not running (crashed at 01:02, see above), not the release. `-36` means "no helper".
- After quitting Ultraschall, `open -a 3DconnexionHelper`, and relaunching Ultraschall: works through the driver, no
  crash.

### 2026-10-01, LED flash for the autoscroll button (ADR-0010)

- Driver path: the flash is not visible (Tim). `'3dsl'` returned 0 (nothing logged), matching stagehand's finding
  that the driver ignores it on the Compact. Writing report 4 past the helper fails (`kIOReturnNotOpen` without an
  open, `kIOReturnExclusiveAccess` with a shared one), so the LED is native only.
- Native path: built, not yet seen at the device.
- Native path at the device (helper stopped, `input=auto` fell back to native): works (Tim).

### 2026-10-01, keyboard in an extension's own window: Cocoa vs. SWELL

Spike `reaper_uitest.dylib` (ObjC++, not in the repository): text field windows in the development REAPER, keys
sent through `[NSApp sendEvent:]` (the path real key events take), REAPER's play state and project state change
count watched, every `accelerator` hook call logged.

- Plain keys (letters, space, backspace, arrows, tab) reach the text field in **every** variant, Cocoa and SWELL, with
  or without hook; space does not start playback, letters trigger no actions. REAPER recognises a focused text view
  itself.
- The hook sees identical messages for both (`WM_KEYDOWN`/`WM_KEYUP`, hwnd = the field editor `NSTextView`).
  Returning -1 changes nothing; -10 ("raw") makes it worse (Cmd-A then goes to REAPER from SWELL too). A hook that
  performs the edit command itself and returns 1 did not stop the Cmd keys either.
- **Cmd keys** are the difference:
  - plain Cocoa window: Cmd-A and Cmd-Z (and Cmd-V) go to REAPER's menu (project state changes: select all, project
    undo), not to the field;
  - SWELL edit field: Cmd-A, Cmd-C, Cmd-V work in the field, but **Cmd-Z undoes the REAPER project**;
  - Cocoa window subclass overriding `performKeyEquivalent:` to send `selectAll:`/`copy:`/`paste:`/`cut:`/`undo:`/
    `redo:` to the first responder when a text view has focus: all of them work in the field, including field undo,
    and REAPER's project stays untouched.
- Conclusion: a Cocoa (SwiftUI) window with that window subclass handles the keyboard better than SWELL.
- SwiftUI `TextField` in the real settings window (`EditKeysWindow` + `NSHostingController`, temporary spike code):
  the first responder is SwiftUI's own field editor (`_SystemTextFieldFieldEditor`, an `NSText`); with the window
  class every edit key worked and the project stayed untouched in 4 of 6 runs. In the two failed runs the Cmd keys
  reached REAPER; the runs after adding logging showed REAPER active with our window key every time, so the failures
  were most likely runs where REAPER was not frontmost (no key window). Open: real keystrokes (ADR-0012).

### 2026-10-01, native side by side with SpaceScroll (ADR-0015)

- Helper stopped, `input` auto (fell back to native: `-36`, then "connected: native HID, SpaceMouse Compact"),
  SpaceScroll (`~/src/timpritlove/spacescroll`) running natively at the same time.
- Tim: both work — Space Shuttle navigates while REAPER is in front, SpaceScroll scrolls the other apps.
- Not checked in detail: Cmd-Tab with the cap deflected, "device busy", stray scrolling while switching, the LED after
  a reopen.

## Later

- Coexistence with stagehand (both want the device; with the driver path both could be clients).
- Other SpaceMouse models (PIDs, buttons) in native mode.
- Settings UI inside REAPER, help, distribution (universal, signed, notarized; ReaPack?).
- MIDI editor view (no public API to set its view, open).
