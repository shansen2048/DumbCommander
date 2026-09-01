# DumbCommander – Entwicklungsplan

Dieser Plan beschreibt den Weg vom aktuellen Prototyp zu einem verlässlichen, im Alltag gut brauchbaren Zwei-Panel-Dateimanager. Die Reihenfolge folgt den Projektprioritäten aus [`AGENTS.md`](AGENTS.md): zuerst Datensicherheit und korrekter Panelzustand, danach Bedienkomfort und erweiterte Commander-Funktionen.

## Umsetzungsstand

| Stufe | Status | Abschluss |
| --- | --- | --- |
| 0 – Bestand absichern | Abgeschlossen | 31. August 2026 |
| 1 – Zustand und Architektur stabilisieren | Abgeschlossen | 31. August 2026 |
| 2 – Sichere Dateioperationen | Abgeschlossen | 31. August 2026 |
| 3 – Gut brauchbarer Commander-Kern | Abgeschlossen | 1. September 2026 |
| 4 – Power-User-Funktionen | Offen | – |
| 5 – Release-Härtung | Offen | – |

Die detaillierten Nachweise für Arbeiten, Tests und verbleibende Grenzen stehen in
[`docs/progress/2026-08-31-stufen-0-und-1.md`](docs/progress/2026-08-31-stufen-0-und-1.md)
und [`docs/progress/2026-08-31-stufe-2.md`](docs/progress/2026-08-31-stufe-2.md).
Der Nachweis für Stufe 3 steht in
[`docs/progress/2026-09-01-stufe-3.md`](docs/progress/2026-09-01-stufe-3.md).

## Zielzustand

Die erste gut brauchbare Version muss zuverlässig können:

- zwei vollständig getrennte Panels verwalten;
- ausschließlich aus dem aktiven Panel in das andere Panel operieren;
- navigieren, markieren, kopieren, verschieben, umbenennen, Ordner erstellen und in den Papierkorb löschen;
- Konflikte verständlich behandeln;
- auch bei größeren Operationen bedienbar bleiben;
- ausgewählte Verzeichnisse nach einem Neustart wieder öffnen;
- ohne Risiko für reale Benutzerdaten getestet werden.

## Übersicht

| Stufe | Ziel | Ergebnis | Aufwand grob |
| --- | --- | --- | --- |
| 0 | Bestand absichern | Gefährliche Fehler beseitigt, Plattform und Berechtigungsmodell entschieden | 2–4 Tage |
| 1 | Architektur stabilisieren | Getrennter Panelzustand und testbarer Dateisystemdienst | 1–2 Wochen |
| 2 | Dateioperationen zuverlässig machen | Sichere, asynchrone Operationen mit Konflikten und Fortschritt | 1–2 Wochen |
| 3 | Commander-Kern abrunden | Gute Tastaturbedienung, Navigation, Viewer und persistente Sitzung | 1–2 Wochen |
| 4 | Power-User-Funktionen | Suche, Tabs, Vergleich, Synchronisation und Mehrfachumbenennung | 3–5 Wochen |
| 5 | Release-Härtung | Performance, Barrierefreiheit, Packaging und vollständige Tests | 1–2 Wochen |

Die Schätzungen gelten ungefähr für eine Person in Vollzeit. Ein brauchbarer lokaler Dateimanager ist nach Stufe 3 erreicht; Stufen 4 und 5 entwickeln ihn zu einem umfassenderen Commander und einer veröffentlichungsfähigen App weiter.

## Stufe 0 – Bestand absichern ✅

Ziel: Das Projekt darf während des Umbaus keine Daten gefährden.

### Aufgaben

1. Bestehende Working-Tree-Änderungen prüfen und in nachvollziehbare Changes aufteilen.
2. Automatischen `removeItem`-Fallback nach einem Papierkorbfehler entfernen.
3. Löschen vorübergehend nur über den Papierkorb erlauben.
4. macOS als einzige unterstützte Plattform konfigurieren.
5. Deployment Targets von App und Tests vereinheitlichen.
6. Distributionsmodell entscheiden und in einem ADR dokumentieren:
   - Sandbox mit benutzergewählten Wurzeln und Security-Scoped Bookmarks; oder
   - signierte und notarisierte App außerhalb des Mac App Store.
7. Shell-Konsole als experimentell kennzeichnen oder vorübergehend standardmäßig ausblenden.
8. Reproduzierbaren Debug-Build dokumentieren.
9. Temporäres Testverzeichnis und grundlegende Testhelfer einrichten.

### Abnahmekriterien

