# ADR-0002: Build a native REAPER extension in Swift and call REAPER only on its main thread

- Status: accepted
- Date: 2026-10-01

## Context

The goal is SpaceMouse navigation "from inside" REAPER, without stagehand or any other helper app running. A REAPER
extension is a dynamic library `UserPlugins/reaper_*.dylib` exporting `ReaperPluginEntry(hInstance, rec)`; REAPER API
functions are obtained by name via `rec->GetFunc`.

The Show Notes extension (`~/src/timpritlove/reaper`, ADR-0003/0004 and spike 2026-09-24 there) verified with
REAPER 7.80: a Swift dylib with `@_cdecl("ReaperPluginEntry")` loads and runs, `ReaperPluginEntry`, `timer`, control
surface callbacks and `DispatchQueue.main` all run on the same (main) thread.

Ultraschall.app (REAPER 7.81) is signed with hardened runtime and `com.apple.security.cs.disable-library-validation`
(seen 2026-10-01), so a library signed by another team loads.

## Decision

- The extension is written in modern Swift (Swift 6 language mode, strict concurrency), built with SwiftPM as the
  dynamic library product `reaper_spacemouse`, installed as `reaper_spacemouse.dylib`.
- REAPER functions are bound in `ReaperKit` as `@convention(c)` types from `GetFunc`; the binding is `@MainActor`.
- `ReaperBridge` is a C header mirroring `reaper_plugin_info_t` and `custom_action_register_t`; no WDL/SWELL headers.
  No control surface is needed so far (no C++ shim).
- Work that needs regular time (the motion ticks) uses `DispatchSourceTimer` on the main queue.

## Consequences

- Same toolchain and patterns as Show Notes; code can move between the two.
- A crash in the extension takes REAPER down, possibly during a recording: the extension does nothing but read the
  device and set the view, and never blocks the main thread.
- The dylib must eventually be universal (arm64 + x86_64) and signed for distribution; not yet done.

## Rules

- Call the REAPER API only on the main thread; C callbacks from REAPER check `pthread_main_np()` before entering the
  main actor.
- Bind REAPER functions only with the exact signatures of `reaper_plugin_functions.h`.
- Never overwrite a loaded dylib in place; install by copy and rename (a running REAPER would crash).

## Enforced and verified by

- `ReaperKit/ReaperAPI.swift` (`@MainActor`), `SpaceMouseExtension/PluginEntry.swift`, `Scripts/install-extension.sh`.
- Verified in Show Notes (REAPER 7.80). Open check here: loading in REAPER 7.81 (development REAPER) and in
  Ultraschall.
