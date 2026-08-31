# DumbCommander

DumbCommander ist der Prototyp eines tastaturorientierten Zwei-Panel-Dateimanagers für macOS. Das langfristige Vorbild ist der Arbeitsfluss von [Total Commander](https://www.ghisler.com/deutsch.htm): Quelle und Ziel bleiben gleichzeitig sichtbar, die aktive Seite ist eindeutig und häufige Dateioperationen sind ohne Maus erreichbar.

> **Projektstatus: frühe, nicht produktionsreife Entwicklung.** Der aktuelle Stand baut, enthält aber bekannte Fehler in Zustandsmodell, Dateizugriff und Löschverhalten. Für wichtige oder nicht gesicherte Daten sollte die App noch nicht verwendet werden.

DumbCommander ist ein eigenständiges Projekt und steht in keiner Verbindung zu Ghisler Software oder Total Commander.

## Zielbild

Die App soll sich wie ein nativer macOS-Commander anfühlen, ohne das bewährte Zwei-Panel-Modell zu verwässern:

- zwei gleichwertige Panels mit eindeutigem aktivem Quell- und inaktivem Zielpanel;
- vollständige Tastaturbedienung mit konsistenten Commander-Shortcuts;
- sichere, nachvollziehbare Dateioperationen mit Konfliktbehandlung, Fortschritt und Abbruch;
- schnelle Navigation über Pfad, Verlauf, Favoriten, Filter und Tabs;
- Viewer, Suche, Mehrfachumbenennung, Vergleich und Verzeichnissynchronisation;
- später optional Archive und entfernte Dateisysteme.

Total Commander bietet weit mehr als zwei Listen, unter anderem Viewer, Suche, Verzeichnisvergleich und -synchronisation, Mehrfachumbenennung, Tabs, Archive und FTP. Diese Funktionen sind Referenz für die Produkt-Roadmap, aber **nicht** Teil des aktuellen Funktionsumfangs. Siehe die offizielle [Funktionsübersicht](https://www.ghisler.com/featurel.htm).

## Aktueller Funktionsumfang

| Bereich | Vorhanden | Einschränkung |
| --- | --- | --- |
| Zwei Panels | Beide starten im Benutzerverzeichnis; das aktive Panel ist markiert | Auswahl und Markierungen sind noch nicht vollständig pro Panel modelliert |
| Navigation | `.`, `..`, Pfeiltasten, Enter, Tab und direkte Pfadeingabe | Kein Verlauf, keine Tabs, kein Breadcrumb und keine Volumenauswahl |
| Dateiliste | Name, Typ, Größe, POSIX-Rechte; Sortierung nach Name, Typ oder Größe | Metadaten werden synchron geladen; große Verzeichnisse können die UI blockieren |
| Auswahl | Cursorzeile, Markieren mit Leertaste oder Command-Klick | Der globale `selectedFile`-Zustand kann nach einem Panelwechsel veraltet sein |
| Dateioperationen | Anzeigen, extern bearbeiten, kopieren, verschieben, neuen Ordner anlegen, löschen | Keine Fortschrittsanzeige, kein Abbruch, keine Konfliktauflösung und keine Transaktionssicherheit |
| Favoriten | Standardmäßig Benutzerverzeichnis und `/`; hinzufügen, filtern, ändern und entfernen | Als JSON in `UserDefaults` gespeichert; keine Security-Scoped Bookmarks |
| Einstellungen | Editor, versteckte Dateien, Löschbestätigung, Status-/F-Leiste, Hell/Dunkel | Einstellungen und Persistenz sind direkt an SwiftUI-Views gekoppelt |
| Kommandozeile | Führt Eingaben über `/bin/bash -c` aus und zeigt die Ausgabe | Blockiert während der Ausführung, kennt das aktive Verzeichnis nicht und zeigt keinen Exit-Code |
| Tests | Zwei einfache UI-Szenarien sowie Xcode-Templates | Keine belastbare Unit-, Integrations- oder Dateisicherheitsabdeckung |

Umbenennen ist im Quellcode begonnen, aber derzeit nicht nutzbar: Es gibt weder einen erreichbaren Befehl noch eine eingebundene Rename-Oberfläche.

## Tastaturbelegung im aktuellen Prototyp

Die Belegung ist noch nicht endgültig. Insbesondere F1 und F2 weichen aktuell vom Total-Commander-Verhalten ab.

| Taste | Aktion |
| --- | --- |
| `F1` / `F2` | Linkes / rechtes Panel aktivieren |
| `F3` | Ausgewählte Datei mit der Standard-App anzeigen |
| `F4` | Ausgewählte Datei im konfigurierten Editor öffnen |
| `F5` | Auswahl in das andere Panel kopieren |
| `F6` | Auswahl in das andere Panel verschieben |
| `F7` | Ordner mit automatisch erzeugtem Namen anlegen |
| `F8` | Auswahl löschen beziehungsweise in den Papierkorb bewegen |
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

Auf Mac-Tastaturen muss je nach Systemeinstellung zusätzlich `fn` gedrückt werden, damit F-Tasten als Funktionstasten ankommen.

## Architektur heute

Das Projekt ist eine SwiftUI-App mit punktueller AppKit-Integration und ohne externe Abhängigkeiten.

```text
DumbCommanderApp
├── AppState                 globaler, gemeinsam genutzter UI-Zustand
├── ContentView              Layout, Toolbar, Dialoge und Dateioperationen
│   ├── FileListView (links) Navigation, Liste, Sortierung und Markierungen
│   └── FileListView (rechts)
├── KeyEventHandlingView     lokaler NSEvent-Monitor als NSViewRepresentable
└── SettingsView             AppStorage-Einstellungen und Favoritenverwaltung
```

| Datei | Verantwortung |
| --- | --- |
| `DumbCommander/DumbCommanderApp.swift` | App-Einstieg, Menübefehle, Appearance und Standardfavoriten |
| `DumbCommander/ContentView.swift` | Gemeinsamer Zustand, Hauptlayout, F-Tasten, Dialoge, Shell und mutierende Dateioperationen |
| `DumbCommander/FileListView.swift` | Panel-UI, Verzeichnisinhalt, Sortierung, Auswahl, Markierung, Favoriten-Popover und Dateiattribute |
| `DumbCommander/KeyEventHandlingView.swift` | Brücke zu lokalen AppKit-Key-Events |
| `DumbCommander/SettingsView.swift` | Einstellungen und Favoritenpflege |
| `DumbCommanderTests/` | Derzeit nur unveränderte Unit-Test-Templates |
| `DumbCommanderUITests/` | Launch-Test sowie Panelwechsel- und Shell-UI-Test |

Die Struktur ist für einen Prototyp nachvollziehbar, skaliert aber nicht sicher: UI, Dateisystemzugriff und Operationslogik sind eng gekoppelt; `ContentView.swift` und `FileListView.swift` tragen den Großteil der Verantwortung.

## Bauen und starten

Voraussetzungen:

- macOS 14 oder neuer;
- vollständige Xcode-Installation (das Projekt wurde ursprünglich mit Xcode 15.4 angelegt);
- Scheme `DumbCommander`.

In Xcode: `DumbCommander.xcodeproj` öffnen, das Scheme `DumbCommander` und als Ziel „My Mac“ auswählen, dann mit `Command` + `R` starten.

Kommandozeile:

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

Der Debug-Build wurde am 31. August 2026 mit Xcode 26.6 erfolgreich geprüft. Das Deaktivieren der Codesignatur dient nur der lokalen Build-Prüfung und validiert **nicht** das reale Sandbox- und Berechtigungsverhalten.

Tests können lokal in Xcode mit `Command` + `U` gestartet werden. Derzeit ist ein grüner Testlauf jedoch kein ausreichender Qualitätsnachweis, weil die Unit-Tests keine Produktlogik prüfen und die UI-Abdeckung minimal ist.

## Bekannte kritische Baustellen

### 1. Löschen ist nicht sicher genug

`handleDelete()` versucht zuerst, ein Element in den Papierkorb zu verschieben, fällt bei **jedem** Fehler aber auf `removeItem` zurück. Ein harmloser Papierkorbfehler kann dadurch zu einer endgültigen Löschung führen. Dieser Fallback muss entfernt werden, bevor die App mit realen Daten eingesetzt wird.

### 2. Panelzustand ist nicht sauber getrennt

Beide Panels teilen sich `selectedFile` und `markedFiles` in `AppState`, während Cursor und Markierungsindizes lokal in jedem `FileListView` liegen. Nach einem Panelwechsel kann eine Operation deshalb mit einer veralteten Auswahl arbeiten. Quelle, Ziel, Cursor und Markierungen müssen explizit pro Panel modelliert werden.

### 3. Sandbox und Dateizugriff widersprechen dem Produktziel

Das Target aktiviert App Sandbox und erlaubt benutzergewählte Dateien nur lesend, während die App beliebige Pfade direkt öffnet und dort schreiben möchte. Persistente Security-Scoped Bookmarks fehlen. Vor weiterer Funktionsentwicklung muss entschieden werden:

- Sandbox-App mit explizit gewählten Wurzeln und persistierten Security-Scoped Bookmarks; oder
- außerhalb des Mac App Store signierte und notarisierte App mit bewusst breiterem Dateisystemzugriff.

### 4. Dateioperationen blockieren die Oberfläche

Verzeichnislesen, Metadaten, Kopieren, Verschieben, Löschen und Shell-Ausführung laufen synchron aus der UI heraus. Große Bäume, langsame Volumes oder Netzwerkpfade frieren die App ein. Ein asynchroner Operationsdienst mit Fortschritt, Abbruch und strukturierten Ergebnissen ist erforderlich.

### 5. Konflikte und Teilfehler sind unzureichend behandelt

Existierende Ziele werden nur übersprungen. Es gibt keine Auswahl zwischen Überschreiben, Überspringen, Umbenennen oder „für alle“, keine Vorabprüfung und keine Wiederaufnahme. Nach Teilfehlern ist der tatsächliche Zustand nur über eine Textmeldung erkennbar.

### 6. Projektkonfiguration und Tests sind inkonsistent

Obwohl der Code AppKit importiert und nur auf macOS lauffähig ist, nennt das Xcode-Projekt zusätzlich iOS und iOS Simulator als unterstützte Plattformen. Die Deployment Targets von App und Tests unterscheiden sich. Es fehlen Unit-Tests für Sortierung, Panelzustand und Operationsplanung sowie Integrationsprüfungen in temporären Verzeichnissen.

### 7. Kommandozeile braucht ein Sicherheits- und UX-Konzept

Die Kommandozeile führt absichtlich beliebige Shell-Befehle aus, jedoch synchron, ohne aktives Panel als Arbeitsverzeichnis, ohne Exit-Status, Abbruch oder Verlauf. In einer Sandbox-Auslieferung ist sie zudem nur eingeschränkt sinnvoll. Sie sollte als bewusstes Power-User-Feature isoliert und konfigurierbar sein.

## Empfohlene Roadmap

Der ausführliche, in sechs Stufen gegliederte Umsetzungsplan steht in [`ROADMAP.md`](ROADMAP.md). Die folgende Übersicht fasst die fachliche Reihenfolge zusammen.

### Phase 0 – Stabilisieren und Daten schützen

1. Nur macOS als Ziel konfigurieren und die Sandbox-/Distributionsentscheidung dokumentieren.
2. `PanelState` pro Seite einführen: Verzeichnis, Cursor, Auswahl, Markierungen, Sortierung und Verlauf.
3. Dateisystemzugriff hinter ein testbares Protokoll verschieben; Operationen über einen `FileOperationCoordinator` planen und ausführen.
4. Endgültiges Löschen als automatischen Fallback entfernen; Papierkorbfehler sichtbar machen.
5. Konfliktdialog, Fortschritt, Abbruch und vollständige Operationsberichte implementieren.
6. Unit- und Integrationssuite mit ausschließlich temporären Testverzeichnissen aufbauen.

### Phase 1 – Solider Commander-Kern

1. Befehle und Shortcuts zentral definieren; Menü, Funktionsleiste und Key-Monitor daraus ableiten.
2. Umbenennen fertigstellen und F6-/`Shift`+F6-Verhalten bewusst festlegen.
3. Pfadleiste, Verlauf, Volumes, Schnellfilter und zuverlässige Fokusführung ergänzen.
4. Internen Viewer für Text, Hex, Bilder und Metadaten aufbauen; externen Editor weiter unterstützen.
5. Operationen in Hintergrund-Tasks verschieben und UI-Updates auf dem Main Actor halten.

### Phase 2 – Total-Commander-typische Werkzeuge

1. Panel-Tabs und wiederherstellbare Sitzungen.
2. Erweiterte Suche und Ergebnislisten.
3. Dateivergleich und Verzeichnissynchronisation mit Vorschau.
4. Mehrfachumbenennung mit Live-Vorschau und Undo-Protokoll.
5. Archive wie Verzeichnisse behandeln, zunächst ZIP und TAR.
6. Drag & Drop, Kontextmenüs und konfigurierbare Spalten.

### Phase 3 – Erweiterungen

Remote-Dateisysteme, Hintergrundwarteschlangen, Checksummen und ein Erweiterungsmodell sind sinnvoll, aber erst nach einem stabilen lokalen Kern.

## Definition für einen ersten belastbaren Meilenstein

Ein Release `0.1` sollte erst markiert werden, wenn:

- Quelle und Ziel jeder Operation eindeutig aus getrenntem Panelzustand hervorgehen;
- Kopieren, Verschieben, Umbenennen, Ordnererstellung und Papierkorbverhalten automatisiert in temporären Verzeichnissen geprüft sind;
- keine Operation stillschweigend endgültig löscht oder überschreibt;
- Dateizugriff nach Neustart entsprechend dem gewählten Sandbox-Modell funktioniert;
- lange Operationen Fortschritt und Abbruch anbieten und die UI bedienbar bleibt;
- Build und Tests reproduzierbar auf einem sauberen Checkout laufen.

## Mitwirken

Verbindliche Arbeitsregeln für Menschen und Coding-Agents stehen in [`AGENTS.md`](AGENTS.md). Neue Funktionen sollten die kritischen Punkte nicht weiter in SwiftUI-Views einbauen, sondern das dort beschriebene Zielmodell schrittweise herstellen.

Die ältere Datei `DumbCommander/README.md` ist Bestandteil des App-Targets und beschreibt Teile des bisherigen Prototyps. Für Projektstatus, Zielbild und Roadmap ist diese README im Repository-Wurzelverzeichnis maßgeblich.