- Papierkorbfehler können nicht zu endgültigem Löschen führen.
- Das Projekt baut ausschließlich als macOS-App.
- Das Berechtigungsmodell ist dokumentiert.
- Kein Test greift auf das echte Benutzerverzeichnis zu.

**Ergebnis:** abgeschlossen. Der Papierkorbpfad besitzt keinen endgültigen Lösch-Fallback, App und Tests zielen einheitlich auf macOS 14, das Distributionsmodell ist in ADR 0001 entschieden und alle schreibenden Tests arbeiten in eigens erzeugten temporären Verzeichnissen.

## Stufe 1 – Zustand und Architektur stabilisieren ✅

Ziel: Beide Panels besitzen einen korrekten, unabhängigen Zustand.

### Zielmodell

```text
CommanderState
├── leftPanel: PanelState
├── rightPanel: PanelState
└── activePanel

PanelState
├── directory
├── items
├── cursor
├── markedItems
├── sorting
└── history
```

### Aufgaben

1. `PanelState` für jedes Panel einführen.
2. Globales `selectedFile` und `markedFiles` entfernen.
3. Auswahl anhand stabiler URLs oder IDs statt Listenindizes speichern.
4. `FileItem` mit einmalig geladenen Metadaten einführen:
   - URL und Name;
   - Typ;
   - Größe;
   - Änderungsdatum;
   - Berechtigungen;
   - Verzeichnis-, Paket- und Symlinkstatus.
5. `FileSystemService` als Protokoll definieren.
6. Reale Implementierung und Testimplementierung hinzufügen.
7. Verzeichnislesen aus `FileListView` herauslösen.
8. Veraltete Ladeergebnisse nach einem Verzeichniswechsel verwerfen.
9. `ContentView` auf Layout und Intent-Weitergabe reduzieren.
10. Unit-Tests für Panelwechsel, Markierungen, Cursor und Sortierung ergänzen.

### Abnahmekriterien

- Jedes Panel behält Auswahl und Markierungen beim Panelwechsel.
- Eine Operation kann niemals versehentlich die Auswahl des anderen Panels verwenden.
- Ein Mausklick aktiviert das betreffende Panel.
- Verzeichnisinhalte und Sortierung sind ohne SwiftUI testbar.
- Beide großen Views enthalten keine neue Dateisystemlogik.

**Ergebnis:** abgeschlossen. `CommanderState`, zwei unabhängige `PanelState`-Instanzen, `FileItem` und `FileSystemServing` bilden die neue Basis. Veraltete Ladeergebnisse werden verworfen; Auswahl, Markierungen und Operationsquellen sind panelgebunden. Die verbleibende Dialog- und Operationskoordination in `ContentView` wird in Stufe 2 in einen `FileOperationCoordinator` verschoben.

## Stufe 2 – Sichere Dateioperationen ✅

Ziel: Die Kernoperationen sind zuverlässig, nachvollziehbar und unterbrechbar.
Symbolische Links werden als eigenständige Dateisystemobjekte behandelt und niemals
automatisch dereferenziert oder rekursiv verfolgt.

### Aufgaben

1. `FileOperationCoordinator` einführen.
2. Operationen zunächst planen und anschließend ausführen.
3. Folgende Operationen implementieren:
   - Kopieren;
   - Verschieben;
   - Umbenennen;
   - Ordner anlegen;
   - in den Papierkorb verschieben.
4. Quelle und Ziel vor jeder Operation normalisieren und validieren.
5. Kopieren oder Verschieben eines Verzeichnisses in sich selbst verhindern.
6. Symbolische Links bei Dateioperationen ohne Dereferenzierung behandeln:
   - Kopieren erzeugt einen Link mit demselben Linkziel;
   - Verschieben, Umbenennen und Papierkorb betreffen nur den Link selbst;
   - Verzeichnislesen und rekursive Operationen steigen niemals in das Linkziel ein.
7. Konfliktmodell einführen:
   - Überspringen;
   - Ersetzen;
   - beide behalten;
   - zusammenführen, nur bei Verzeichnissen;
   - abbrechen.
8. „Für alle Konflikte anwenden“ unterstützen.
9. Operationen außerhalb des Main Actors ausführen.
10. Fortschritt, aktuelles Element und Abbruch anzeigen.
11. Strukturierte Ergebnisse pro Element liefern.
12. Nach Operationen beide Panels gezielt aktualisieren.
13. Integrationstests ausschließlich in neuen temporären Verzeichnissen ergänzen.

### Wichtige Testfälle

