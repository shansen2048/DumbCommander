# AGENTS.md

Diese Regeln gelten für das gesamte Repository. Die README im Repository-Wurzelverzeichnis beschreibt Produktziel, Ist-Zustand und Roadmap und ist vor größeren Änderungen zu lesen.

## Produktauftrag

DumbCommander wird ein nativer, tastaturorientierter Zwei-Panel-Dateimanager für macOS. Total Commander unter Windows ist das Interaktionsvorbild, nicht eine Aufforderung zu einem pixelgenauen Klon.

Prioritäten, in dieser Reihenfolge:

1. Schutz und Vorhersagbarkeit von Benutzerdaten.
2. Korrekte Trennung von Quell- und Zielpanel.
3. Vollständige Tastaturbedienung und stabile Fokusführung.
4. Responsivität bei großen Verzeichnissen und langen Operationen.
5. Erweiterte Commander-Funktionen.

Neue Features dürfen keine Abkürzungen nehmen, die eine höhere Priorität verschlechtern.

## Plattform und Werkzeuge

- Zielplattform ist ausschließlich macOS, derzeit ab macOS 14.
- UI: SwiftUI; AppKit-Brücken nur dort, wo SwiftUI die benötigte macOS-Funktion nicht zuverlässig liefert.
- Sprache: Swift 5 Language Mode, bis eine bewusste Migration beschlossen und vollständig geprüft wurde.
- Keine iOS-Kompatibilität vortäuschen. AppKit-basierter Code darf nicht durch zusätzliche iOS-Build-Settings kaschiert werden.
- Externe Abhängigkeiten nur bei klarem Nutzen und mit dokumentierter Begründung hinzufügen.

Build-Prüfung:

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

`CODE_SIGNING_ALLOWED=NO` prüft nur Kompilierung und Linken. Änderungen an Sandbox, Entitlements, Dateizugriff oder App-Lifecycle müssen zusätzlich in einer signierten lokalen App geprüft werden.

## Zielarchitektur

Entkopple den bestehenden Prototyp schrittweise, ohne einen Big-Bang-Rewrite:

- `PanelState`: genau ein Zustand pro Panel, einschließlich Verzeichnis, Cursor, Auswahl, Markierungen, Sortierung und Verlauf.
- `CommanderState`: aktives Panel und panelübergreifende UI-Zustände; keine einzelne globale Dateiauswahl als Ersatz für Panelzustand.
- `FileItem`: beim Laden erfasste, stabile Metadaten statt wiederholter synchroner Dateisystemabfragen aus jeder Zeile.
- `FileSystemService`: Protokoll für Lesen, Prüfen und elementare Operationen; reale und Testimplementierung.
- `FileOperationCoordinator`: plant Quelle, Ziel, Konflikte und Ergebnis; führt lange Arbeit außerhalb des Main Actors aus.
- `CommandRegistry`: eine Quelle der Wahrheit für Menü, Funktionsleiste, Labels und Shortcuts.
- Views rendern Zustand und senden Intents. Sie führen keine komplexen oder lang laufenden Dateisystemoperationen direkt aus.

Bestehenden Code nur so weit umbauen, wie für die jeweilige Änderung nötig. Neue Logik jedoch nicht weiter in `ContentView` oder `FileListView` konzentrieren.

## Invarianten des Zwei-Panel-Modells

- Es gibt immer genau ein aktives Panel.
- Das aktive Panel ist bei Kopieren und Verschieben die Quelle; das andere Panel ist standardmäßig das Ziel.
- Cursor, Auswahl und Markierungen gehören einem konkreten Panel und überleben einen Panelwechsel korrekt.
- Markierte Elemente haben Vorrang vor dem Cursor, aber niemals vor Elementen des anderen Panels.
- Nach einer Operation werden beide betroffenen Panels gezielt aktualisiert; Cursor und sinnvolle Auswahl bleiben nach Möglichkeit erhalten.
- `Tab` wechselt das aktive Panel. Ein Mausklick in ein Panel aktiviert dieses Panel, bevor daraus eine Operation ausgelöst wird.
- Shortcuts dürfen während Texteingabe keine Zeichen, Pfeile, Tab oder Enter stehlen.

