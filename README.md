# reaper-spacemouse

Arbeitstitel. Eine native REAPER-Erweiterung für macOS: Die 3Dconnexion SpaceMouse scrollt und zoomt die
Arrange-Ansicht stufenlos. Je weiter die Kappe ausgelenkt ist, desto schneller bewegt sich die Ansicht, solange man
sie hält: ein Trackpad ohne Rand.

| Bewegung der Kappe | Wirkung |
|---|---|
| nach links/rechts schieben oder drehen | horizontal scrollen |
| drücken/ziehen | horizontal zoomen |
| vor/zurück schieben | Spurliste scrollen |
| rechte Taste halten und drehen | Spurhöhe |
| linke Taste | Autoscroll ein/aus (beim Steuern ohnehin kurz aus, danach gleitet die Ansicht zum Playhead zurück) |
| rechte Taste doppelt klicken | Projekt einpassen (einstellbar) |

Stand: Machbarkeitsprüfung, siehe [docs/feasibility.md](docs/feasibility.md) und die
[Architekturentscheidungen](docs/adr/README.md).

## Bauen

```sh
make test        # Unit-Tests
make run         # bauen, ins portable Entwicklungs-REAPER (.dev/reaper) installieren und starten
```

Voraussetzungen: Xcode 27 / Swift 6.2 oder neuer; für den Treiberweg 3DxWare von 3Dconnexion.
