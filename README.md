# DumbCommander

DumbCommander ist ein nativer, tastaturorientierter Zwei-Panel-Dateimanager für macOS. Das Interaktionsvorbild ist [Total Commander](https://www.ghisler.com/deutsch.htm): Quelle und Ziel bleiben gleichzeitig sichtbar, das aktive Panel ist eindeutig und häufige Dateioperationen sind ohne Maus erreichbar. Die App ist kein pixelgenauer Klon und steht in keiner Verbindung zu Ghisler Software.

> **Projektstatus: Version 0.1 für lokale Nutzung.** Die Stufen 0 bis 3 sind umgesetzt: Plattformbasis, getrenntes Panelmodell, sichere Dateioperationen und ein vollständig tastaturbedienbarer Commander-Kern. Release-Härtung, Power-User-Funktionen und Notarisierung stehen noch aus.

## Umsetzungsstand

Bis zum 1. September 2026 wurden die ersten vier Stufen der [Roadmap](ROADMAP.md) abgeschlossen:

- Stufe 0: macOS-only-Konfiguration, einheitliches Deployment Target, sichere Papierkorbsemantik, dokumentiertes Distributionsmodell, experimentell gekennzeichnete Shell und temporäre Testumgebung.
- Stufe 1: unabhängige Zustände beider Panels, stabile URL-basierte Auswahl und Markierungen, vorab geladene Dateimetadaten, asynchroner und testbarer Dateisystemdienst sowie Schutz vor veralteten Ladeergebnissen.
- Stufe 2: vorab geplante Dateioperationen, explizite Konfliktentscheidungen, Fortschritt, Abbruch, strukturierte Teilergebnisse und sichere Behandlung von Symlinks sowie Volume-Wechseln.
- Stufe 3: editierbare Pfadleisten, Verlauf, Volumes, Sitzungswiederherstellung, Schnellfilter, zentrale Befehlsregistrierung, stabile Fokusführung und interner Viewer.

Die Arbeitsnachweise stehen unter [Stufen 0 und 1](docs/progress/2026-08-31-stufen-0-und-1.md), [Stufe 2](docs/progress/2026-08-31-stufe-2.md) und [Stufe 3](docs/progress/2026-09-01-stufe-3.md). Architekturentscheidungen dokumentieren [ADR 0001](docs/decisions/0001-distribution-and-file-access.md), [ADR 0002](docs/decisions/0002-konflikte-und-dateioperationen.md), [ADR 0003](docs/decisions/0003-command-navigation-viewer.md) und [ADR 0004](docs/decisions/0004-symbolische-links-beim-oeffnen.md).

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
| Zwei Panels | Unabhängige Verzeichnisse, Cursor, Markierungen, Sortierung und Verlauf; aktives Panel ist Quelle; letzte Verzeichnisse und aktives Panel werden wiederhergestellt | Tabs sind Stufe 4 |
| Navigation | Editierbare Pfadleiste, `.`, `..`, Verlauf, Home, Wurzel, eingebundene Volumes, Favoriten und direkter Pfad; Enter und Doppelklick öffnen Verzeichnisse und folgen Verzeichnis-Links | Erweiterte virtuelle Orte sind nicht Bestandteil von 0.1 |
| Dateiliste | Name, Typ, Größe und POSIX-Rechte aus einmalig geladenen Metadaten; Verzeichnisse zuerst | Konfigurierbare Spalten und sehr große Verzeichnisse weiter profilieren |
| Auswahl | URL-basierter Cursor und Mehrfachmarkierung pro Panel; Cursor und Markierung besitzen zusätzliche Symbole; Schnellfilter operiert nur auf sichtbaren Markierungen | Bereichsauswahl und erweiterte Auswahlmuster |
| Dateioperationen | Kopieren, Verschieben, Umbenennen, Ordneranlage und Papierkorb laufen geplant, asynchron, fortschrittsfähig und abbrechbar | Keine Wiederaufnahme nach App-Neustart und noch keine Operationswarteschlange |
| Konflikte | Ersetzen, Überspringen, beide behalten, Verzeichnisse zusammenführen oder abbrechen; passende Entscheidung „für alle“ | Zusammenführen überspringt verschachtelte Zielkonflikte sicher und weist sie einzeln im Bericht aus |
| Sicherheit | Kein endgültiger Lösch-Fallback oder stilles Überschreiben; temporäres Ersetzen; Selbstkopie verhindert; Dateioperationen dereferenzieren Symlinks nie | Tests mit echten externen Volumes bleiben Teil der Release-Härtung |
| Favoriten | Hinzufügen, filtern, ändern und entfernen; Speicherung in `UserDefaults` | Import/Export und bessere Fehlerdarstellung |
| Viewer | Interner, speicherbegrenzter Text- und Hexviewer, Bildvorschau und Metadatenansicht; Enter und Doppelklick öffnen Dateien, Datei-Links ihr aufgelöstes Ziel | Suche im Viewer und weitere Binärdarstellungen |
| Editor | Systemstandard oder konfigurierbare App; Datei-Links öffnen ihr Ziel; fehlende oder ungültige Editoren werden verständlich gemeldet | Editorprofile und dateitypabhängige Zuordnung |
| Kommandozeile | Als experimentelles Power-User-Feature sichtbar gekennzeichnet | Arbeitsverzeichnis, Exit-Code, getrennte Ausgabe, Abbruch und nicht blockierende Ausführung |
| Tests | 35 Unit-/Integrationstests sowie acht gezielte UI-Regressionstests | Breitere VoiceOver-, Kontrast- und Performance-Prüfungen in Stufe 5 |

## Tastatur- und Mausbedienung

F1/F2 bleiben bewusst eine Abweichung vom Total-Commander-Vorbild: Sie aktivieren direkt das linke beziehungsweise rechte Panel. Das ist auf dem Mac ohne separate Laufwerksbuchstaben ein schneller, eindeutiger Panelwechsel; `Tab` bleibt der normale Wechsel zwischen beiden Seiten.

| Taste | Aktion |
| --- | --- |
| `F1` / `F2` | Linkes / rechtes Panel aktivieren |
| `F3` | Datei im internen Viewer anzeigen |
| `F4` | Datei im konfigurierten Editor öffnen |
| `F5` | Markierung oder Cursorziel in das andere Panel kopieren |
| `F6` | Markierung oder Cursorziel in das andere Panel verschieben |
| `Shift` + `F6` | Ausgewähltes Element umbenennen |
| `F7` | Ordner anlegen |
| `F8` | Nach Bestätigung in den Papierkorb bewegen |
| `F10` | App beenden |
| `Tab` | Aktives Panel wechseln |
| `↑` / `↓` | Cursor bewegen |
| `Enter` | Verzeichnis öffnen oder Datei anzeigen; symbolische Links führen zum Ziel |
| Doppelklick | Verzeichnis öffnen oder Datei im internen Viewer anzeigen |
| `Leertaste` | Markierung umschalten und Cursor weiterbewegen |
| `Command` + Klick | Markierung umschalten |
| `Control` + `Page Up` / `Page Down` | Übergeordnetes / ausgewähltes Unterverzeichnis öffnen |
| `Option` + `F1` / `F2` | Favoriten des linken / rechten Panels öffnen |
| `Command` + `G` | Pfad direkt öffnen |
| `Command` + `[` / `]` | Im Verlauf zurück / vorwärts |
| `Command` + `Shift` + `H` | Benutzerordner öffnen |
| `Command` + `Option` + `H` | Wurzelverzeichnis öffnen |
| `Command` + `F` | Schnellfilter des aktiven Panels fokussieren |
| `Command` + `R` | Beide Panels neu laden |
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

ContentView ── Requests ──> FileOperationViewModel
                              │
                              └── FileOperationCoordinator
                                      ├── Plan und Konflikte
                                      └── FileSystemServing

CommandRegistry ──> Menü, Toolbar, Funktionsleiste und Tastaturereignisse
CommanderSessionStore ──> letzte Panelpfade und aktives Panel
FileViewerLoader (actor) ──> begrenzte Text-, Hex-, Bild- und Metadatenvorschau
```

| Datei | Verantwortung |
| --- | --- |
| `DumbCommander/CommanderState.swift` | Aktives Panel, panelübergreifender UI-Zustand und je ein `PanelState` pro Seite |
| `DumbCommander/FileItem.swift` | Stabile Identität, vorab geladene Metadaten und deterministische Sortierung |
| `DumbCommander/FileSystemService.swift` | Testbares Protokoll und reale asynchrone Dateisystemimplementierung |
| `DumbCommander/FileOperationCoordinator.swift` | Planung, Konfliktmodell, Fortschritt, Abbruch und strukturierte Operationsberichte |
| `DumbCommander/CommandRegistry.swift` | Gemeinsame Definition von Befehlen, Labels und Shortcuts |
| `DumbCommander/SessionStore.swift` | Persistenz der letzten Panelverzeichnisse und des aktiven Panels |
| `DumbCommander/FileViewer.swift` | Asynchroner, speicherbegrenzter interner Viewer |
| `DumbCommander/ContentView.swift` | Hauptlayout, Konflikt-/Fortschrittsoberfläche und Weitergabe von Benutzeraktionen |
| `DumbCommander/FileListView.swift` | Darstellung und Eingaben eines Panels ohne eigenen Dateisystemzustand |
| `DumbCommander/KeyEventHandlingView.swift` | Brücke zu lokalen AppKit-Tastaturereignissen |
| `DumbCommander/SettingsView.swift` | Einstellungen und Favoritenpflege |

Lange Dateioperationen laufen nicht auf dem Main Actor. Reguläre Dateien werden blockweise kopiert, damit Fortschritt und Abbruch auch innerhalb großer Einzeldateien wirksam sind.

## Plattform und Distribution

- ausschließlich macOS 14 oder neuer;
- SwiftUI mit gezielten AppKit-Brücken;
- Swift 5 Language Mode;
- keine externen Abhängigkeiten;
- direkte, signierte und später notarisierte Distribution außerhalb des Mac App Store;
- App Sandbox deaktiviert, Hardened Runtime aktiviert;
- Full Disk Access ist keine normale Voraussetzung.

Geschützte macOS-Bereiche und POSIX-Berechtigungen gelten weiterhin. Fehler werden nicht durch aggressivere Folgeoperationen umgangen.
Security-Scoped Bookmarks sind im beschlossenen, nicht sandboxed Distributionsmodell nicht erforderlich. Die Sitzung speichert ausschließlich Pfade; nicht mehr verfügbare Verzeichnisse werden beim Start verworfen, Verzeichnis-Links kontrolliert auf ihr Ziel aufgelöst.

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

Am 1. September 2026 waren der unsignierte Debug-Build, der signierte Test-Build, alle 35 Unit-/Integrationstests und acht gezielte UI-Regressionstests erfolgreich. Die schreibenden Tests erzeugen jeweils ein neues temporäres Verzeichnis und berühren keine echten Benutzerdaten oder `UserDefaults.standard`.

## Nächste Priorität

[Stufe 4 der Roadmap](ROADMAP.md#stufe-4--power-user-funktionen) ergänzt Tabs, Suche, Verzeichnisvergleich, Synchronisation und Mehrfachumbenennung. Stufe 5 übernimmt anschließend die Release-Härtung.

## Mitwirken

Die verbindlichen Regeln stehen in [AGENTS.md](AGENTS.md). Die ältere Datei `DumbCommander/README.md` wird in das App-Bundle kopiert und ist nur Prototyp-Altbestand; maßgeblich sind diese Root-README, die Roadmap und die ADRs.
