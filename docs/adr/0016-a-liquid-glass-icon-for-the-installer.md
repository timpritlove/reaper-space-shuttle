# ADR-0016: A Liquid Glass icon made in Icon Composer format, shown in the installer window

- Status: accepted
- Date: 2026-10-01

## Context

Space Shuttle has no app bundle: it is a dylib inside REAPER, delivered as an installer package (ADR-0009). Tim
wants a Liquid Glass icon for the project and the installer that joins the two images of the name (ADR-0013): the
jog shuttle and the Space Shuttle. The sibling projects (stagehand, Spacer) keep their icons as Icon Composer
documents (`AppIcon.icon`: `icon.json` plus flat layer images; the system adds the glass).

A `.pkg` file cannot carry its own icon: a custom Finder icon lives in extended attributes, which downloads drop and
which are not part of the signature. What the installer can show is a background image in its window
(`<background>` in the distribution, with a separate one for dark mode).

## Decision

- Motif: a SpaceMouse seen from above (dark base, blue LED ring, knurled cap) whose cap has the finger dimple of a
  jog shuttle, on a blue gradient. A first draft with a Space Shuttle orbiting on a jog shuttle ring was too busy
  (Tim); the name already says "space", the dimple says "shuttle".
- `Packaging/AppIcon.icon` in Icon Composer format; its layers are drawn by code (`Scripts/make-icon-layers.swift`,
  CoreGraphics), not by hand, so the icon can be changed and rebuilt.
- `make icon` (`Scripts/make-icon.sh`) redraws the layers, renders the icon with Icon Composer's `ictool` and writes
  `Packaging/Resources/background.tiff` and `background-dark.tiff` (128 pt icon in the lower left, 1x and 2x) and
  `docs/icon.png` for the README. The results are committed; a release needs neither Xcode's `ictool` nor
  ImageMagick.
- The distribution shows the icon as the installer window's background, bottom left, unscaled.

## Consequences

- The `.pkg` file itself keeps the generic installer icon in Finder.
- A changed icon needs `make icon` and a commit of the rendered images.
- The icon is ready for an app bundle should one come (settings app, ADR-0012 alternatives).

## Rules

- Change the icon through `Scripts/make-icon-layers.swift` and `make icon`, never by editing the rendered images.

## Enforced and verified by

- `Scripts/make-icon-layers.swift`, `Scripts/make-icon.sh`, `Packaging/distribution.xml`; rendered with `ictool`
  (Default and Dark) and looked at; a test package built with `productbuild` contains both backgrounds.
- Open check: how the background looks in the running Installer (position, size, light and dark mode).
