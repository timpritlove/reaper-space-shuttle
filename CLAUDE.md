# Space Shuttle (reaper-space-shuttle) – Hinweise für Claude Code

Space Shuttle (nach dem Jog Shuttle; ADR-0013). Native REAPER-Erweiterung (`reaper_spaceshuttle.dylib`, Swift 6,
macOS), die REAPERs Arrange-Ansicht mit einer 3Dconnexion SpaceMouse stufenlos scrollt und zoomt: Auslenkung = Geschwindigkeit, solange die Kappe gehalten
wird („unendliches Trackpad“). Zuerst Machbarkeit; **Übergabe und Testplan: `docs/feasibility.md` zuerst lesen.**
Sprache mit dem Nutzer: Deutsch. Code, Kommentare, ADRs und Docs auf Englisch (README/CLAUDE.md deutsch).

## Arbeitsweise: ADRs
- Entscheidungen in `docs/adr/` (Index `docs/adr/README.md`, Vorlage `template.md`, Prozess ADR-0001).
- Jede neue Entscheidung zu Architektur, Gerätezugriff, REAPER-Anbindung, Build oder Verteilung bekommt einen ADR im
  selben Commit wie der Code; nächste freie Nummer aus dem Index.
- Verstößt eine Änderung gegen die `Rules` eines ADR, braucht es einen ablösenden ADR (alter wird
  `superseded by`, nicht umgeschrieben).
- „Enforced and verified by“ ehrlich halten: nur gebaut = offene Prüfung in REAPER bzw. am Gerät.

## Aufbau
- `Sources/ReaperBridge` – C-Spiegel von `reaper_plugin_info_t` und `custom_action_register_t`.
- `Sources/ReaperKit` – `ReaperAPI`, getypte REAPER-Funktionen über `GetFunc`, `@MainActor` (ADR-0002).
- SpaceMouse: Paket `space-juggler` (`github.com/metaebene/space-juggler`, Git-Abhängigkeit mit Versions-Tag; zum Entwickeln `swift package edit` oder lokaler Override): Werte aus
  `SpaceMouseKit`, Eingabe über Space Juggler (`SpaceJugglerConnection`, Anspruch = REAPERs Bundle-ID; ADR-0017).
  `Space Juggler.app` liegt neben der Erweiterung in `UserPlugins` (`Scripts/space-juggler.sh`, Installation, Paket).
- `Sources/NavigationCore` – reine Rechnung, getestet: `AxisShaping` (Totzone, Kennlinie, Übersprechen),
  `ArrangeMotion` (Geschwindigkeit → Ansicht, Anker, eigene Bruchteil-Ansicht), `StepAccumulator`,
  `PlayheadMotion`, `AutoscrollGuard`, `LEDFlash`, `SpeedScale`, `ControlsDescription`, `NavigationSettings` (ADR-0004 bis 0006,
  0010, 0012, 0014).
- `Sources/SpaceShuttleExtension` – `PluginEntry` (Einstieg, Aktionen), `Navigator` (Takt, Ansicht, Autoscroll,
  Diagnose in der REAPER-Konsole), `SettingsWindow` (SwiftUI-Fenster „Space Shuttle: Settings…“, ADR-0012).
- Verwandte Projekte: `~/src/timpritlove/reaper` (Show-Notes-Erweiterung, Swift-Muster), `~/src/timpritlove/stagehand`
  (`docs/spacemouse-findings.md`, `spacemouse-probe`), `~/src/timpritlove/spacer` (SpaceMouse-HID, Flugmodell).

## Bauen und testen
- `make build`, `make test` (swift-testing), `make install` (ins Entwicklungs-REAPER), `make run` (installieren,
  Entwicklungs-REAPER neu starten mit Diagnose in der Konsole), `make dev-reaper` (portables REAPER einrichten).
- Nach jeder Code-Änderung, die der Nutzer ausprobieren soll: `make run`.
- Icon: `make icon` (`Scripts/make-icon.sh`) zeichnet `Packaging/AppIcon.icon` neu und rendert die Installer-Bilder
  und `docs/icon.png`; Motiv nur in `Scripts/make-icon-layers.swift` ändern (ADR-0016).
- Release: `make release` (`Scripts/release.sh`) → signiertes, notarisiertes Paket `dist/SpaceShuttle-<Version>.pkg`,
  nur für den aktuellen Benutzer (ADR-0009); verweigert ungesicherte Änderungen, `VERSION` vorher erhöhen.
- Nur das portable REAPER in `.dev/reaper` benutzen, nie Ultraschall oder `~/Library/Application Support/REAPER`
  (ADR-0007). Einstellungen: `.dev/reaper/reaper-extstate.ini`, Abschnitt `[spaceshuttle]`, dann Aktion
  „Space Shuttle: Reload settings“.
- Tests am Gerät brauchen den Nutzer an der SpaceMouse; Ergebnisse in `docs/feasibility.md` („Results“) und in die
  betroffenen ADRs eintragen.

## Regeln (Kurzfassung; Begründung in den ADRs)
- REAPER-API nur auf dem Main Thread; Signaturen exakt nach `reaper_plugin_functions.h`; geladene dylib nie
  überschreiben, nur kopieren + umbenennen (ADR-0002).
- Die SpaceMouse nie selbst öffnen: nur Space Juggler hält sie und gibt sie REAPER, solange es vorn ist (ADR-0017).
  Nichts davon in `ReaperPluginEntry`. Den 3DxWare-Treiber behandelt Space Juggler (space-juggler ADR-0004).
- Im Paket für die Verteilung ist `Space Juggler.app` nicht verschiebbar (`BundleIsRelocatable` aus), sonst legte der
  Installer sie auf die Kopie einer anderen App.
- Bewegung nach vergangener Zeit, nie pro Takt oder Report; horizontal nur über `GetSet_ArrangeView2`; kein Takt ohne
  Bewegung (ADR-0004).
- Drehung bewegt den Abspielcursor (Geschwindigkeit wie beim Scrollen), nie während einer Aufnahme; Scrollen und Drehen schließen einander aus (ADR-0014).
- Vorzeichen und Belegung nur in `AxisMapping`/Einstellungen; Tempo folgt immer der Auslenkung (ADR-0005).
- Autoscroll nur über die Aktionen 40036/40262 (Name beim Start geprüft), nur zurückschalten, was der Guard selbst
  ausgeschaltet hat oder die Taste verlangt (ADR-0006).
- LED: über Space Juggler (`setLEDs`, Report 4); jedes Muster endet mit LED an; LED-Fehler stoppen nie die Eingabe
  (ADR-0010).
- Konsole nur für Diagnose; Meldungen für Nutzer über `report` (landen in `messages` für ein Einstellungsfenster)
  (ADR-0011).
- Einstellungen nur im SwiftUI-Fenster; Fenster mit Textfeldern über `EditKeysWindow` (sonst nimmt REAPERs Menü
  Cmd-A/C/V/Z, Cmd-Z macht das Projekt rückgängig); Änderungen wirken sofort und landen im Extension-State (ADR-0012).
- Name: „SpaceMouse“ nur für das Gerät (`SpaceMouseKit` usw.), alles Produktseitige heißt Space Shuttle; eine
  `reaper_spacemouse.dylib` daneben wandert beim Laden in den Papierkorb, dann ohne Eingang bis zum Neustart
  (ADR-0013).