## Regeln für Dateioperationen

Dateioperationen sind der sicherheitskritische Kern.
Die verbindliche Planungs- und Konfliktsemantik ist zusätzlich in
`docs/decisions/0002-konflikte-und-dateioperationen.md` dokumentiert.

- Niemals nach einem Papierkorbfehler automatisch mit endgültigem Löschen fortfahren.
- Niemals existierende Ziele stillschweigend überschreiben, zusammenführen oder entfernen.
- Konflikte explizit als `replace`, `skip`, `keepBoth`, `merge` oder `cancel` modellieren; nur tatsächlich sinnvolle Optionen anbieten.
- `replace` erst nach vollständig erzeugtem temporärem Ersatz ausführen. `merge` überschreibt keine verschachtelten Konflikte, sondern weist sie als übersprungen aus.
- Vor der Ausführung normalisierte Quelle und Ziel validieren. Rekursives Kopieren oder Verschieben eines Verzeichnisses in sich selbst verhindern.
- Symbolische Links als eigenständige Einträge behandeln und niemals automatisch dereferenzieren. Kopieren erhält den Link; Verschieben, Umbenennen und Papierkorb betreffen nur den Link selbst. Verzeichnislesen und rekursive Operationen steigen nicht in das Linkziel ein.
- Pakete, Aliase, versteckte Dateien, Berechtigungen, verschiedene Volumes und Groß-/Kleinschreibung bewusst berücksichtigen.
- Lange Operationen müssen asynchron, abbrechbar und fortschrittsfähig sein. Keine blockierende Dateiarbeit auf dem Main Actor.
- Teilfehler strukturiert pro Element zurückgeben. Keine alleinige Fehlerausgabe über `print` oder einen zusammengesetzten String.
- Destruktive Integrationstests ausschließlich in einem für den Test neu erzeugten temporären Verzeichnis ausführen. Pfade außerhalb dieses Verzeichnisses sind tabu.
- Tests dürfen weder das echte Benutzerverzeichnis noch echte Favoriten oder `UserDefaults.standard` verändern.

## Sandbox und Dateizugriff

Das Distributionsmodell ist in `docs/decisions/0001-distribution-and-file-access.md` festgelegt:

- DumbCommander wird direkt, signiert und notarisiert außerhalb des Mac App Store verteilt.
- App Sandbox bleibt deaktiviert, Hardened Runtime bleibt aktiviert.
- Änderungen an Sandbox, Entitlements, Hardened Runtime oder Distributionsmodell benötigen ein neues ADR.
- „Full Disk Access“ nicht als normalen Onboarding-Schritt voraussetzen.
- Berechtigungsfehler als erwartbaren Zustand behandeln und mit einer konkreten nächsten Aktion anzeigen.

## Nebenläufigkeit und Zustand

- Swift-Concurrency bevorzugen. UI-Zustand auf dem Main Actor, Verzeichnislesen und Dateioperationen außerhalb davon.
- Veraltete Ladeergebnisse verwerfen, wenn das Panel inzwischen in ein anderes Verzeichnis gewechselt hat.
- Keine unstrukturierten `DispatchQueue.main.async`-Ketten zur Zustandskoordination hinzufügen.
- `NSEvent`-Monitore müssen alle nicht behandelten Events unverändert weiterreichen und beim Abbau zuverlässig entfernt werden.
- Shell-Prozesse brauchen Arbeitsverzeichnis, Exit-Code, getrennte Ausgabe, Abbruch und eine bewusst dokumentierte Sandbox-Policy, bevor die Konsole ausgebaut wird.

## UI- und Shortcut-Konventionen