- Quelle existiert nicht mehr.
- Ziel existiert bereits.
- Schreibberechtigung fehlt.
- Verschieben zwischen verschiedenen Volumes.
- Symlink auf Datei oder Verzeichnis wird als Link kopiert und nicht verfolgt.
- Linkziel bleibt bei Kopieren, Verschieben, Umbenennen und Papierkorb unverändert.
- Verzeichnis wird in sich selbst kopiert.
- Abbruch während einer größeren Operation.
- Teilfehler bei einer Mehrfachauswahl.
- Papierkorb ist nicht verfügbar.

### Abnahmekriterien

- Nichts wird stillschweigend überschrieben oder endgültig gelöscht.
- Dateioperationen dereferenzieren symbolische Links nie oder betreten sie rekursiv.
- Große Operationen blockieren die Oberfläche nicht.
- Abbruch hinterlässt einen verständlich dokumentierten Zustand.
- Alle Kernoperationen besitzen Erfolgs- und Fehlertests.

**Ergebnis:** abgeschlossen. Der `FileOperationCoordinator` trennt Planung,
Konfliktentscheidungen und Ausführung. Konflikte unterstützen Ersetzen,
Überspringen, beide behalten, Verzeichniszusammenführung und Abbruch sowie
passende „für alle“-Regeln. Operationen liefern Fortschritt und strukturierte
Ergebnisse, sind zwischen Kopierblöcken abbrechbar und aktualisieren danach
beide Panels. 25 Unit-/Integrationstests prüfen den Operationskern ausschließlich
in neuen temporären Verzeichnissen. Details stehen im
[Arbeitsnachweis für Stufe 2](docs/progress/2026-08-31-stufe-2.md).

## Stufe 3 – Gut brauchbarer Commander-Kern ✅

Ziel: Die App ist für tägliche lokale Dateioperationen angenehm nutzbar.

### Navigation

- editierbare Pfadleiste;
- Vorwärts- und Rückwärtsverlauf pro Panel;
- Home- und Root-Navigation;
- Auswahl eingebundener Volumes;
- Wiederherstellung der letzten Sitzung;
- Sitzungszugriff entsprechend ADR 0001 ohne Security-Scoped Bookmarks, da die App nicht sandboxed verteilt wird;
- bewusstes Öffnen von Datei- und Verzeichnis-Links mit begrenzter, zyklussicherer Zielauflösung;
- Schnellfilter innerhalb des aktuellen Verzeichnisses.

### Bedienung

1. Zentrales `CommandRegistry` einführen.
2. Menü, Toolbar, Funktionsleiste und Shortcuts daraus ableiten.
3. F3 bis F8 verbindlich umsetzen.
4. `Shift`+F6 für reines Umbenennen vorsehen.
5. F1/F2-Belegung bewusst entscheiden und dokumentieren.
6. Fokuswechsel zwischen Panel, Pfadleiste, Filter und Dialogen stabilisieren.
7. Cursor und Markierung auch ohne Farbe unterscheiden.
8. Funktionstastenleiste an kleine Fensterbreiten anpassen.
9. Deutsche Texte vereinheitlichen.
10. Enter und Doppelklick auf Verzeichnisse gleich behandeln; Dateien mit ihrer
    verknüpften macOS-App öffnen und sichtbare Mehrfachmarkierungen unterstützen.

### Viewer und Editor

- interner Textviewer für große Dateien;
- Hexansicht als einfache zweite Darstellungsart;
- Bildvorschau;
- Metadatenansicht;
- externer Editor weiterhin konfigurierbar;
- verständlicher Fehler, wenn der konfigurierte Editor fehlt.

### Abnahmekriterien

- Alle normalen Dateioperationen sind vollständig per Tastatur möglich.
- Die zuletzt verwendeten Verzeichnisse funktionieren nach einem Neustart.
- Die UI bleibt bei großen Verzeichnissen reaktionsfähig.
- Fokus und Shortcuts funktionieren zuverlässig in Textfeldern und Dialogen.
- Die App ist damit als Version `0.1` für lokale Nutzung brauchbar.

