# Bedienung, Oberfläche und App-Icon

Stand: 14. Oktober 2026. Ergänzt die [Projektbewertung vom 9. Oktober](2026-10-09-projektbewertung.md); deren Sicherheitsbefunde bleiben gültig, soweit hier nicht ausdrücklich bearbeitet.

## Umgesetzte Features

- **Tab-Sitzungen:** Versioniertes Format v2 speichert alle echten Tabs beider Panels, den jeweils aktiven Tab, das aktive Panel, Sortierung und Filter. Das alte Format wird migriert. Fehlende Verzeichnisse werden übersprungen, Pfadlinks kontrolliert aufgelöst. Suchergebnisse werden nicht persistiert. Benutzeraktionen während der asynchronen Wiederherstellung haben Vorrang; mutierende Jobs werden nicht wiederaufgenommen.
- **Bereichsauswahl:** Shift mit Pfeiltasten oder Klick markiert den Bereich in der aktuell sichtbaren Reihenfolge. Zurückbewegen verkleinert den Bereich; vorher unabhängig gesetzte Markierungen bleiben erhalten. Die Auswahl ist weiterhin an ihren Panel-Tab gebunden.
- **Viewer-Suche:** Text- und Hexvorschau verwenden einen nativen, schreibgeschützten Textbereich mit Suchleiste. Command-F öffnet die Suche, Command-G bzw. Command-Shift-G wechseln Treffer. Gesucht wird ausschließlich in der bereits geladenen, begrenzten Vorschau.
- **Oberfläche:** Arbeitsbereichskopf mit Suche, Vergleich und Archiven, explizite Quelle-/Zielkennzeichnung, kompaktere Dateizeilen, getrennte Cursor-/Markierungssymbole und Funktionsleiste mit sichtbaren Tastenkappen. Die Auswahlstatusanzeige beobachtet den ausgewählten Panelzustand direkt.
- **App-Icon:** Neues Zweipanelmotiv mit Transferpfeil, eingebunden als `CommanderIcon` in beiden Buildkonfigurationen. Alle zehn macOS-Größen sind enthalten. [Design, Herkunft und Prompt](../design/app-icon.md).

## Begleitende Korrekturen

Tabidentität ist Bestandteil des Ladetriggers; der AppKit-Keyhandler übernimmt aktualisierte Closures und behandelt nur Ereignisse seines aktiven Fensters. Dadurch bleiben neue Tabs am gleichen Pfad ladbar und Pfeile/Enter erreichen den richtigen Tab. Das Schließen eines Tabs vor dem aktiven Tab erhält dessen Identität. Navigation entfernt alte Zeilen sofort, bevor neue Ergebnisse eintreffen.

Drop-Ziele werden vor dem asynchronen Lesen der angebotenen URLs festgelegt. Nach direkten Dateioperationen werden betroffene echte Tabs einschließlich inaktiver Tabs aktualisiert. Virtuelle Suchergebnisse werden vorsorglich als veraltet gekennzeichnet; sie liefern dann keine Operationsquellen, bis erneut gesucht wird. Die globale Dialogsperre gilt auch für Panel-Keyhandler, Toolbar und Funktionsleiste.

Die Test-App nutzt einen eigenen Settings-Store und eine isolierte Wurzel. Das gilt für Favoriten, Sitzungen und alle `@AppStorage`-Zugriffe. Fehlt einem App-hosted Unit-Test eine explizite Wurzel, wird eine neue temporäre Wurzel erzeugt. UI-Tests konfigurieren Wurzel und Suite vor jedem Start; der Neustarttest verwendet bewusst dieselbe Testsuite innerhalb seines Tests. Ein geteiltes Scheme ist im Repository enthalten.

## Prüfungen

Nach Annahme der Xcode-Lizenz durch den Betreiber wurden ausgeführt:

- macOS-Debug-Build gemäß Root-README mit `CODE_SIGNING_ALLOWED=NO`: erfolgreich;
- vollständige Suite mit lokaler Ad-hoc-Signierung: **53 Unit-/Integrationstests und 19 UI-Testausführungen, null Fehler**;
- die UI-Suite umfasst 17 Haupttests und einen Launchtest in zwei Konfigurationen;
- Signaturprüfung der lokalen Test-App mit `codesign --verify --deep --strict`: erfolgreich;
- manuelle Sichtprüfung des laufenden Fensters im dunklen Erscheinungsbild mit ausschließlich eigens erzeugten Beispieldateien;
- `git diff --check`: erfolgreich.

Neue Regressionstests decken unter anderem Sitzungsmigration und Wiederherstellung aller Tabs, fehlende Verzeichnisse, Ausschluss virtueller Tabs, Tabidentität beim Schließen, Bereichsauswahl, Aktualisierung inaktiver Tabs, veraltete Suchergebnisse und das sofortige Entfernen alter Navigationszeilen ab. Neue UI-Tests prüfen Tabs am gleichen Pfad, panelgetrennte Shift-Auswahl, native Viewer-Suche ohne Eingriff von F7 sowie Sitzungen nach einem echten App-Neustart.

Im ersten vollständigen Lauf waren drei neue UI-Tests wegen mehrdeutiger Accessibility-Selektoren fehlgeschlagen. Nach Präzisierung der Selektoren wurde die gesamte Suite erneut erfolgreich ausgeführt. Lokale Resultate: `build/Tests-20261014-2.xcresult`; diese Buildprodukte bleiben unversioniert. Xcode meldet lediglich, dass ohne AppIntents-Abhängigkeit keine entsprechenden Metadaten extrahiert werden.

Eine abschließende kleine Korrektur aktiviert beim Klick auf „Erneut suchen“ ausdrücklich das betreffende Panel vor dem Suchauftrag. Danach wurden der Debug-Build, die Signaturprüfung und der gezielte UI-Test `testPanelTabAndSearchShortcuts` erneut erfolgreich ausgeführt.

Reproduzierbarer Testbefehl:

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

## Verbleibende Grenzen

Der Stand ist keine Release-Freigabe. Die Befunde zu Metadatenerhalt, konkurrierenden Zieländerungen, ZIP-Zielschutz und Rename-Rollback wurden in diesem Change nicht bearbeitet. Gemeinsame Jobverwaltung, Suchlimits/Teilfehlermeldungen und Vergleichssemantik bleiben weitere Aufgaben aus [Stufe 5](../../ROADMAP.md#umsetzungsplan-nach-der-projektprüfung).

Nicht vollständig abgenommen sind verzögerte Drag-and-drop-Abläufe, VoiceOver, hoher Kontrast, alle Dialogkombinationen, externe/verschiedene Volumes und große Verzeichnisse. Die Sichtprüfung im dunklen Fenster ersetzt diese Prüfungen nicht. Eine Meldung für ausgelassene Sitzungsverzeichnisse, gebündelte Aktualisierung nach externen Änderungen und CI fehlen weiterhin. Das Icon benötigt vor Veröffentlichung noch die abschließende Prüfung in Dock, Finder und App-Umschaltung auf hellen/dunklen Hintergründen. Developer-ID-Signierung, Notarisierung sowie frische Installation und Upgrade bleiben offen.
