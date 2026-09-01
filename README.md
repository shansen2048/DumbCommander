# DumbCommander

DumbCommander ist ein nativer, tastaturorientierter Zwei-Panel-Dateimanager für macOS. Das Interaktionsvorbild ist [Total Commander](https://www.ghisler.com/deutsch.htm): Quelle und Ziel bleiben gleichzeitig sichtbar, das aktive Panel ist eindeutig und häufige Dateioperationen sind ohne Maus erreichbar. Die App ist kein pixelgenauer Klon und steht in keiner Verbindung zu Ghisler Software.

> **Projektstatus: Version 0.2.0 „Power Tools“ für lokale Nutzung.** Die Stufen 0 bis 4 sind umgesetzt: Auf dem sicheren Zwei-Panel-Kern bauen Tabs, Suche, Vergleich, Archive und weitere Power-User-Werkzeuge auf. Release-Härtung und Notarisierung stehen noch aus.

## Umsetzungsstand

Bis zum 1. September 2026 wurden die Stufen 0 bis 4 der [Roadmap](ROADMAP.md) abgeschlossen:

- Stufe 0: macOS-only-Konfiguration, einheitliches Deployment Target, sichere Papierkorbsemantik, dokumentiertes Distributionsmodell, experimentell gekennzeichnete Shell und temporäre Testumgebung.
- Stufe 1: unabhängige Zustände beider Panels, stabile URL-basierte Auswahl und Markierungen, vorab geladene Dateimetadaten, asynchroner und testbarer Dateisystemdienst sowie Schutz vor veralteten Ladeergebnissen.
- Stufe 2: vorab geplante Dateioperationen, explizite Konfliktentscheidungen, Fortschritt, Abbruch, strukturierte Teilergebnisse und sichere Behandlung von Symlinks sowie Volume-Wechseln.
- Stufe 3: editierbare Pfadleisten, Verlauf, Volumes, Sitzungswiederherstellung, Schnellfilter, zentrale Befehlsregistrierung, stabile Fokusführung und interner Viewer.
- Stufe 4: Panel-Tabs, rekursive Datei- und Inhaltssuche mit virtuellen Ergebnis-Panels, Vergleich und Synchronisationsvorschau, Mehrfachumbenennung mit Undo, ZIP/TAR-Werkzeuge, SHA-256, Inhaltsvergleich, Drag-and-drop, Operationswarteschlange und konfigurierbare Befehle.

Die Arbeitsnachweise stehen unter [Stufen 0 und 1](docs/progress/2026-08-31-stufen-0-und-1.md), [Stufe 2](docs/progress/2026-08-31-stufe-2.md), [Stufe 3](docs/progress/2026-09-01-stufe-3.md) und [Stufe 4](docs/progress/2026-09-01-stufe-4.md). Architekturentscheidungen dokumentieren [ADR 0001](docs/decisions/0001-distribution-and-file-access.md), [ADR 0002](docs/decisions/0002-konflikte-und-dateioperationen.md), [ADR 0003](docs/decisions/0003-command-navigation-viewer.md), [ADR 0004](docs/decisions/0004-symbolische-links-beim-oeffnen.md) und [ADR 0005](docs/decisions/0005-power-tools-und-externe-prozesse.md).

## Zielbild

DumbCommander soll sich wie ein nativer macOS-Commander anfühlen:

- zwei gleichwertige Panels mit eindeutigem aktiven Quell- und inaktivem Zielpanel;
- vollständige Tastaturbedienung und stabile Fokusführung;
- sichere, nachvollziehbare Dateioperationen ohne stilles Überschreiben oder endgültiges Löschen;
- reaktionsfähige Navigation auch in großen Verzeichnissen;
- Viewer, Suche, Mehrfachumbenennung, Vergleich, Synchronisation, Tabs und Archive als integrierte Commander-Werkzeuge.

Datenschutz und Vorhersagbarkeit haben Vorrang vor Funktionsumfang.

## Aktueller Funktionsumfang

| Bereich | Stand | Noch offen |
| --- | --- | --- |
| Zwei Panels | Unabhängige Verzeichnisse, Cursor, Markierungen, Sortierung, Verlauf und beliebig viele Tabs; aktives Panel ist Quelle | Beim Neustart werden derzeit nur die jeweils aktiven Tabs wiederhergestellt |
| Navigation | Editierbare Pfadleiste, `.`, `..`, Verlauf, Home, Wurzel, Volumes, Favoriten und direkter Pfad; Enter und Doppelklick öffnen Verzeichnisse und folgen Verzeichnis-Links | Weitere virtuelle Orte außer Suchergebnissen sind offen |
| Dateiliste | Name sowie optional Typ, Größe und POSIX-Rechte aus einmalig geladenen Metadaten; Verzeichnisse zuerst | Sehr große Verzeichnisse weiter profilieren |
| Auswahl | URL-basierter Cursor und Mehrfachmarkierung pro Panel; Schnellfilter sowie gespeicherte Wildcard-Auswahlmuster | Bereichsauswahl mit Shift bleibt offen |
| Dateioperationen | Kopieren, Verschieben, Umbenennen, Ordneranlage und Papierkorb laufen geplant, asynchron, fortschrittsfähig, abbrechbar und nacheinander in einer Warteschlange | Keine Wiederaufnahme nach App-Neustart |
| Konflikte | Ersetzen, Überspringen, beide behalten, Verzeichnisse zusammenführen oder abbrechen; passende Entscheidung „für alle“ | Zusammenführen überspringt verschachtelte Zielkonflikte sicher und weist sie einzeln im Bericht aus |
| Sicherheit | Kein endgültiger Lösch-Fallback oder stilles Überschreiben; temporäres Ersetzen; Selbstkopie verhindert; Dateioperationen dereferenzieren Symlinks nie | Tests mit echten externen Volumes bleiben Teil der Release-Härtung |
| Favoriten | Hinzufügen, filtern, ändern und entfernen; Speicherung in `UserDefaults` | Import/Export und bessere Fehlerdarstellung |
| Dateien öffnen | Enter und Doppelklick öffnen Dateien mit der verknüpften macOS-Standard-App; sichtbare Mehrfachmarkierungen werden unterstützt und nach App gruppiert | Auswahl einer abweichenden App über „Öffnen mit“ |
| Viewer | F3 öffnet den internen, speicherbegrenzten Text- und Hexviewer, die Bildvorschau und Metadatenansicht | Suche im Viewer und weitere Binärdarstellungen |
| Editor | Systemstandard oder konfigurierbare App; Datei-Links öffnen ihr Ziel; fehlende oder ungültige Editoren werden verständlich gemeldet | Editorprofile und dateitypabhängige Zuordnung |
| Suche und Vergleich | Rekursive Namens-/Inhaltssuche, gespeicherte Suchmuster, virtuelle Ergebnis-Tabs, Verzeichnis- und bytegenauer Inhaltsvergleich, sichere Synchronisationsvorschau | Suche ist lokal und auf 10.000 Ergebnisse begrenzt |
| Mehrfachumbenennung | Live-Vorschau, Vorlagen, Suchen/Ersetzen, Zähler, Schreibweise und Rückgängig für die letzte Ausführung | Undo wird nicht über einen App-Neustart gespeichert |
| Archive und Prüfsummen | ZIP/TAR-Inhaltsbrowser, Packen/Entpacken mit Pfad- und Zielprüfung, SHA-256 erzeugen und prüfen | Archive erscheinen in einem Browserdialog, nicht als schreibbares Panel-Dateisystem |
| Power-User | Drag-and-drop, Hintergrundwarteschlange, eigene Commands mit `%P`/`%F` und ein-/ausblendbare Buttonleiste | Warteschlange wird nicht persistiert |
| Kommandozeile | Nicht blockierend, abbrechbar, mit Arbeitsverzeichnis, Exit-Code sowie getrennter Standard-/Fehlerausgabe; keine Shell-Auswertung | Bleibt bewusst experimentell |
| Tests | 43 Unit-/Integrationstests sowie elf gezielte UI-Regressionstests im Projekt | Breitere VoiceOver-, Kontrast- und Performance-Prüfungen in Stufe 5 |

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
| `Enter` | Verzeichnis öffnen oder Datei(en) mit der verknüpften App öffnen; symbolische Links führen zum Ziel |
| Doppelklick | Verzeichnis öffnen oder Datei(en) mit der verknüpften App öffnen |
| `Leertaste` | Markierung umschalten und Cursor weiterbewegen |
| `Command` + Klick | Markierung umschalten |
| `Control` + `Page Up` / `Page Down` | Übergeordnetes / ausgewähltes Unterverzeichnis öffnen |
| `Option` + `F1` / `F2` | Favoriten des linken / rechten Panels öffnen |
| `Command` + `G` | Pfad direkt öffnen |
| `Command` + `[` / `]` | Im Verlauf zurück / vorwärts |
| `Command` + `Shift` + `H` | Benutzerordner öffnen |
| `Command` + `Option` + `H` | Wurzelverzeichnis öffnen |
| `Command` + `F` | Schnellfilter des aktiven Panels fokussieren |
| `Command` + `Shift` + `F` | Rekursive Dateisuche öffnen |
| `Command` + `R` | Beide Panels neu laden |
| `Command` + `T` / `Command` + `W` | Tab im aktiven Panel anlegen / schließen |
| `Command` + `/` | Statusleiste ein- oder ausblenden |

Je nach macOS-Tastatureinstellung muss zusätzlich `fn` gedrückt werden.

## Architektur

```text
DumbCommanderApp
└── CommanderState
    ├── leftTabs: [PanelState]
    ├── rightTabs: [PanelState]
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
PowerTools ──> Suche, Vergleich, Umbenennung, SHA-256, Archive und Prozesse
```

| Datei | Verantwortung |
| --- | --- |
| `DumbCommander/CommanderState.swift` | Aktives Panel, Panel-Tabs, virtuelle Ergebnisse und je ein unabhängiger `PanelState` pro Tab |
| `DumbCommander/FileItem.swift` | Stabile Identität, vorab geladene Metadaten und deterministische Sortierung |
| `DumbCommander/FileSystemService.swift` | Testbares Protokoll und reale asynchrone Dateisystemimplementierung |
| `DumbCommander/FileOperationCoordinator.swift` | Planung, Konfliktmodell, Fortschritt, Abbruch und strukturierte Operationsberichte |
| `DumbCommander/CommandRegistry.swift` | Gemeinsame Definition von Befehlen, Labels und Shortcuts |
| `DumbCommander/SessionStore.swift` | Persistenz der letzten Panelverzeichnisse und des aktiven Panels |
| `DumbCommander/FileViewer.swift` | Asynchroner, speicherbegrenzter interner Viewer |
| `DumbCommander/PowerTools.swift` | Testbare Dienste für Suche, Vergleich, Mehrfachumbenennung, SHA-256, Archive und Prozesse |
| `DumbCommander/PowerToolsViews.swift` | Vorschau- und Ergebnisoberflächen der Power-User-Werkzeuge |
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

Dieser Build ist absichtlich unsigniert und dient ausschließlich der Prüfung. Für eine lokal startbare App `CODE_SIGNING_ALLOWED=NO` weglassen:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
  -project DumbCommander.xcodeproj \
  -scheme DumbCommander \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  build

open build/DerivedData/Build/Products/Debug/DumbCommander.app
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

Am 1. September 2026 waren der unsignierte Debug-Build, ein lokal startbarer Debug-Build, alle 43 Unit-/Integrationstests und der neue gezielte UI-Test für Tabs und Suche erfolgreich. Die bereits vorhandenen zehn UI-Regressionstests bleiben Teil der Suite. Die schreibenden Tests erzeugen jeweils ein neues temporäres Verzeichnis und berühren keine echten Benutzerdaten oder `UserDefaults.standard`.

## Nächste Priorität

[Stufe 5 der Roadmap](ROADMAP.md#stufe-5--release-härtung) übernimmt Performance, Barrierefreiheit, Packaging, Developer-ID-Signierung und Notarisierung.

## Mitwirken

Die verbindlichen Regeln stehen in [AGENTS.md](AGENTS.md). Die ältere Datei `DumbCommander/README.md` wird in das App-Bundle kopiert und ist nur Prototyp-Altbestand; maßgeblich sind diese Root-README, die Roadmap und die ADRs.
