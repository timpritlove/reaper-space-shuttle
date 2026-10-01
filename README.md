# Space Shuttle

Eine native REAPER-Erweiterung für macOS: Die 3Dconnexion SpaceMouse scrollt und zoomt die Arrange-Ansicht
stufenlos. Je weiter die Kappe ausgelenkt ist, desto schneller bewegt sich die Ansicht, solange man sie hält: ein
Trackpad ohne Rand, oder eben ein Jog Shuttle im Raum.

| Bewegung der Kappe | Wirkung |
|---|---|
| nach links/rechts schieben | horizontal scrollen |
| drücken/ziehen | horizontal zoomen |
| drehen | Playhead bewegen (gestoppt und bei Wiedergabe, nie bei Aufnahme) |
| vor/zurück schieben | Spurliste scrollen |
| rechte Taste halten und drehen | Spurhöhe |
| linke Taste | Autoscroll ein/aus (beim Steuern ohnehin kurz aus, danach gleitet die Ansicht zum Playhead zurück) |
| rechte Taste klicken | Start/Stop (einstellbar) |
| rechte Taste doppelt klicken | Projekt einpassen (einstellbar) |

Einstellungen (Geschwindigkeit, Modus, Belegung, Meldungen): Aktion „Space Shuttle: Settings…“. Mit dem 3DxWare-Treiber
dessen Geschwindigkeitsregler in der Mitte lassen.

Stand: Machbarkeitsprüfung, siehe [docs/feasibility.md](docs/feasibility.md) und die
[Architekturentscheidungen](docs/adr/README.md).

## Installieren

`SpaceShuttle-<Version>.pkg` öffnen (vorher REAPER beenden). Das Paket legt die Erweiterung nur für dich nach
`~/Library/Application Support/REAPER/UserPlugins/reaper_spaceshuttle.dylib`. Entfernen: diese Datei löschen.

Update von 0.1/0.2 (damals `reaper_spacemouse.dylib`): Beim ersten Start legt Space Shuttle die alte Datei in den
Papierkorb und übernimmt nach einem Neustart von REAPER, mit den bisherigen Einstellungen. Tastenkürzel auf den alten
Aktionen „SpaceMouse: …“ müssen neu vergeben werden (ADR-0013).

## Bauen

```sh
make test        # Unit-Tests
make run         # bauen, ins portable Entwicklungs-REAPER (.dev/reaper) installieren und starten
make release     # signiertes, notarisiertes Installationspaket in dist/ (ADR-0009)
```

Voraussetzungen: Xcode 27 / Swift 6.2 oder neuer; für den Treiberweg 3DxWare von 3Dconnexion.
