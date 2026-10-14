# Projektbewertung und Zielprüfung

Stand: 9. Oktober 2026. Bewerteter Code: `bb20071e86a0b1014a88212d2a63d2bafa195394`.

DumbCommander besitzt eine tragfähige Grundarchitektur und einen breiten Funktionsumfang. Für eine Freigabe als verlässlicher Alltagsdateimanager fehlen jedoch Sicherheits- und Bediennachweise; mehrere konkrete Implementierungslücken betreffen die höchsten Projektprioritäten. Die bisherige Aussage „Stufen 0 bis 4 abgeschlossen“ beschreibt den Funktionsausbau, aber keine vollständige Erfüllung der Abnahmekriterien.

Die Produktziele bleiben sinnvoll: ein nativer macOS-Commander mit zwei unabhängigen Panels, tastaturbasierter Bedienung und vorhersehbaren Dateioperationen. Der nächste Entwicklungsschritt ist die Absicherung des vorhandenen Umfangs. Der verbindliche weitere Ablauf steht in der [Roadmap](../../ROADMAP.md#umsetzungsplan-nach-der-projektprüfung).

## Bewertungsgrundlage

Geprüft wurden Root-README, Roadmap, ADRs, Arbeitsnachweise, Xcode-Konfiguration, Zustandsmodell, Operationskern, Power Tools sowie relevante UI- und Testpfade. Der Working Tree war vor der Prüfung sauber. Diese Änderung ergänzt Dokumentation und Planung; sie behebt die unten aufgeführten Programmfehler noch nicht.

Die Nachweisarten sind bewusst getrennt:

- **Im Code belegt:** Ein konkreter Ausführungspfad oder eine fehlende Absicherung ist nachvollziehbar. Die Auswirkung in der laufenden App benötigt gegebenenfalls einen Regressionstest.
- **Im Experiment bestätigt:** Das benannte Verhalten wurde lokal mit isolierten Testdaten ausgeführt.
- **Offen:** Laufzeit-, Performance-, Accessibility- oder Distributionsnachweise fehlen aktuell.

## Abgleich mit den gesetzten Zielen

| Ziel | Bewertung | Begründung und nächster Nachweis |
| --- | --- | --- |
| Datensicherheit | Nicht vollständig erfüllt | Konfliktmodell, temporärer Ersatz und Papierkorb ohne Lösch-Fallback sind vorhanden. F01 bis F05 erfordern Nacharbeit vor Freigabe. |
| Trennung von Quelle und Ziel | Im Modell gut, an UI-Grenzen unvollständig | Jeder Tab besitzt `PanelState`; direkte Transfers verwenden aktive Quelle und Gegenseite. Tabidentität, verzögerte Eingaben und Aktualisierung brauchen F06. |
| Vollständige Tastaturbedienung | Teilweise erfüllt | Registry und AppKit-Brücke existieren. Tabwechsel, Dialoge und Cursor außerhalb des sichtbaren Ausschnitts sind nicht ausreichend abgesichert; siehe F06/F09. |
| Responsivität | Gute Basis, nicht abgenommen | Actors und blockweises Kopieren sind vorhanden. Sortierung und Vorschauprüfungen laufen teilweise im UI-Pfad; belastbare Messungen fehlen. |
| Erweiterte Commander-Funktionen | Breit implementiert, unterschiedliche Reife | Tabs, Suche, Viewer, Archive und Umbenennung existieren. Vergleich ist flach und metadatenbasiert, Archivnavigation ein Dialog. |
| macOS und Distribution | Konfiguration entspricht dem ADR, Auslieferung offen | macOS 14, Swift 5, Sandbox aus und Hardened Runtime an sind für die App konfiguriert. Developer-ID-, Notarisierungs- und Installationsnachweise fehlen. |
| Testbarkeit | Gute Grundlage mit Lücken | 43 Unit-/Integrationstestmethoden und 14 UI-Testmethoden im Quelltext; elf davon gezielte UI-Regressionen, zusätzlich Beispiel-, Start- und Startperformancetest. Testisolation ist nicht durchgängig. |

Ein pauschaler Prozentwert wäre irreführend: Viele Funktionen sind vorhanden, während einzelne noch offene Sicherheitsbedingungen eine Freigabe verhindern.

## Stärken der vorhandenen Umsetzung

- `PanelState`, `CommanderState`, `FileItem`, `FileSystemServing`, `FileOperationCoordinator` und `CommandRegistry` entsprechen weitgehend der geplanten Architektur. Ein grundlegender Rewrite ist nicht nötig.
- Direkte Dateioperationen trennen Planung, Konfliktentscheidung und Ausführung. Teilergebnisse werden pro Element modelliert; die Konfliktentscheidungen sind explizit.
- Reguläre Kopien arbeiten blockweise; Symlinks werden im Operationskern als eigene Einträge behandelt. Bewusstes Öffnen verwendet einen separaten, begrenzten Auflösungspfad.
- Veraltete Verzeichnisladeergebnisse werden durch Generationen verworfen. Die Auswahl verwendet URLs statt Listenindizes.
- Die vorhandenen Integrationstests enthalten wertvolle Fehlerfälle: Papierkorbfehler, fehlende Quellen, Konflikte, Berechtigungen, Abbruch und simulierten Volume-Wechsel.
- Architekturentscheidungen und historische Arbeitsnachweise sind vorhanden. Das erleichtert gezielte Korrekturen ohne Neuinterpretation des Produktauftrags.

## Priorisierte Befunde

P1 bezeichnet eine Sperre für die Freigabe als verlässlicher Dateimanager, P2 eine notwendige Korrektur für den vollständigen Zielumfang. Die Einstufung ist eine Projektpriorität, keine Behauptung, dass jeder Fehler bereits im Alltag aufgetreten ist.

### F01 ZIP kann über einen vorhandenen Link das Zielverzeichnis verlassen

**P1, im Experiment bestätigt.** [PowerTools.swift](../../DumbCommander/PowerTools.swift), `ArchiveService.extract`, Zeilen 578–606.

Die Vorprüfung betrachtet die Namen im Archiv und die Existenz des vollständigen Zielpfads. Ein bereits vorhandener symbolischer Link in einer Zwischenkomponente wird nicht abgewiesen. Für `bridge/new.txt` kann die Prüfung deshalb „Ziel fehlt“ ergeben, obwohl `bridge` in ein anderes Verzeichnis zeigt. Anschließend schreibt `ditto -x -k` durch diesen Link.

Das isolierte Experiment erzeugte unter einem neuen Testwurzelverzeichnis ein Ziel, ein Geschwisterverzeichnis und `destination/bridge → sibling`. Das ZIP enthielt ausschließlich `bridge/new.txt`. Der verwendete `ditto`-Aufruf beendete sich mit Status 0 und erzeugte `sibling/new.txt`. Der entsprechende TAR-Aufruf verweigerte die Extraktion mit Status 1. Keine Testdatei lag außerhalb dieser Testwurzel. Das Experiment prüft den tatsächlich verwendeten Systemaufruf, nicht einen ausgeführten XCTest gegen den Swift-Dienst.

**Abnahme:** ZIP und TAR prüfen Eintragstypen, Linkziele, sämtliche Pfadkomponenten, doppelte Namen und Zielkollisionen. Extraktion erfolgt in einem isolierten Bereich mit abgesichertem Entpacker; ein temporäres Verzeichnis allein ist kein Traversalschutz. Erst validierte Ergebnisse werden nach gemeinsamer Konfliktsemantik übernommen. Tests enthalten vorhandene Zwischenlinks, defekte Links, Archivlinks, absolute/aufsteigende Pfade und Fehler nach teilweiser Extraktion. Ein Wächterverzeichnis innerhalb der Testwurzel, aber außerhalb des Extraktionsziels, bleibt unverändert.

### F02 Kopieren erhält macOS Metadaten nicht vollständig

**P1, im Code belegt.** [FileSystemService.swift](../../DumbCommander/FileSystemService.swift), `copyEntry` ab Zeile 538 und `copyAttributes` ab Zeile 704.

Die Kopie erzeugt eine neue Datei und überträgt den Datenstrom. Anschließend werden nur POSIX-Rechte, Änderungs- und Erstellungsdatum übernommen. Ein Pfad für Extended Attributes, Resource Forks und ACLs fehlt. Das betrifft beispielsweise Finder-Metadaten und zusätzliche Dateiinhalte. Beim Verschieben mit Ersetzen oder über den EXDEV-Fallback wird nach diesem Kopierpfad die Quelle entfernt.

**Abnahme:** Eine dokumentierte Metadatenpolitik legt fest, was verlustfrei erhalten bleiben muss und wie nicht unterstützende Zielvolumes behandelt werden. Quelle erst nach erfolgreicher Übertragung aller zugesagten Bestandteile entfernen. Tests prüfen Inhalt, xattrs, Resource Fork und ACLs sowie Fehler beim Metadatenübertrag. Reale Volume-Tests ergänzen den vorhandenen simulierten EXDEV-Test.

### F03 Zielprüfung und Bereinigung sind nicht gegen konkurrierende Änderungen abgesichert

**P1, im Code belegt.** [FileSystemService.swift](../../DumbCommander/FileSystemService.swift), `copyWithPolicy` Zeilen 420–460, `moveWithPolicy` ab Zeile 464 und Dateierzeugung ab Zeile 574.

Zwischen Existenzprüfung und Anlage des Ziels kann ein anderer Prozess dasselbe Ziel erstellen. Der Fehlerpfad entfernt anschließend `destination`, ohne nachzuweisen, dass dieses Objekt durch die eigene Operation angelegt wurde. Bei einem inzwischen entstandenen Verzeichnis kann schon die fehlgeschlagene Verzeichnisanlage zur Entfernung dieses fremden Ziels führen. Die zusätzliche Bereinigung im EXDEV-Fehlerpfad besitzt dieselbe Schwäche. Existenzfehler werden außerdem mehrfach mit `try?` wie „nicht vorhanden“ behandelt.

**Abnahme:** Neue Ziele exklusiv anlegen bzw. eigene temporäre Ergebnisse ohne implizites Ersetzen veröffentlichen. Bereinigung nur für nachweislich eigene Objekte. Zugriffsfehler von „nicht gefunden“ unterscheiden. Vor der Mutation Quelle/Ziel und freigegebenen Konflikt erneut gegen Änderungen prüfen; Pfadidentität und Groß-/Kleinschreibung berücksichtigen. Deterministische Tests erzeugen zwischen Prüfung und Mutation ein Ziel und belegen, dass es unverändert bleibt. Spezialdateien wie FIFOs dürfen nicht wie reguläre Dateien blockierend kopiert werden.

### F04 Mehrfachumbenennung verschluckt Wiederherstellungsfehler

**P1, im Code belegt.** [PowerTools.swift](../../DumbCommander/PowerTools.swift), `BatchRenameService.execute` ab Zeile 250 und `rollback` ab Zeile 318.

Nach Teilfehlern wird zurückgerollt, aber jede fehlgeschlagene Rückumbenennung durch `try?` verworfen. Das Ergebnis enthält dann keine Zuordnung zu noch vorhandenen temporären Namen. Bei Task-Abbruch läuft die Wiederherstellung im bereits abgebrochenen Task; der reale Dateisystemdienst prüft bei jedem Rename erneut auf Abbruch. Zusätzlich kann direktes Rückbenennen bei Namensketten oder Zyklen an noch belegten Originalnamen scheitern.

**Abnahme:** Abbruchfeste Wiederherstellung mit separater temporärer Phase, strukturiertem Ergebnis pro Datei und Angabe des tatsächlichen verbliebenen Pfads. Fehler in jeder Phase, Zyklen, nachträglich belegte Namen, Case-only-Rename und Undo testen. Die UI muss auch nach Teilfehlern aktualisiert werden und Wiederherstellung ermöglichen.

### F05 Lange Werkzeuge und das Beenden besitzen keinen einheitlichen Lebenszyklus

**P1, im Code belegt.** [PowerToolsViews.swift](../../DumbCommander/PowerToolsViews.swift), `BatchRenameView` und `ArchiveToolView`; [ContentView.swift](../../DumbCommander/ContentView.swift), `handleQuit` Zeile 512; [FileOperationCoordinator.swift](../../DumbCommander/FileOperationCoordinator.swift), `FileOperationViewModel` ab Zeile 695.

Archivaktionen starten eigene Tasks außerhalb der Operationswarteschlange. Ihre Startbuttons bleiben während der Ausführung bedienbar, die Tasks werden nicht für Abbruch oder Dialogschließen verwaltet. Mehrfachumbenennung besitzt ebenfalls keinen durchgängigen Abbruchpfad in der Oberfläche. F10 beendet die App unmittelbar; ein zentraler Beendigungsschutz für laufende Mutationen ist nicht vorhanden. Beim nächsten Warteschlangeneintrag wird der vorherige Bericht wieder gelöscht.

**Abnahme:** Gemeinsame Verwaltung aller mutierenden Jobs, sichtbarer Fortschritt/Abbruch, Schutz vor Mehrfachstart und pro Job erhaltener Bericht. Für F10, Cmd-Q und Fensterende einheitlich zwischen Warten, kontrolliertem Abbruch und Weiterarbeiten entscheiden. Für unerwartete Beendigung einen nachvollziehbaren Umgang mit temporären Dateien festlegen. Eine persistente Warteschlange ist dafür noch nicht erforderlich. Lifecycle-Änderungen zusätzlich in einer signierten App prüfen.

### F06 Tabwechsel und verzögerte Aktionen sind nicht vollständig an Panelidentitäten gebunden

**P1, im Code belegt; UI-Auswirkungen noch auszuführen.** [FileListView.swift](../../DumbCommander/FileListView.swift), `reloadID` Zeile 56, Drop-Callback Zeile 154, `ReloadID` Zeile 716; [KeyEventHandlingView.swift](../../DumbCommander/KeyEventHandlingView.swift), Zeilen 17–28; [ContentView.swift](../../DumbCommander/ContentView.swift), `refreshPanels` Zeile 281.

`ReloadID` enthält den Pfad, aber keine Tab-ID. Ein neuer Tab am selben Pfad ändert damit die Task-ID nicht. Der Eventmonitor hält den beim Anlegen übergebenen Handler; `updateNSView` aktualisiert ihn nicht auf den neuen PanelState. Nach einer Operation werden nur die inzwischen ausgewählten Tabs neu geladen; virtuelle Ergebnisse werden generell nicht aktualisiert. Der Drop-Callback liest das Zielverzeichnis erst nach dem asynchronen Laden des Providers. Navigation währenddessen kann das Ablageziel verändern.

Daneben verschiebt `closeTab` den ausgewählten Index nicht korrekt, wenn ein weiter links liegender Tab geschlossen wird und rechts noch Tabs folgen. Beispiel: B ist in A/B/C aktiv, A wird geschlossen; danach wird C aktiv.

**Abnahme:** Lade- und Eingabeidentität an `PanelState.id` binden, Handler aktuell halten, Drop-Ziel bei Annahme einfrieren und die betroffenen Tabs über Identität/Pfad aktualisieren oder als veraltet markieren. Tests: Cmd-T am selben Pfad zeigt Dateien; Pfeile und Enter betreffen nach Tabwechsel den sichtbaren Tab; Hintergrundoperation plus Tabwechsel; virtuelle Ergebnisse nach Verschieben; verzögerter Drop; Schließen eines Tabs vor dem aktiven Tab.

### F07 Vergleich und Synchronisation erfüllen nur einen begrenzten Umfang

**P2, im Code belegt.** [PowerTools.swift](../../DumbCommander/PowerTools.swift), `DirectoryComparisonService` Zeilen 111–155; [PowerToolsViews.swift](../../DumbCommander/PowerToolsViews.swift), `DirectoryComparisonView`.

Verglichen wird nur die oberste Ebene anhand von Typ, Größe und Änderungszeit. „Identisch“ bezeichnet somit keine Inhaltsgleichheit. Unterschiede tief in gleichnamigen Verzeichnisbäumen werden nicht zuverlässig ermittelt. Die Synchronisation kopiert die daraus abgeleiteten Einträge über den normalen Coordinator, besitzt aber keine rekursive Vorschau einzelner Aktionen. Die ID `name.lowercased()` ist für zwei getrennte Namen auf einem case-sensitiven Volume nicht eindeutig.

**Abnahme:** Metadatenvergleich korrekt benennen und rekursiven Vergleich mit relativen Pfaden ergänzen. Optionaler Inhaltsvergleich darf gleiche Größe/Zeit nicht als Beweis verwenden. Vorschau zeigt Richtung, Aktion und Konflikt pro Eintrag; verschachtelte Änderungen sind sichtbar. Zunächst einseitige Synchronisation ohne automatische Löschungen. Bidirektionaler Abgleich und Spiegeln mit Löschen benötigen später eine ausdrückliche Produktentscheidung.

### F08 Testisolation und heutiger Buildnachweis fehlen

**P1 für die Prüfgrundlage, im Code belegt.** [DumbCommanderUITests.swift](../../DumbCommanderUITests/DumbCommanderUITests.swift), `makeApp`; [DumbCommanderUITestsLaunchTests.swift](../../DumbCommanderUITests/DumbCommanderUITestsLaunchTests.swift), `testLaunch`; [DumbCommanderApp.swift](../../DumbCommander/DumbCommanderApp.swift), Initialisierung und `@AppStorage`.

Mehrere UI-Tests starten ohne eigenes Verzeichnis; die App fällt auf das echte Benutzerverzeichnis zurück. Der separate Starttest setzt nicht einmal den UI-Testmodus und aktiviert damit die normale Favoriten-/Sitzungslogik. `@AppStorage` verwendet auch im UI-Testmodus weiterhin den Standard-Store. Die Unit-Tests besitzen einen App-Testhost, dessen Initialisierung deshalb ebenfalls zur Testisolation gehört. Die pauschale Aussage, die gesamte Suite berühre keine echten Benutzereinstellungen, ist nicht abgesichert.

**Abnahme:** Jede Test-App erhält eine eigene temporäre Wurzel und einen eigenen Settings-Store; sämtliche `@AppStorage`-Zugriffe und der Testhost sind einbezogen. Fehlende Testkonfiguration darf nicht auf echte Benutzerdaten zurückfallen. Danach frischer Debug-Build und vollständige relevante Suite mit Ergebnisprotokoll. CI benötigt ein geteiltes Scheme, festgelegte Xcode-Version und archivierte Testresultate; ein Workflow ist im bewerteten Repository nicht vorhanden.

### F09 Fokus und Performance sind noch keine abgeschlossenen Qualitätsziele

**P2, teilweise im Code belegt, Messungen offen.** [FileListView.swift](../../DumbCommander/FileListView.swift), `handleKeyEvent` ab Zeile 480; [CommanderState.swift](../../DumbCommander/CommanderState.swift), `visibleItems`, `moveCursor`, `apply`; [PowerToolsViews.swift](../../DumbCommander/PowerToolsViews.swift), `BatchRenameView.previews`.

Der Panel-Keyhandler berücksichtigt die globale Dialogsperre nicht; ein TextView-Check allein deckt fokussierte Buttons und andere Dialogelemente nicht ab. Eine explizite Scrollführung für den programmgesteuerten Cursor fehlt. Filtern und Erzeugen der Cursorliste erfolgen wiederholt, Sortieren auf dem Main Actor. Die Umbenennungsvorschau fragt das Dateisystem synchron aus dem View-Pfad ab. `ContentView` mit 1.214 und `FileListView` mit 979 Zeilen bleiben stark gekoppelte Integrationsstellen.

**Abnahme:** Fokusrouting für Dialoge und Fenster absichern, Cursor sichtbar halten, danach Messungen mit 1.000/10.000/100.000 Einträgen. Vorschauprüfung und große Sortierarbeit aus dem Main Actor lösen, soweit Messungen bzw. blockierende Zugriffe es verlangen. Views schrittweise nach Verantwortung aufteilen, zusammen mit passenden Verhaltenstests. VoiceOver, hoher Kontrast und reine Tastaturbedienung erhalten eine manuelle Abnahmematrix.

### F10 Suche und Prozessausgabe benötigen belastbare Grenzen und Teilergebnisse

**P2, im Code belegt.** [PowerTools.swift](../../DumbCommander/PowerTools.swift), `FileSearchService` Zeilen 25–67 und `CommandRunner` Zeilen 499–535.

Ein einzelnes unlesbares Verzeichnis oder ein Lesefehler beendet die gesamte Suche. Beim Erreichen von 10.000 Treffern wird eine normale Ergebnisliste ohne Kennzeichnung der Unvollständigkeit zurückgegeben. `CommandRunner` sammelt stdout/stderr vollständig im Speicher. Abbruch signalisiert nur dem gestarteten Prozess die Beendigung; eine Grenze für Laufzeit/Ausgabe oder ein Modell für weiterlaufende Kindprozesse fehlt.

**Abnahme:** Suchbericht mit Treffern, übersprungenen Orten, Fehlern und Abbruch-/Limitstatus. Grenzfälle deterministisch testen. Prozessausgabe begrenzen oder streamen, abgebrochene Ergebnisse eindeutig kennzeichnen und Beendigung einschließlich relevanter Kindprozesse testen. Programm/Argumente bleiben getrennt; keine Shell-Auswertung einführen.

## Sinnvolle Ergänzungen des Zielbilds

| Ergänzung | Nutzen | Einordnung |
| --- | --- | --- |
| Erhalt von Metadaten als explizite Zusage | Verhindert unbemerkten Verlust beim Kopieren und Verschieben | Pflicht vor Freigabe, F02 |
| Aufbewahrte Operationsberichte und Wiederherstellungshinweise | Macht Teilfehler und unterbrochene Jobs nachvollziehbar | Pflicht vor Freigabe, F04/F05 |
| Alle echten Tabs und deren Einstellungen wiederherstellen | Entspricht dem inzwischen eingeführten Tabmodell | Nach Sicherheitskorrekturen; versioniertes Sitzungsformat, Suchergebnisse nicht blind als aktuell wiederherstellen |
| Shift-Bereichsauswahl und sichtbarer Tastaturcursor | Schließt eine alltägliche Commander-Lücke | Bedienphase, vor neuen Spezialwerkzeugen |
| Änderungen im Verzeichnis erkennen | Vermeidet veraltete Ansichten nach Finder-/Editoraktionen | Nach korrekter gezielter Aktualisierung; Ereignisse bündeln und Auswahl erhalten |
| Aussagekräftige unvollständige Suchergebnisse | Verhindert falsche Schlussfolgerungen aus Grenzen/Berechtigungsfehlern | F10 |
| Messbare Qualitätsbudgets | Macht „schnell“ und „bedienbar“ überprüfbar | Referenzgerät und Fixtures festlegen; vorläufig p95 unter 100 ms für Panelwechsel/Cursor/Filter bei 10.000 Einträgen und unter 1 s bis Abbruchreaktion bei lokaler blockweiser Kopie |

Diese Leistungswerte sind vorgeschlagene Abnahmeziele, keine gemessenen Eigenschaften. Langsame oder nicht mehr reagierende Volumes separat ausweisen; Betriebssystem-I/O kann andere Abbruchgrenzen haben.

Netzwerkprotokolle, Plugins, bidirektionale Synchronisation, vollständiges Archivdateisystem, persistente Jobwiederaufnahme und allgemeines Undo bleiben außerhalb des ersten stabilen Releases. Sie erweitern die Sicherheitssemantik erheblich und sollten erst nach stabilen Kernpfaden priorisiert werden. Viewer-Suche, „Öffnen mit“ und Favoriten-Import/Export sind sinnvolle spätere Komfortergänzungen.

## Aktueller Prüfstatus

| Prüfung | Ergebnis am 9. Oktober 2026 |
| --- | --- |
| Repository und Zielkonfiguration | Statisch geprüft; keine vorgefundenen Working-Tree-Änderungen |
| Dokumentation | Lokale Verweise und Überschriftenanker geprüft; Diff ohne Whitespacefehler |
| Vorgegebener unsignierter Debug-Build | Aufgerufen, vor Kompilierung mit Exit-Code 69 an nicht akzeptierten Xcode-Lizenzbedingungen gestoppt |
| `build-for-testing` für das macOS-Scheme | Aufgerufen, derselbe Lizenzfehler; Testtargets heute nicht neu kompiliert |
| Unit-/Integrationstests und UI-Tests | Heute nicht ausgeführt; Lizenzblockade und zusätzlich zu behebende Testisolation |
| ZIP-/TAR-Zwischenlinkexperiment | ZIP schreibt über den Link; TAR verweigert denselben Fall; temporäre Fixture vollständig entfernt |
| Signierte App, reale externe Volumes, VoiceOver, Lastmessungen, Notarisierung | Heute nicht geprüft |

Die lokalen Buildlogs liegen unter `/tmp/DumbCommander-audit-build.log` und `/tmp/DumbCommander-audit-test-build.log` und sind keine dauerhaft eingecheckten Nachweise. Xcode muss durch den Betreiber geöffnet und die Lizenz geprüft/akzeptiert werden; das wurde nicht automatisiert vorgenommen. Danach beginnt die Umsetzung mit isolierter Testkonfiguration, Regressionstests für die Befunde und erneuten Builds. Historische Erfolgsmeldungen vom 1. September ersetzen diesen aktuellen Nachweis nicht.