**Ergebnis:** abgeschlossen. Beide Panels besitzen editierbare Pfadleisten,
Rück-/Vorwärtsverlauf, Home-, Wurzel- und Volume-Navigation, einen Schnellfilter
und eine validierte Sitzungswiederherstellung. `CommandRegistry` speist Menü,
Toolbar, Funktionsleiste und globale Shortcuts; Texteingaben und Dialoge sperren
Commander-Shortcuts zuverlässig. F3 öffnet den speicherbegrenzten internen
Text-, Hex-, Bild- und Metadatenviewer. Bewusst geöffnete symbolische Links
führen kontrolliert zum Ziel, ohne die Semantik der Dateioperationen zu ändern.
Die Version ist auf `0.1` gesetzt. 36 Unit-/Integrationstests und zehn gezielte
UI-Tests decken den aktuellen Kern ab. Details stehen im
[Arbeitsnachweis für Stufe 3](docs/progress/2026-09-01-stufe-3.md).

## Stufe 4 – Power-User-Funktionen

Ziel: Vom brauchbaren Dateimanager zum echten Commander-Werkzeug.

### Priorität A

- Panel-Tabs;
- vollständige Dateisuche;
- Suchergebnisse als virtuelles Panel;
- Verzeichnisvergleich;
- Synchronisation mit Vorschau;
- Mehrfachumbenennung mit Live-Vorschau;
- Undo für Mehrfachumbenennung.

### Priorität B

- ZIP- und TAR-Archive wie Verzeichnisse öffnen;
- Packen und Entpacken;
- Checksummen erzeugen und prüfen;
- Dateiinhalte vergleichen;
- konfigurierbare Spalten;
- gespeicherte Such- und Auswahlmuster.

### Priorität C

- Drag & Drop;
- Operationswarteschlange;
- Hintergrundoperationen;
- benutzerdefinierte Commands;
- konfigurierbare Buttonleiste.

Netzwerkprotokolle oder Plugins sollten erst danach kommen. Sie vervielfachen Fehlerfälle, Berechtigungsfragen und Testaufwand.

## Stufe 5 – Release-Härtung

Ziel: Eine stabile, verteilbare Anwendung.

### Aufgaben

- Performance-Tests mit sehr großen Verzeichnissen;
- Tests mit externen und langsamen Volumes;
- vollständige VoiceOver-Beschriftung;
- Tastaturnavigation ohne Maus prüfen;
- Hell-, Dunkel- und hohen Kontrast prüfen;
- strukturierte Logs ohne vertrauliche Pfadinhalte;
- Crash- und Fehlerberichte vorbereiten;
- CI-Build und automatisierte Tests;
- Release-Konfiguration und Codesignierung;
- Notarisierung;
- frische Installation und Upgrade-Pfad prüfen;
- App-Icon, Versionsnummern und Release Notes;
- alte eingebettete `DumbCommander/README.md` entfernen oder ersetzen.

### Release-Kriterien

- Kein bekannter Datenverlustfehler.
- Keine blockierende Dateiarbeit auf dem Main Actor.
- Keine widersprüchlichen Sandbox- oder Plattform-Einstellungen.
- Kernoperationen sind vollständig automatisiert getestet.
- Die signierte App funktioniert nach Neustart mit den erlaubten Verzeichnissen.
- Die Dokumentation entspricht dem ausgelieferten Verhalten.

## Empfohlene Meilensteine

| Version | Name | Umfang |
| --- | --- | --- |
| `0.0.1` | Safety Baseline | Stufe 0 abgeschlossen |
| `0.0.2` | Panel Model | Stufe 1 abgeschlossen |
| `0.0.3` | Reliable Operations | Stufe 2 abgeschlossen |
| `0.1.0` | Usable Commander | Stufe 3 abgeschlossen |
| `0.2.0` | Power Tools | Wichtigste Teile aus Stufe 4 |
| `1.0.0` | Stable Release | Stufe 5 abgeschlossen |

## Kritischer Pfad

```text
Löschsicherheit
    ↓
Getrennter Panelzustand
    ↓
Testbarer Dateisystemdienst
    ↓
Zuverlässige Dateioperationen
    ↓
Tastaturbedienung und Navigation
    ↓
Erweiterte Commander-Funktionen
```

Suche, Archive oder Tabs sollten nicht vorgezogen werden, solange Quelle und Ziel einer Dateioperation noch verwechselt werden können.

## Pflege des Plans

- Beim Start einer Stufe offene Aufgaben in konkrete, kleine Issues zerlegen.
- Aufgaben erst als abgeschlossen betrachten, wenn die jeweiligen Abnahmekriterien erfüllt sind.
- Neue Anforderungen einer Stufe und Priorität zuordnen, statt sie ungeplant in den aktuellen Umbau einzuschieben.
- Abweichungen, Architekturentscheidungen und geänderte Meilensteine in diesem Dokument und gegebenenfalls in der Root-[`README.md`](README.md) aktualisieren.