- Commander-Workflows sind tastaturzuerst, müssen aber auch mit Maus, VoiceOver und Standard-macOS-Konventionen funktionieren.
- Aktives Panel, Cursor und Mehrfachmarkierung müssen visuell unterscheidbar sein und dürfen nicht allein über Farbe kommunizieren.
- F3 bis F8 behalten ihre Commander-Bedeutung: View, Edit, Copy, Move/Rename, MkDir, Delete.
- Abweichungen vom Total-Commander-Vorbild müssen bewusst entschieden und in der Root-README dokumentiert werden.
- Benutzertexte sind derzeit Deutsch. Keine neue Mischung aus deutschen und englischen Labels einführen; vorhandene Mischungen bei Berührung vereinheitlichen.
- Alerts dürfen keine Operationslogik enthalten. Dialoge liefern Entscheidungen an den Coordinator zurück.

## Tests und Abnahmekriterien

Für jede behobene Regression zuerst oder gleichzeitig einen Test ergänzen, sofern die Logik ohne UI testbar ist.

Mindesterwartung je Änderung:

- Zustands- oder Sortierlogik: Unit-Test.
- Dateioperation: Integrationstest in einem eigenen temporären Verzeichnis, einschließlich mindestens eines Fehlerfalls.
- Shortcut oder Fokusänderung: gezielter UI-Test, wenn Unit-Tests das Verhalten nicht abdecken.
- Sandbox-/Bookmark-Änderung: manueller Test mit frischer App-Installation und nach Neustart dokumentieren.
- Vor Abschluss mindestens den Debug-Build ausführen. Relevante Tests ausführen und nicht ausgeführte oder umgebungsbedingt blockierte Prüfungen offen nennen.

Tests müssen deterministisch sein. Keine Annahmen über Inhalte des Benutzerverzeichnisses, installierte Editoren, Tastaturlayout oder Netzverfügbarkeit.

## Arbeitsweise im Repository

- Vor Änderungen `git status --short` prüfen. Vorhandene fremde Änderungen bewahren und nicht formatieren oder zurücksetzen.
- Kleine, zusammenhängende Änderungen bevorzugen. Mechanische Umbauten und Verhaltensänderungen nicht unnötig vermischen.
- Keine generierten Xcode-Benutzerdaten, DerivedData, Build-Produkte oder `.DS_Store` committen.
- Neue Swift-Dateien dem korrekten Xcode-Target hinzufügen und Target Membership prüfen.
- Keine Warnungen unterdrücken, wenn ihre Ursache behoben werden kann.
- Keine destruktiven Git-Befehle und keine Änderungen außerhalb des Repositorys für Tests verwenden.

## Dokumentation

Die Root-`README.md` ist die maßgebliche Produkt- und Architekturübersicht. Bei Änderungen an Funktionsumfang, Shortcut-Belegung, Mindestversion, Build-Schritten, Sandbox-Modell oder Roadmap muss sie im selben Change aktualisiert werden.

Die Datei `DumbCommander/README.md` ist eine ältere, in das App-Bundle kopierte Prototyp-Dokumentation. Keine neue Information ausschließlich dort pflegen; mittelfristig sollte sie entfernt oder durch einen Verweis auf die Root-Dokumentation ersetzt werden.

Kommentare sollen das Warum erklären, nicht den unmittelbar sichtbaren Swift-Code paraphrasieren. Architekturentscheidungen mit weitreichenden Folgen als kurze ADR unter `docs/decisions/` festhalten, sobald dieses Verzeichnis eingeführt wird.

## Fertig-Definition

Eine Änderung ist erst fertig, wenn:

- das Verhalten dem Zwei-Panel-Modell und den Sicherheitsinvarianten entspricht;
- Fehler- und Abbruchpfade berücksichtigt sind;
- relevante Tests vorhanden und ausgeführt sind;
- der macOS-Debug-Build erfolgreich ist;
- keine fremden Working-Tree-Änderungen überschrieben wurden;
- betroffene Dokumentation aktualisiert ist.
