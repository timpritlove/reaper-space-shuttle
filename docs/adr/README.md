# Architecture Decision Records

Process: [ADR-0001](0001-record-architecture-decisions.md). Template: [template.md](template.md).

| ADR | Title | Status |
|---|---|---|
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions | accepted |
| [0002](0002-swift-extension-on-reapers-main-thread.md) | Build a native REAPER extension in Swift and call REAPER only on its main thread | accepted |
| [0003](0003-spacemouse-input-driver-first-native-fallback.md) | Read the SpaceMouse through the 3DxWare client API first, natively over HID as fallback | accepted, registration superseded by 0008, write rule by 0010, native hold by 0015 |
| [0004](0004-rate-control-of-the-arrange-view.md) | Drive the arrange view by rate control through GetSet_ArrangeView2 | accepted |
| [0005](0005-axis-mapping-and-shaping.md) | Map four cap movements to scroll and zoom, shaped by dead zone, curve and crosstalk suppression | accepted, twist moved to the play cursor by 0014 |
| [0006](0006-autoscroll-yields-to-the-spacemouse.md) | Suspend autoscroll while the SpaceMouse moves the view; the left button toggles it | accepted |
| [0007](0007-develop-against-a-portable-reaper.md) | Develop and test against a portable REAPER in .dev, never against Ultraschall | accepted |
| [0008](0008-register-with-3dxware-as-the-application.md) | Register with 3DxWare as the application, after REAPER has launched | accepted |
| [0009](0009-distribute-as-a-per-user-installer-package.md) | Distribute as a signed, notarized per-user installer package | accepted |
| [0010](0010-flash-the-led-to-confirm-the-autoscroll-button.md) | Write the SpaceMouse LED natively; flash it to confirm the autoscroll button | accepted |
| [0011](0011-the-console-is-for-diagnostics-only.md) | Use REAPER's console for diagnostics only; keep user messages for a settings window | accepted |
| [0012](0012-settings-window-in-swiftui.md) | A settings window in SwiftUI inside the extension, with a window class for edit keys | accepted |
| [0013](0013-name-the-extension-space-shuttle.md) | Name the extension Space Shuttle and retire reaper_spacemouse.dylib | accepted |
| [0014](0014-twist-moves-the-play-cursor.md) | Twist moves the play cursor by rate control, never while recording | accepted |
| [0015](0015-seize-the-device-natively-only-while-reaper-is-active.md) | Seize the device natively only while REAPER is active, so other programs can have it meanwhile | accepted |
| [0016](0016-a-liquid-glass-icon-for-the-installer.md) | A Liquid Glass icon made in Icon Composer format, shown in the installer window | accepted |
