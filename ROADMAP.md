# DumbCommander – Entwicklungsplan

Dieser Plan beschreibt den Weg zu einem verlässlichen, im Alltag gut brauchbaren Zwei-Panel-Dateimanager. Die Reihenfolge folgt den Projektprioritäten aus [`AGENTS.md`](AGENTS.md): zuerst Datensicherheit und korrekter Panelzustand, danach Bedienkomfort und erweiterte Commander-Funktionen.

**Aktualisiert am 14. Oktober 2026:** Auf die [Projektprüfung](docs/progress/2026-10-09-projektbewertung.md) folgen isolierte Tests, Tab-/Fokuskorrekturen, vollständige echte Tab-Sitzungen, Shift-Bereichsauswahl und Viewer-Suche. Oberfläche und App-Icon sind überarbeitet. Die Sicherheitskorrekturen zu Operationen, Archiven, Rollback und Beendigungslebenszyklus sind implementiert und lokal getestet. Maßgeblich sind der [Umsetzungsplan nach der Projektprüfung](#umsetzungsplan-nach-der-projektprüfung), der [Bedienungsnachweis](docs/progress/2026-10-14-bedienung-und-oberflaeche.md) und der [Sicherheitsnachweis mit Abnahmegrenzen](docs/progress/2026-10-14-sicherheit-dateioperationen.md).

## Umsetzungsstand

| Stufe | Aktueller Status | Historischer Implementierungsstand |
| --- | --- | --- |
| 0 – Bestand absichern | Lokale Testisolation korrigiert und Suite erfolgreich | 31. August 2026 |
| 1 – Zustand und Architektur stabilisieren | Tab-/Eingabeidentitäten und gemeinsame Verwaltung laufender Mutationen umgesetzt | 31. August 2026 |
| 2 – Sichere Dateioperationen | Metadaten, konkurrierende Änderungen und Fehlerbereinigung lokal abgesichert | 31. August 2026 |
| 3 – Gut brauchbarer Commander-Kern | Implementiert; Fokus und Performance erneut abnehmen | 1. September 2026 |
| 4 – Power-User-Funktionen | Archive und Rollback abgesichert; Vergleich und Suchgrenzen weiter nachbessern | 1. September 2026 |
| 5 – Release-Härtung | 5A–5D lokal geprüft; weitere Ausfall-/Dateisystemabnahme offen, Teile von 5E/5G umgesetzt | – |

Die detaillierten Nachweise für Arbeiten, Tests und verbleibende Grenzen stehen in
[`docs/progress/2026-08-31-stufen-0-und-1.md`](docs/progress/2026-08-31-stufen-0-und-1.md)
und [`docs/progress/2026-08-31-stufe-2.md`](docs/progress/2026-08-31-stufe-2.md).
Der Nachweis für Stufe 3 steht in
[`docs/progress/2026-09-01-stufe-3.md`](docs/progress/2026-09-01-stufe-3.md).
Der Nachweis für Stufe 4 steht in
[`docs/progress/2026-09-01-stufe-4.md`](docs/progress/2026-09-01-stufe-4.md).

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
| 5 | Absicherung und Release-Härtung | Befunde schließen, Performance, Barrierefreiheit, Packaging und vollständige Tests | Neu geschätzt: 5–9 Wochen |

Die Schätzungen für Stufen 0 bis 4 sind die ursprünglichen Planwerte. Die neue Schätzung für Stufe 5 gilt für eine Person in Vollzeit und schließt die gefundenen Nachbesserungen ein; sie ist nach Herstellung einer ausführbaren Testbasis zu überprüfen. Funktionsausbau allein ist kein Abnahmenachweis.

## Stufe 0 – Bestand absichern

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

**Historischer Implementierungsstand:** Der Papierkorbpfad besitzt keinen endgültigen Lösch-Fallback, App und Tests zielen einheitlich auf macOS 14 und das Distributionsmodell ist in ADR 0001 entschieden. Schreibende Operationsfixtures verwenden temporäre Verzeichnisse. Die damals noch unvollständige Isolation von Test-App und Einstellungen wurde am 14. Oktober in Arbeitspaket 5A korrigiert.

## Stufe 1 – Zustand und Architektur stabilisieren

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

**Historischer Implementierungsstand:** `CommanderState`, unabhängige `PanelState`-Instanzen, `FileItem` und `FileSystemServing` bilden die Basis. Veraltete Ladeergebnisse werden verworfen; Auswahl, Markierungen und Operationsquellen sind im Modell panelgebunden. Der Operationskoordinator ist inzwischen vorhanden. Die mit Tabs entstandenen Identitäts- und Aktualisierungslücken werden in Arbeitspaket 5E bearbeitet; der Teilstand vom 14. Oktober ist unten dokumentiert.

## Stufe 2 – Sichere Dateioperationen

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

**Historischer Implementierungsstand:** Der `FileOperationCoordinator` trennt Planung,
Konfliktentscheidungen und Ausführung. Konflikte unterstützen Ersetzen,
Überspringen, beide behalten, Verzeichniszusammenführung und Abbruch sowie
passende „für alle“-Regeln. Operationen liefern Fortschritt und strukturierte
Ergebnisse, sind zwischen Kopierblöcken abbrechbar und aktualisieren danach
beide Panels. 25 Unit-/Integrationstests prüfen den Operationskern ausschließlich
in neuen temporären Verzeichnissen. Details stehen im
[Arbeitsnachweis für Stufe 2](docs/progress/2026-08-31-stufe-2.md).
Metadaten, Zieländerungen und Fehlerbereinigung sind seit dem 14. Oktober
in 5B abgesichert; weitere Dateisysteme und Ausfallszenarien bleiben Teil der Release-Abnahme.

## Stufe 3 – Gut brauchbarer Commander-Kern

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
- Die App ist damit als Version `0.1.0` für lokale Nutzung brauchbar.

**Historischer Implementierungsstand:** Beide Panels besitzen editierbare Pfadleisten,
Rück-/Vorwärtsverlauf, Home-, Wurzel- und Volume-Navigation, einen Schnellfilter
und eine validierte Sitzungswiederherstellung. `CommandRegistry` speist Menü,
Toolbar, Funktionsleiste und globale Shortcuts. Die globale Dialogsperre ist seit
dem 14. Oktober auch im Panel-Keyhandler berücksichtigt. F3 öffnet den speicherbegrenzten internen
Text-, Hex-, Bild- und Metadatenviewer. Bewusst geöffnete symbolische Links
führen kontrolliert zum Ziel, ohne die Semantik der Dateioperationen zu ändern.
Die damalige Version war `0.1.0`; 36 Unit-/Integrationstests und zehn gezielte
UI-Tests waren zu diesem Zeitpunkt vorhanden. Details stehen im
[Arbeitsnachweis für Stufe 3](docs/progress/2026-09-01-stufe-3.md).
Die vollständige Bedien- und Performanceabnahme folgt in 5E und 5G.

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

**Historischer Implementierungsstand:** Jedes Panel verwaltet unabhängige Tabs; die
rekursive Namens- und Inhaltssuche öffnet ihre Treffer in einem virtuellen Tab.
Verzeichnisvergleich, markierbare Unterschiede und Synchronisationsvorschau
verwenden für die Ausführung weiterhin den gemeinsamen Konflikt-Koordinator.
Mehrfachumbenennung besitzt Live-Vorschau und ein nicht persistentes Undo.
ZIP/TAR-Browser, Packen und Entpacken mit bisher unvollständiger Zielprüfung, SHA-256-Prüfung,
bytegenauer Inhaltsvergleich, konfigurierbare Spalten und gespeicherte Muster
decken Priorität B ab. Drag-and-drop, eine sequenzielle Hintergrundwarteschlange,
eigene Befehle ohne Shell-Auswertung und eine konfigurierbare Buttonleiste decken
Priorität C ab. Die Version ist auf `0.2.0` gesetzt. Grenzen und Prüfnachweise
stehen im [Arbeitsnachweis für Stufe 4](docs/progress/2026-09-01-stufe-4.md).
Die Projektprüfung vom 9. Oktober ergänzt offene Befunde zu Archivschutz,
Rollback, Jobverwaltung und der begrenzten Vergleichssemantik. Diese werden
in 5C, 5D und 5F bearbeitet; die damalige Abschlussmeldung ist keine Release-Freigabe.

## Stufe 5 – Release-Härtung

Ziel: Eine stabile, verteilbare Anwendung, deren vorhandene Funktionen die Sicherheits- und Bedieninvarianten nachweislich erfüllen.

### Umsetzungsplan nach der Projektprüfung

Die Befundnummern beziehen sich auf die [Projektbewertung vom 9. Oktober](docs/progress/2026-10-09-projektbewertung.md). Jedes Arbeitspaket wird in kleine Changes mit passenden Regressionstests aufgeteilt. Die Zeitspannen sind Planungshypothesen einschließlich Tests, keine zugesagten Termine.

| Paket | Konkretes Ergebnis | Abhängigkeit | Aufwand grob |
| --- | --- | --- | --- |
| 5A – Prüfgrundlage | Xcode nutzbar, Test-App und Settings isoliert, geteiltes Scheme und reproduzierbare Testbefehle | Betreiber prüft/akzeptiert Xcode-Lizenz | 1–3 Tage |
| 5B – Operationskern | Metadaten erhalten, fremde Ziele vor konkurrierenden Änderungen geschützt, eigene temporäre Dateien sicher bereinigt | 5A | 5–8 Tage |
| 5C – Archive | Sichere Pfad-/Linkprüfung, kontrollierte Extraktion und Veröffentlichung, gemeinsame Konfliktsemantik | 5A, sicherer Übernahmepfad aus 5B | 3–6 Tage |
| 5D – Wiederherstellung und Jobs | Abbruchfester Rename-Rollback, strukturierte Teilberichte, einheitlicher Job- und Beendigungslebenszyklus | 5A/5B; Integration der Archivjobs aus 5C | 3–5 Tage |
| 5E – Panels und Bedienung | Korrekte Tab-/Eingabeidentität, festes Drop-Ziel, gezielte Aktualisierung, Dialogfokus und sichtbarer Cursor | 5A; gemeinsame Jobergebnisse aus 5D | 3–5 Tage |
| 5F – Vergleich und Suche | Ehrliche Vergleichssemantik, rekursive Vorschau, unvollständige Suche sichtbar, begrenzte Prozessausgabe | 5B/5D/5E | 3–5 Tage |
| 5G – Alltag und Qualität | Vollständige echte Tab-Sitzung, Bereichsauswahl, Performance- und Accessibility-Abnahme, CI | 5A–5F | 4–7 Tage |
| 5H – Distribution | Signierter/notarisierter Release-Kandidat mit Installations-/Upgrade-Nachweis und aktuellen Release Notes | Alle Abnahmen aus 5A–5G | 3–5 Tage |

Gesamt: etwa 25–44 Arbeitstage, also 5–9 Vollzeitwochen ohne externe Wartezeiten. Nach 5A anhand der neu ausgeführten Suite und nach 5B anhand der Metadaten-/Volume-Ergebnisse neu schätzen. Developer-ID-Zugang und ein geeignetes Testvolume müssen spätestens für die entsprechenden Abnahmen verfügbar sein.

#### Fortschritt am 14. Oktober 2026

Die obigen Aufwände sind die ursprüngliche Gesamtschätzung vom 9. Oktober, keine verbleibende Restlaufzeit. Die folgenden Ergebnisse reduzieren den offenen Umfang:

- **5A lokal erfüllt:** Betreiber hat die Xcode-Lizenz akzeptiert. Geteiltes Scheme, isolierte App-Starts, temporäre Testwurzeln und gemeinsame Settings-Konfiguration einschließlich `@AppStorage` sind umgesetzt. Nach den Sicherheitskorrekturen bestehen Debug-Build und vollständige Suite mit 79 Unit-/Integrationstests und 20 UI-Testausführungen.
- **5B implementiert und lokal getestet:** Identitäts- und Baumprüfung schützt geplante Quellen/Ziele; private Arbeitsbereiche und exklusive Umbenennung verhindern überschreibende Veröffentlichung. Metadaten werden übertragen und überprüft. Fehlerbereinigung entfernt ausschließlich eigene Einträge. Tests umfassen gezielte Konkurrenz, Berechtigungs-/Metadatenfehler, EXDEV-Injektion und einen tatsächlichen Wechsel auf ein temporäres APFS-Volume. ExFAT/SMB, weitere externe Medien und Ausfalltests bleiben offen.
- **5C implementiert und lokal getestet:** ZIP/TAR werden über die macOS-Systembibliothek gelesen, vollständig auf Pfade, Links, Duplikate und Grenzen geprüft und ausschließlich in einem privaten Bereich extrahiert. Veröffentlichung erfolgt über den Operationskoordinator. Vorhandene Ziele werden nicht überschrieben oder zusammengeführt. Packen schützt Optionsoperanden und bestehende Archive. Manipulierte ZIP-/TAR-Fixtures, Abbruch, Limits und späte Konflikte sind abgedeckt.
- **5D implementiert und lokal getestet:** Zweiphasiger, von Cancellation unabhängiger Rename-Rollback, Identitätsprüfung bei Undo, wiederholbare Wiederherstellung und vor jedem Rename synchronisiertes Journal mit tatsächlichen Pfaden. Direkte Operationen, Archive und Batch-Jobs teilen Beendigungssteuerung und Sitzungsberichte. F10, Cmd-Q und Fensterschließen während einer Kopie sind in einer lokal signierten App geprüft. Journal-Import nach Neustart, erzwungener Prozessabbruch und Developer-ID-Abnahme sind noch offen.
- **5E teilweise umgesetzt:** Lade- und Keyhandler-Identität folgt dem ausgewählten Tab; Schließen eines früheren Tabs erhält den aktiven Tab. Navigation entfernt alte Zeilen sofort. Drop-Ziele werden vor der asynchronen URL-Auswertung festgelegt. Direkte Dateioperationen aktualisieren auch betroffene inaktive Tabs; virtuelle Ergebnisse werden als veraltet gekennzeichnet und als Operationsquelle gesperrt. Dialogsperre und Scrollen zum Cursor sind vereinheitlicht. Verzögerter Drop und vollständiger Job-/Dialoglebenszyklus brauchen zusätzliche Abnahme.
- **5G teilweise umgesetzt:** Sitzungsformat v2 stellt alle echten Tabs, aktive Tabs/Panel, Sortierung und Filter wieder her und migriert das alte Format. Shift-Bereichsauswahl funktioniert per Pfeiltaste und Klick. Fehlende Verzeichnisse werden übersprungen; eine eigene Meldung für nicht verfügbare Volumes bleibt offen. Performance, externe Änderungen, Accessibility und CI sind noch ausstehend.
- **Oberfläche und Icon:** Klare Quelle-/Zielbeschriftung, kompaktere Zeilen, beobachtete Auswahlstatusanzeige und überarbeitete Funktionsleiste sind eingebunden. Der neue Assetsatz `CommanderIcon` enthält alle zehn macOS-Größen und wird in Debug und Release verwendet. [Design und Generierung](docs/design/app-icon.md); abschließende Dock-/Finder-/Kontrastprüfung vor Veröffentlichung offen.
- **Viewer-Suche umgesetzt:** Native Suche und Treffernavigation in der geladenen Text-/Hexvorschau. Die vorhandene Vorschaugrenze bleibt bestehen; dies ist keine Suche durch eine komplette große Datei.

Die danach umgesetzten Sicherheitskorrekturen schließen die konkreten reproduzierten Fehlerpfade F01–F05. Die Release-Freigabe folgt erst nach den ergänzenden Ausfall-/Dateisystemprüfungen und den übrigen Qualitäts- und Distributionsabnahmen. Der aktuelle vollständige Prüfstand steht im [Sicherheitsnachweis](docs/progress/2026-10-14-sicherheit-dateioperationen.md).

#### Abnahme von 5A

- F08 schließen: gemeinsame Testkonfiguration für Unit-Testhost und alle UI-Starts; eigene temporäre Wurzel und eigener Settings-Store, einschließlich `@AppStorage`.
- Start ohne vollständige Testkonfiguration darf keine echten Favoriten, Sitzung oder Home-Verzeichnisse verwenden.
- Vorgegebenen Debug-Build, 43 bestehende Unit-/Integrationstests und die UI-Suite ausführen; Abweichungen als konkrete Regressionen erfassen. Testanzahlen wachsen mit den folgenden Korrekturen.
- Keine automatisierte Annahme von Lizenzbedingungen; der frühere Umgebungsblocker wurde am 14. Oktober durch den Betreiber beseitigt.

#### Abnahme von 5B bis 5D

- F01–F05 schließen: kein stiller Verlust von zugesagten Metadaten, keine Entfernung eines inzwischen fremden Ziels, keine ZIP-Extraktion außerhalb des Zielbereichs.
- Für jeden mutierenden Pfad Erfolg, Zielkonflikt, Abbruch und mindestens einen Teilfehler testen. Fehler gezielt injizieren statt zeitkritische Zufallsrennen zu verwenden.
- Rename-Tests müssen auch fehlschlagende Wiederherstellung und tatsächlich verbleibende Dateipfade prüfen.
- Archive nicht direkt in endgültige Ziele schreiben; Archivnamen und als Programmoption interpretierbare Dateinamen validieren bzw. als Operanden behandeln. Entpackgröße und Eintragsanzahl begrenzen.
- Alle mutierenden Werkzeuge in die Jobverwaltung einbeziehen. Berichte pro Job erhalten; Beenden bei laufender Mutation kontrollieren. Einträge nach unerwartetem Abbruch erkennbar und wiederherstellbar halten.
- Signierte lokale App für Lifecycle-/Dateizugriffsänderungen prüfen. Erst dann ist der Sicherheitsmeilenstein erreicht.

#### Abnahme von 5E und 5F

- F06/F09: Tab am gleichen Pfad, Wechsel mit Pfeilen/Enter, Schließen vor dem aktiven Tab, Modaldialoge, verzögerter Drop und Operation bei Tabwechsel per gezielten UI-/Unit-Tests prüfen.
- Quelle und Ziel werden beim Benutzerauftrag eingefroren. Fertige Operationen aktualisieren betroffene echte Tabs und behandeln virtuelle Ergebnisse ausdrücklich als aktualisiert oder veraltet.
- F07: Metadatengleichheit nicht als Inhaltsidentität bezeichnen. Rekursive Vorschau zeigt relative Pfade und konkrete Aktionen; gleiche Dateigröße/Zeit mit anderem Inhalt testen. Keine automatische Löschsynchronisation.
- F10: Suchlimits und unlesbare Teilbäume werden im Ergebnis ausgewiesen. Prozesse begrenzen Ausgabe und besitzen getestete Abbruch-/Fehlerpfade.

#### Abnahme von 5G und 5H

- Sitzungsformat versionieren und alle echten Tabs mit aktivem Tab, Sortierung und Filter wiederherstellen; fehlende Volumes verständlich behandeln. Keine automatische Wiederaufnahme mutierender Jobs.
- Shift-Bereichsauswahl und gebündelte Aktualisierung nach externen Änderungen ergänzen, sobald Tab- und Fokusregressionen geschlossen sind.
- Reproduzierbare Fixtures mit 1.000/10.000/100.000 Einträgen; Referenzgerät und Messmethode protokollieren. Vorläufige Ziele: p95 unter 100 ms für Cursor/Panelwechsel/Filter bei 10.000 Einträgen, unter 1 s bis Abbruchreaktion einer lokalen blockweisen Kopie. Grenzen langsamer Volumes separat dokumentieren.
- VoiceOver, Tastatur ohne Maus, Hell/Dunkel/hoher Kontrast und kleine Fenster manuell abnehmen. UI-Tests decken die kritischen Fokuspfade ab.
- CI baut und testet auf macOS; UI-Tests benötigen eine geeignete angemeldete Testsitzung. Vollständige Resultate aufbewahren und fehlgeschlagene Prüfungen nicht als bestanden werten.
- Release-Konfiguration, Hardened Runtime, Developer-ID, Notarisierung, frische Installation, Neustart und Upgrade prüfen. Sandbox-Modell bleibt gemäß ADR 0001 bestehen.
- P1/P2-Befunde schließen oder Funktionsumfang ausdrücklich reduzieren und dokumentieren; bekannte Datenverlustpfade sind kein akzeptabler Release-Restpunkt.

### Bewusste Begrenzung des Releases

Netzwerkprotokolle, Plugin-System, bidirektionale Synchronisation, automatische Löschspiegelung, persistente Operationswiederaufnahme und ein beschreibbares Archivdateisystem sind keine Voraussetzungen für 1.0. „Öffnen mit“ und Favoriten-Import/Export folgen nach der Kernabnahme. Die Suche innerhalb der Viewer-Vorschau ist seit dem 14. Oktober vorhanden. Diese Begrenzung schützt die bestehenden Prioritäten vor weiterem Funktionswachstum.

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
- App-Icon abschließend in Dock/Finder prüfen (Assetsatz seit 14. Oktober integriert), Versionsnummern und Release Notes;
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
| `0.2.0` | Power Tools | Vorhandener Funktionsstand; Abnahmelücken dokumentiert |
| `0.2.1` vorgeschlagen | Sichere Operationen | 5A–5D abgenommen |
| `0.3.0` vorgeschlagen | Verlässliche Bedienung | 5E–5F abgenommen |
| `0.9.0` vorgeschlagen | Release-Kandidat | 5G abgenommen; Distributionsprüfung läuft |
| `1.0.0` | Stable Release | 5H und sämtliche Release-Kriterien erfüllt |

## Kritischer Pfad

```text
Isolierte und ausführbare Tests
    ↓
Metadaten und Schutz konkurrierender Ziele
    ↓
Archive, Rollback und Job-Lebenszyklus
    ↓
Tabidentität, Fokus und verlässliche Vorschauen
    ↓
Performance und Barrierefreiheit
    ↓
Signierter und notarisierter Release
```

Suche, Archive oder Tabs sollten nicht vorgezogen werden, solange Quelle und Ziel einer Dateioperation noch verwechselt werden können.

## Pflege des Plans

- Beim Start einer Stufe offene Aufgaben in konkrete, kleine Issues zerlegen.
- Aufgaben erst als abgeschlossen betrachten, wenn die jeweiligen Abnahmekriterien erfüllt sind.
- Neue Anforderungen einer Stufe und Priorität zuordnen, statt sie ungeplant in den aktuellen Umbau einzuschieben.
- Abweichungen, Architekturentscheidungen und geänderte Meilensteine in diesem Dokument und gegebenenfalls in der Root-[`README.md`](README.md) aktualisieren.
