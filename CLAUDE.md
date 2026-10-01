# reaper-spacemouse – Hinweise für Claude Code

Arbeitstitel. Native REAPER-Erweiterung (`reaper_spacemouse.dylib`, Swift 6, macOS), die REAPERs Arrange-Ansicht mit
einer 3Dconnexion SpaceMouse stufenlos scrollt und zoomt: Auslenkung = Geschwindigkeit, solange die Kappe gehalten
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
- `Sources/SpaceMouseKit` – Werte (`SpaceMouseAxes`, Reports, `ConnexionDeviceState`), Eingänge
  `DriverSpaceMouse` (3DxWare-Client-API, manueller Client `'++++'`, aktiv nur solange REAPER vorn ist) und
  `NativeSpaceMouse` (HID, exklusiv, aus Spacer portiert) hinter `SpaceMouseInput` (ADR-0003).
- `Sources/NavigationCore` – reine Rechnung, getestet: `AxisShaping` (Totzone, Kennlinie, Übersprechen),
  `ArrangeMotion` (Geschwindigkeit → Ansicht, Anker, eigene Bruchteil-Ansicht), `StepAccumulator`,
  `AutoscrollGuard`, `LEDFlash`, `NavigationSettings` (ADR-0004 bis 0006, 0010).
- `Sources/SpaceMouseExtension` – `PluginEntry` (Einstieg, Aktionen), `Navigator` (Takt, Ansicht, Autoscroll,
  Diagnose in der REAPER-Konsole).
- Verwandte Projekte: `~/src/timpritlove/reaper` (Show-Notes-Erweiterung, Swift-Muster), `~/src/timpritlove/stagehand`
  (`docs/spacemouse-findings.md`, `spacemouse-probe`), `~/src/timpritlove/spacer` (SpaceMouse-HID, Flugmodell).

## Bauen und testen
- `make build`, `make test` (swift-testing), `make install` (ins Entwicklungs-REAPER), `make run` (installieren,
  Entwicklungs-REAPER neu starten mit Diagnose in der Konsole), `make dev-reaper` (portables REAPER einrichten).
- Nach jeder Code-Änderung, die der Nutzer ausprobieren soll: `make run`.
- Release: `make release` (`Scripts/release.sh`) → signiertes, notarisiertes Paket `dist/ReaperSpaceMouse-<Version>.pkg`,
  nur für den aktuellen Benutzer (ADR-0009); verweigert ungesicherte Änderungen, `VERSION` vorher erhöhen.
- Nur das portable REAPER in `.dev/reaper` benutzen, nie Ultraschall oder `~/Library/Application Support/REAPER`
  (ADR-0007). Einstellungen: `.dev/reaper/reaper-extstate.ini`, Abschnitt `[spacemouse]`, dann Aktion
  „SpaceMouse: Reload settings“.
- Tests am Gerät brauchen den Nutzer an der SpaceMouse; Ergebnisse in `docs/feasibility.md` („Results“) und in die
  betroffenen ADRs eintragen.

## Regeln (Kurzfassung; Begründung in den ADRs)
- REAPER-API nur auf dem Main Thread; Signaturen exakt nach `reaper_plugin_functions.h`; geladene dylib nie
  überschreiben, nur kopieren + umbenennen (ADR-0002).
- 3DxWare-Helper, stagehand und Spacer nie beenden, um an das Gerät zu kommen. Nativ: Vendor- **und** Product-ID,
  nur exklusiv öffnen, nur verstandene Output-Reports schreiben (LED = Report 4), nie Vendor-Feature-Reports (ADR-0010). Stille vom Treiber nicht als Loslassen deuten, bis gemessen (ADR-0003).
- Treiber: als Anwendung anmelden (`'****'` + Programmname), nie in `ReaperPluginEntry`, erst nach dem Start; die
  manuelle Anmeldung nur als Einstellung. Der Helper 1.4.2 stürzte bei Anmeldung während des Starts ab (ADR-0008).
- Bewegung nach vergangener Zeit, nie pro Takt oder Report; horizontal nur über `GetSet_ArrangeView2`; kein Takt ohne
  Bewegung (ADR-0004).
- Vorzeichen und Belegung nur in `AxisMapping`/Einstellungen; Tempo folgt immer der Auslenkung (ADR-0005).
- Autoscroll nur über die Aktionen 40036/40262 (Name beim Start geprüft), nur zurückschalten, was der Guard selbst
  ausgeschaltet hat oder die Taste verlangt (ADR-0006).
- LED: nativ Report 4, beim Treiber `'3dsl'` (wirkt bei der Compact nicht); jedes Muster endet mit LED an;
  LED-Fehler stoppen oder wechseln nie den Eingang (ADR-0010).
