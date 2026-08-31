# DumbCommander

DumbCommander ist ein nativer, tastaturorientierter Zwei-Panel-Dateimanager für macOS. Das Interaktionsvorbild ist [Total Commander](https://www.ghisler.com/deutsch.htm): Quelle und Ziel bleiben gleichzeitig sichtbar, das aktive Panel ist eindeutig und häufige Dateioperationen sind ohne Maus erreichbar. Die App ist kein pixelgenauer Klon und steht in keiner Verbindung zu Ghisler Software.

> **Projektstatus: stabilisierter Prototyp, noch nicht produktionsreif.** Die Sicherheitsbasis und das getrennte Panelmodell aus Stufe 0 und 1 sind umgesetzt. Für einen alltagstauglichen Einsatz fehlen insbesondere vollständige Konfliktbehandlung, Fortschritt, Abbruch und weitere Tests der Dateioperationen.

## Umsetzungsstand

Am 31. August 2026 wurden die ersten beiden Stufen der [Roadmap](ROADMAP.md) abgeschlossen:

- Stufe 0: macOS-only-Konfiguration, einheitliches Deployment Target, sichere Papierkorbsemantik, dokumentiertes Distributionsmodell, experimentell gekennzeichnete Shell und temporäre Testumgebung.
- Stufe 1: unabhängige Zustände beider Panels, stabile URL-basierte Auswahl und Markierungen, vorab geladene Dateimetadaten, asynchroner und testbarer Dateisystemdienst sowie Schutz vor veralteten Ladeergebnissen.

Der ausführliche Arbeitsnachweis steht unter [docs/progress/2026-08-31-stufen-0-und-1.md](docs/progress/2026-08-31-stufen-0-und-1.md). Die Entscheidung zu Distribution und Dateizugriff ist in [ADR 0001](docs/decisions/0001-distribution-and-file-access.md) festgehalten.

## Zielbild

DumbCommander soll sich wie ein nativer macOS-Commander anfühlen:

- zwei gleichwertige Panels mit eindeutigem aktiven Quell- und inaktivem Zielpanel;
- vollständige Tastaturbedienung und stabile Fokusführung;
- sichere, nachvollziehbare Dateioperationen ohne stilles Überschreiben oder endgültiges Löschen;
- reaktionsfähige Navigation auch in großen Verzeichnissen;
- später Viewer, Suche, Mehrfachumbenennung, Vergleich, Synchronisation, Tabs und Archive.

Datenschutz und Vorhersagbarkeit haben Vorrang vor Funktionsumfang.

## Aktueller Funktionsumfang

| Bereich | Stand | Noch offen |
| --- | --- | --- |
| Zwei Panels | Unabhängige Verzeichnisse, Cursor, Markierungen, Sortierung und Verlauf; aktives Panel ist Quelle | Sitzungswiederherstellung und Tabs |
| Navigation | `.`, `..`, Pfeiltasten, Enter, Tab, direkte Pfadeingabe, Rück-/Vorwärtsmodell und Favoriten | Breadcrumb, Volumenauswahl und Schnellfilter |
| Dateiliste | Name, Typ, Größe und POSIX-Rechte aus einmalig geladenen Metadaten; Verzeichnisse zuerst | Konfigurierbare Spalten und sehr große Verzeichnisse weiter profilieren |
| Auswahl | URL-basierter Cursor und Mehrfachmarkierung pro Panel; Markierungen haben Vorrang | Bereichsauswahl und erweiterte Auswahlmuster |
| Dateioperationen | Anzeigen, extern bearbeiten, kopieren, verschieben, umbenennen, Ordner anlegen und in den Papierkorb bewegen | Konfliktdialog, Fortschritt, Abbruch, Wiederaufnahme und vollständige Teilfehler-UI |
| Sicherheit | Kein endgültiger Lösch-Fallback; keine stillen Überschreibungen; Selbstkopie eines Ordners wird verhindert | Zentraler `FileOperationCoordinator` und breitere Integrationssuite |
| Favoriten | Hinzufügen, filtern, ändern und entfernen; Speicherung in `UserDefaults` | Import/Export und bessere Fehlerdarstellung |
| Kommandozeile | Als experimentelles Power-User-Feature sichtbar gekennzeichnet | Arbeitsverzeichnis, Exit-Code, getrennte Ausgabe, Abbruch und nicht blockierende Ausführung |
| Tests | Acht Unit-/Integrationstests für Panelzustand, Sortierung, Laden und Sicherheitsfälle | Ausbau pro Kernoperation und gezielte Fokus-/Shortcut-UI-Tests |

## Tastaturbelegung

Die aktuelle F1/F2-Belegung stammt noch aus dem Prototyp und wird in Stufe 3 bewusst neu bewertet.

| Taste | Aktion |
| --- | --- |
| `F1` / `F2` | Linkes / rechtes Panel aktivieren |
| `F3` | Datei mit der Standard-App anzeigen |
| `F4` | Datei im konfigurierten Editor öffnen |
| `F5` | Markierung oder Cursorziel in das andere Panel kopieren |
| `F6` | Markierung oder Cursorziel in das andere Panel verschieben |
| `Shift` + `F6` | Ausgewähltes Element umbenennen |
| `F7` | Ordner anlegen |
| `F8` | Nach Bestätigung in den Papierkorb bewegen |
| `F10` | App beenden |
| `Tab` | Aktives Panel wechseln |
| `↑` / `↓` | Cursor bewegen |
| `Enter` | Verzeichnis öffnen oder Datei anzeigen |
| `Leertaste` | Markierung umschalten und Cursor weiterbewegen |
| `Command` + Klick | Markierung umschalten |
| `Control` + `Page Up` / `Page Down` | Übergeordnetes / ausgewähltes Unterverzeichnis öffnen |
| `Option` + `F1` / `F2` | Favoriten des linken / rechten Panels öffnen |
| `Command` + `G` | Pfad direkt öffnen |
| `Command` + `/` | Statusleiste ein- oder ausblenden |

Je nach macOS-Tastatureinstellung muss zusätzlich `fn` gedrückt werden.

## Architektur

```text
DumbCommanderApp
└── CommanderState
    ├── leftPanel: PanelState
    ├── rightPanel: PanelState
    └── activePanel

FileListView ── Intents ──> PanelState
      │
      └── async ──> FileSystemServing <── LocalFileSystemService (actor)
```

| Datei | Verantwortung |
| --- | --- |
| `DumbCommander/CommanderState.swift` | Aktives Panel, panelübergreifender UI-Zustand und je ein `PanelState` pro Seite |
| `DumbCommander/FileItem.swift` | Stabile Identität, vorab geladene Metadaten und deterministische Sortierung |
| `DumbCommander/FileSystemService.swift` | Testbares Protokoll und reale asynchrone Dateisystemimplementierung |
| `DumbCommander/ContentView.swift` | Hauptlayout, Dialoge und Weitergabe von Benutzeraktionen |
| `DumbCommander/FileListView.swift` | Darstellung und Eingaben eines Panels ohne eigenen Dateisystemzustand |
| `DumbCommander/KeyEventHandlingView.swift` | Brücke zu lokalen AppKit-Tastaturereignissen |
| `DumbCommander/SettingsView.swift` | Einstellungen und Favoritenpflege |

Lange Dateioperationen laufen nicht auf dem Main Actor. Ein eigener Coordinator für Planung, Konflikte, Fortschritt und Abbruch ist Bestandteil von Stufe 2.

## Plattform und Distribution

- ausschließlich macOS 14 oder neuer;
- SwiftUI mit gezielten AppKit-Brücken;
- Swift 5 Language Mode;
- keine externen Abhängigkeiten;
- direkte, signierte und später notarisierte Distribution außerhalb des Mac App Store;
- App Sandbox deaktiviert, Hardened Runtime aktiviert;
- Full Disk Access ist keine normale Voraussetzung.

Geschützte macOS-Bereiche und POSIX-Berechtigungen gelten weiterhin. Fehler werden nicht durch aggressivere Folgeoperationen umgangen.

## Bauen und testen

In Xcode `DumbCommander.xcodeproj` öffnen, Scheme `DumbCommander` und Ziel „My Mac“ wählen.

Reproduzierbare Kompilierungsprüfung:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
  -project DumbCommander.xcodeproj \
  -scheme DumbCommander \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/DumbCommander-DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Unit- und Integrationstests:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
  -project DumbCommander.xcodeproj \
  -scheme DumbCommander \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/DumbCommander-TestDerivedData \
  test
```

Am 31. August 2026 waren der unsignierte Debug-Build, ein signierter Debug-Build, alle acht neuen Unit-/Integrationstests und zwei gezielte UI-Tests erfolgreich. Die schreibenden Tests erzeugen jeweils ein neues temporäres Verzeichnis und berühren keine echten Benutzerdaten.

## Nächste Priorität

[Stufe 2 der Roadmap](ROADMAP.md#stufe-2--sichere-dateioperationen) führt einen `FileOperationCoordinator` ein. Er plant Quelle und Ziel, modelliert Konflikte, liefert strukturierte Teilergebnisse und macht lange Operationen fortschrittsfähig sowie abbrechbar. Bis diese Stufe abgeschlossen ist, bleibt DumbCommander ein Entwicklungsprototyp.

## Mitwirken

Die verbindlichen Regeln stehen in [AGENTS.md](AGENTS.md). Die ältere Datei `DumbCommander/README.md` wird in das App-Bundle kopiert und ist nur Prototyp-Altbestand; maßgeblich sind diese Root-README, die Roadmap und die ADRs.
