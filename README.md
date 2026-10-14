# DumbCommander

DumbCommander ist ein nativer, tastaturorientierter Zwei-Panel-Dateimanager für macOS. Das Interaktionsvorbild ist [Total Commander](https://www.ghisler.com/deutsch.htm): Quelle und Ziel bleiben gleichzeitig sichtbar, das aktive Panel ist eindeutig und häufige Dateioperationen sind ohne Maus erreichbar. Die App ist kein pixelgenauer Klon und steht in keiner Verbindung zu Ghisler Software.

> **Projektstatus: Version 0.2.0 „Power Tools“, in Absicherung.** Die Funktionen der Stufen 0 bis 4 sind weitgehend vorhanden. Die Sicherheitsbefunde der [Projektprüfung vom 9. Oktober 2026](docs/progress/2026-10-09-projektbewertung.md) zu Dateioperationen, Archiven und Mehrfachumbenennung sind korrigiert und durch Regressionstests abgesichert. Die vollständige Alltags-, Performance- und Distributionsabnahme steht noch aus.

**Update vom 14. Oktober 2026:** Vollständige Tab-Sitzungen, Shift-Bereichsauswahl und Suche im Viewer sind umgesetzt. Die Oberfläche wurde mit klaren Quelle-/Zielkennzeichnungen, kompakteren Dateizeilen und Funktionsleiste überarbeitet; ein neues [App-Icon](docs/design/app-icon.md) ist eingebunden. Tab-/Fokuskorrekturen und isolierte Tests begleiten die Änderungen. [Arbeitsnachweis und Grenzen](docs/progress/2026-10-14-bedienung-und-oberflaeche.md).

**Sicherheitskorrekturen vom 14. Oktober 2026:** Dateioperationen prüfen Identitäten und Metadaten und veröffentlichen neue Daten ohne Überschreiben konkurrierender Ziele. Archive werden kontrolliert in einem privaten Arbeitsbereich entpackt. Mehrfachumbenennung besitzt abbrechungsfeste Wiederherstellung und ein Wiederherstellungsjournal. Alle mutierenden Werkzeuge nehmen am gemeinsamen Beendigungs- und Berichtslebenszyklus teil. [Prüfnachweis und verbleibende Grenzen](docs/progress/2026-10-14-sicherheit-dateioperationen.md).

## Umsetzungsstand

Bis zum 1. September 2026 wurden die Funktionen der Stufen 0 bis 4 der [Roadmap](ROADMAP.md) implementiert und damals als abgeschlossen dokumentiert. Die aktuelle Prüfung unterscheidet diesen Implementierungsstand von der noch offenen vollständigen Abnahme:

- Stufe 0: macOS-only-Konfiguration, einheitliches Deployment Target, sichere Papierkorbsemantik, dokumentiertes Distributionsmodell, experimentell gekennzeichnete Shell und temporäre Testumgebung.
- Stufe 1: unabhängige Zustände beider Panels, stabile URL-basierte Auswahl und Markierungen, vorab geladene Dateimetadaten, asynchroner und testbarer Dateisystemdienst sowie Schutz vor veralteten Ladeergebnissen.
- Stufe 2: vorab geplante Dateioperationen, explizite Konfliktentscheidungen, Fortschritt, Abbruch, strukturierte Teilergebnisse und sichere Behandlung von Symlinks sowie Volume-Wechseln.
- Stufe 3: editierbare Pfadleisten, Verlauf, Volumes, Sitzungswiederherstellung, Schnellfilter, zentrale Befehlsregistrierung, stabile Fokusführung und interner Viewer.
- Stufe 4: Panel-Tabs, rekursive Datei- und Inhaltssuche mit virtuellen Ergebnis-Panels, Vergleich und Synchronisationsvorschau, Mehrfachumbenennung mit Undo, ZIP/TAR-Werkzeuge, SHA-256, Inhaltsvergleich, Drag-and-drop, Operationswarteschlange und konfigurierbare Befehle.

Die konkreten Datenverlustpfade aus der Projektprüfung sind durch gezielte Fehler- und Konkurrenztests abgesichert. Vor der Freigabe bleiben insbesondere zusätzliche Dateisysteme, erzwungener Prozessabbruch, vollständige Bedienabnahme, Performance und Developer-ID-/Notarisierungsprüfung offen. Der [priorisierte Umsetzungsplan](ROADMAP.md#umsetzungsplan-nach-der-projektprüfung) unterscheidet implementierte Korrekturen von dieser Release-Abnahme.

Die Arbeitsnachweise stehen unter [Stufen 0 und 1](docs/progress/2026-08-31-stufen-0-und-1.md), [Stufe 2](docs/progress/2026-08-31-stufe-2.md), [Stufe 3](docs/progress/2026-09-01-stufe-3.md) und [Stufe 4](docs/progress/2026-09-01-stufe-4.md). Architekturentscheidungen dokumentieren [ADR 0001](docs/decisions/0001-distribution-and-file-access.md), [ADR 0002](docs/decisions/0002-konflikte-und-dateioperationen.md), [ADR 0003](docs/decisions/0003-command-navigation-viewer.md), [ADR 0004](docs/decisions/0004-symbolische-links-beim-oeffnen.md), [ADR 0005](docs/decisions/0005-power-tools-und-externe-prozesse.md) und [ADR 0006 – sichere Dateimutationen](docs/decisions/0006-sichere-dateimutationen.md).

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
| Zwei Panels | Unabhängige Zustände pro Tab; aktives Panel ist Quelle; alle echten Tabs einschließlich Auswahl des aktiven Tabs, Sortierung und Filter werden wiederhergestellt | Virtuelle Suchergebnisse und Verlauf werden nicht persistiert; fehlende Verzeichnisse werden verworfen |
| Navigation | Editierbare Pfadleiste, `.`, `..`, Verlauf, Home, Wurzel, Volumes, Favoriten und direkter Pfad; Enter und Doppelklick öffnen Verzeichnisse und folgen Verzeichnis-Links | Weitere virtuelle Orte außer Suchergebnissen sind offen |
| Dateiliste | Name sowie optional Typ, Größe und POSIX-Rechte aus einmalig geladenen Metadaten; Verzeichnisse zuerst | Sehr große Verzeichnisse weiter profilieren |
| Auswahl | URL-basierter Cursor und Mehrfachmarkierung pro Panel; Shift-Bereichsauswahl mit Maus und Pfeiltasten; Schnellfilter und gespeicherte Wildcard-Auswahlmuster | Vollständige VoiceOver-Abnahme offen |
| Dateioperationen | Direkte Aufträge laufen geplant und asynchron in einer Warteschlange; Archive und Mehrfachumbenennung teilen Abbruch-, Beendigungs- und Berichtsverwaltung | Keine automatische Wiederaufnahme nach Neustart; Berichtsverlauf gilt für die laufende Sitzung |
| Konflikte | Ersetzen, Überspringen, beide behalten, Verzeichnisse zusammenführen oder abbrechen; passende Entscheidung „für alle“ | Zusammenführen überspringt verschachtelte Zielkonflikte sicher und weist sie einzeln im Bericht aus |
| Sicherheit | Kein endgültiger Lösch-Fallback; private Arbeitsbereiche, exklusive Veröffentlichung, Identitäts-/Baumprüfung und verifizierte Metadaten; realer Volume-Wechsel auf temporärem APFS getestet | Weitere Dateisysteme und Ausfälle prüfen; keine atomare Transaktion über einen ganzen Mehrfachauftrag |
| Favoriten | Hinzufügen, filtern, ändern und entfernen; Speicherung in `UserDefaults` | Import/Export und bessere Fehlerdarstellung |
| Dateien öffnen | Enter und Doppelklick öffnen Dateien mit der verknüpften macOS-Standard-App; sichtbare Mehrfachmarkierungen werden unterstützt und nach App gruppiert | Auswahl einer abweichenden App über „Öffnen mit“ |
| Viewer | F3 öffnet Text-, Hex-, Bild- und Metadatenvorschau; native Suche in der geladenen Text-/Hexvorschau | Suche ist auf die begrenzte Vorschau beschränkt; weitere Binärdarstellungen offen |
| Editor | Systemstandard oder konfigurierbare App; Datei-Links öffnen ihr Ziel; fehlende oder ungültige Editoren werden verständlich gemeldet | Editorprofile und dateitypabhängige Zuordnung |
| Suche und Vergleich | Rekursive Namens-/Inhaltssuche, virtuelle Ergebnis-Tabs, flacher Metadatenvergleich, separater bytegenauer Dateivergleich und Kopiervorschau | Rekursive Synchronisationsvorschau fehlt; „Identisch“ im Verzeichnisvergleich bedeutet nur Metadatengleichheit; Suche auf 10.000 Ergebnisse begrenzt, Limit-/Teilfehlermeldungen offen |
| Mehrfachumbenennung | Live-Vorschau, Vorlagen, Zähler, Undo mit Identitätsprüfung, Wiederherstellung bei Teilfehlern/Abbruch und Journal mit tatsächlichen Pfaden | Undo nicht persistent; nach Prozessabsturz Journal manuell auswerten, keine automatische Wiederaufnahme |
| Archive und Prüfsummen | ZIP/TAR-Inhaltsbrowser, begrenzte Extraktion über System-libarchive in privaten Arbeitsbereich, geprüfte Pfade/Links und Konflikte; sicheres Packen; SHA-256 | Archivnavigation bleibt ein Dialog; Hardlinks und Links mit Elternkomponenten werden abgewiesen; kein verlustfreies macOS-Backup |
| Power-User | Drag-and-drop, Hintergrundwarteschlange, eigene Commands mit `%P`/`%F` und ein-/ausblendbare Buttonleiste | Warteschlange wird nicht persistiert |
| Kommandozeile | Asynchroner Prozessstart mit Arbeitsverzeichnis, Exit-Code und getrennt erfasster Standard-/Fehlerausgabe; keine Shell-Auswertung | Experimentell; Ausgabegrenzen und zuverlässige Prozessbeendigung noch absichern |
| Tests | Isolierter Testhost, eigene Settings-Stores, Sicherheitsregressionen einschließlich temporärem APFS-Volume und Beenden während einer Kopie; aktueller Prüfstand unten | VoiceOver-, Kontrast-, weitere Dateisystem- und Performance-Abnahme sowie CI ausstehend |

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
| `Shift` + `↑` / `↓` oder Klick | Bereich in der sichtbaren Sortierung markieren; bestehende unabhängige Markierungen bleiben erhalten |
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

Im Text-/Hexviewer öffnet `Command` + `F` die native Suchleiste; `Command` + `G` und `Command` + `Shift` + `G` wechseln zwischen Treffern der geladenen Vorschau. `Escape` schließt den Viewer. Panel-Shortcuts greifen während Texteingabe und in Dialogen nicht ein.

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
CommanderSessionStore ──> echte Tabs, aktive Tabs/Panel, Sortierung und Filter
FileViewerLoader (actor) ──> begrenzte Text-, Hex-, Bild- und Metadatenvorschau
PowerTools ──> Suche, Vergleich, Umbenennung, SHA-256, Archive und Prozesse
```

| Datei | Verantwortung |
| --- | --- |
| `DumbCommander/CommanderState.swift` | Aktives Panel, Panel-Tabs, virtuelle Ergebnisse und je ein unabhängiger `PanelState` pro Tab |
| `DumbCommander/FileItem.swift` | Stabile Identität, vorab geladene Metadaten und deterministische Sortierung |
| `DumbCommander/FileSystemService.swift` | Testbares Protokoll und reale asynchrone Dateisystemimplementierung |
| `DumbCommander/FileOperationCoordinator.swift` | Planung, Konfliktmodell, Fortschritt, Abbruch und strukturierte Operationsberichte |
| `DumbCommander/SafeFileIO.swift`, `DumbCommander/SafeTransfer.swift` | Verankerte Dateideskriptoren, Metadatenübertragung, private Arbeitsbereiche und exklusive Veröffentlichung |
| `DumbCommander/ArchiveService.swift`, `DumbCommander/SystemArchive/` | Typisiertes Archivmanifest, kontrollierte Extraktion und schmale Anbindung an die macOS-Systembibliothek |
| `DumbCommander/MutationActivity.swift` | Gemeinsame laufende Jobs, Berichtsverlauf und kontrolliertes Schließen/Beenden |
| `DumbCommander/CommandRegistry.swift` | Gemeinsame Definition von Befehlen, Labels und Shortcuts |
| `DumbCommander/SessionStore.swift` | Versionierte Tab-Sitzungen mit Migration sowie zentrale, für Tests isolierte Einstellungen |
| `DumbCommander/FileViewer.swift` | Asynchroner, speicherbegrenzter Viewer mit nativer Textsuche |
| `DumbCommander/CommanderChrome.swift` | Arbeitsbereichskopf, Quelle-/Zielkennung und beobachtete Auswahl-/Statusanzeigen |
| `DumbCommander/PowerTools.swift` | Testbare Dienste für Suche, Vergleich, Mehrfachumbenennung samt Wiederherstellungsjournal, SHA-256 und Prozesse |
| `DumbCommander/PowerToolsViews.swift` | Vorschau- und Ergebnisoberflächen der Power-User-Werkzeuge |
| `DumbCommander/ContentView.swift` | Hauptlayout, Konflikt-/Fortschrittsoberfläche und Weitergabe von Benutzeraktionen |
| `DumbCommander/FileListView.swift` | Darstellung und Eingaben eines Panels ohne eigenen Dateisystemzustand |
| `DumbCommander/KeyEventHandlingView.swift` | Brücke zu lokalen AppKit-Tastaturereignissen |
| `DumbCommander/SettingsView.swift` | Einstellungen und Favoritenpflege |

Die Dienste für lange Dateioperationen laufen außerhalb des Main Actors. Reguläre Dateien werden blockweise kopiert, damit Fortschritt und Abbruch auch innerhalb großer Einzeldateien wirksam sind. Die Umbenennungsvorschau prüft nur Namen; Dateisystemprüfung und Ausführung liegen im Dienst. Große Sortier-/Filterarbeit im UI-Pfad bleibt Teil der Nachbesserung.

Kopieren und der Volume-Fallback erhalten POSIX-Modus, Änderungs-/Erstellungszeit, Dateiflags, Extended Attributes einschließlich Resource Fork und ACLs. Kann das Ziel diese Metadaten nicht bewahren, schlägt die Operation vor der Veröffentlichung fehl. Besitzerwechsel, Hardlink-Topologie und physische Sparse-/Kompressionsdarstellung sind nicht zugesagt. Archive dürfen höchstens 100.000 Einträge, 20 GiB entpackten Inhalt und 4.096 UTF-8-Bytes pro Pfad enthalten. Bereits vorhandene Entpackziele werden als Konflikt abgewiesen. Details und Wiederherstellungspfade stehen in ADR 0006.

## Plattform und Distribution

- ausschließlich macOS 14 oder neuer;
- SwiftUI mit gezielten AppKit-Brücken;
- Swift 5 Language Mode;
- keine zusätzlich zu installierenden Pakete; Archive nutzen die mit macOS gelieferte Systembibliothek libarchive.2;
- direkte, signierte und später notarisierte Distribution außerhalb des Mac App Store;
- App Sandbox deaktiviert, Hardened Runtime aktiviert;
- Full Disk Access ist keine normale Voraussetzung.

Geschützte macOS-Bereiche und POSIX-Berechtigungen gelten weiterhin. Fehler werden nicht durch aggressivere Folgeoperationen umgangen.
Security-Scoped Bookmarks sind im beschlossenen, nicht sandboxed Distributionsmodell nicht erforderlich. Die Sitzung speichert Pfade und Anzeigeeinstellungen, keine Zugriffsrechte. Nicht mehr verfügbare Verzeichnisse werden beim Start verworfen, Verzeichnis-Links kontrolliert auf ihr Ziel aufgelöst. Das alte Format mit einem Pfad je Panel wird automatisch migriert.

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

Vollständige Unit-, Integrations- und UI-Suite mit lokaler Ad-hoc-Signierung:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
  -project DumbCommander.xcodeproj \
  -scheme DumbCommander \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/TestDerivedData \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
  test
```

**Prüfstand vom 14. Oktober 2026:** Debug-Build und vollständige Suite sind erfolgreich: **79 Unit-/Integrationstests und 20 UI-Testausführungen ohne Fehler**. Die UI-Suite enthält 18 Haupttests sowie einen Launchtest in zwei Konfigurationen. Das geteilte Scheme ist im Repository enthalten. Test-App, Favoriten, Sitzungen und `@AppStorage` verwenden eigene temporäre Wurzeln bzw. Settings-Stores; App-hosted Unit-Tests bekommen auch ohne expliziten Fixturepfad eine isolierte Wurzel. Der Volume-Test erzeugt und mountet mit `hdiutil` ein temporäres APFS-Diskimage innerhalb seiner Fixture und hängt es anschließend aus. UI-Tests benötigen eine angemeldete macOS-Sitzung. Die Ad-hoc-Signierung ist eine lokale Prüfung und ersetzt keine Developer-ID-/Notarisierungsabnahme. [Vollständiger Sicherheitsnachweis](docs/progress/2026-10-14-sicherheit-dateioperationen.md).

## Nächste Priorität

Die Sicherheitskorrekturen und die gemeinsame Verwaltung laufender Mutationen sind umgesetzt. Als Nächstes folgen die verbliebenen Abnahmen aus [Stufe 5](ROADMAP.md#umsetzungsplan-nach-der-projektprüfung), verlässliche Vergleichs- und Suchergebnisse, Performance und Barrierefreiheit. Packaging, abschließende Icon-Prüfung, Developer-ID-Signierung und Notarisierung bilden den Abschluss. Neue Netzwerk- oder Plugin-Funktionen sind bis zur Kernabnahme zurückgestellt.

## Mitwirken

Die verbindlichen Regeln stehen in [AGENTS.md](AGENTS.md). Die ältere Datei `DumbCommander/README.md` wird in das App-Bundle kopiert und ist nur Prototyp-Altbestand; maßgeblich sind diese Root-README, die Roadmap und die ADRs.
