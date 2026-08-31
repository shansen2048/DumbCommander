# DumbCommander

Ein zweispaltiger Dateimanager für macOS auf Basis von SwiftUI. Dieses Dokument ist die primäre Einstiegs- und Architekturbeschreibung des Projekts.

## Zweck und Pflege
- Ziel: Ein einfacher, schneller, tastaturfreundlicher Dateimanager im Stil klassischer Commander-Tools.
- WICHTIG: Dieses Dokument ist ein lebendes Dokument und MUSS kontinuierlich an neue Anforderungen, Entscheidungen und Erkenntnisse angepasst werden.

## Architekturüberblick
- Hauptkomponenten:
  - `DumbCommanderApp`: App-Entry, Scenes, Commands, Settings.
  - `ContentView`: Koordination, Toolbar, globale Shortcuts, Status-/Funktionsleiste, Command-Prompt.
  - `FileListView`: Panel mit Dateiliste, Navigation (Pfeile, Enter, Tab), Selektion, Spaltenbreite, Up-Verzeichnis.
  - `KeyEventHandlingView`: NSViewRepresentable für lokale Key-Event-Monitore.
  - `SettingsView`: Einstellungen (Editorwahl, versteckte Dateien, Löschbestätigung, Status-/Funktionsleiste).
- Datenfluss:
  - `AppState` (ObservableObject) trägt `leftDirectory`, `rightDirectory`, `activePanel`, `selectedFile`, `showGotoDirectoryPrompt`.
  - Bindings von `ContentView` zu `FileListView` via `@Binding currentDirectory`.

## Tastatur- und Interaktionskonzept
- Globale Shortcuts (in `ContentView` via `KeyEventHandlingView`):
  - F1/F2: Linkes/rechtes Panel aktivieren.
  - F3–F8: Anzeigen, Bearbeiten, Kopieren, Verschieben, Neuer Ordner, Löschen. F10: Beenden.
  - Option+F1 / Option+F2: Öffnet das Favoriten-Popover des linken/rechten Panels.
  - Command+Q wird nicht abgefangen (System übernimmt).
  - Die Menüeinträge unter "Navigation" tragen dieselben F-Tasten-Shortcuts (via SwiftUI `keyboardShortcut` mit Funktionstasten-KeyEquivalents).
- Lokale Shortcuts (in `FileListView` via `KeyEventHandlingView`):
  - Pfeil hoch/runter: Auswahl bewegen.
  - Enter: Öffnen/Wechseln in Verzeichnis oder Anzeigen von Dateien.
  - Tab: Panel-Wechsel (`onTab`-Closure, links→rechts, rechts→links).
- WICHTIG: Jeder Key-Monitor konsumiert nur Events, die er wirklich verarbeitet. Alle anderen werden durchgereicht, um Konflikte zu vermeiden.

## Einstellungen (Preferences)
- Persistiert via `@AppStorage`:
  - `editorChoice`: "system" | "vscode" | "xcode" | "textedit" | "custom".
  - `customEditorPath`: Pfad zu benutzerdefiniertem Editor (.app).
  - `showHiddenFiles`: Bool – blendet dotfiles/hidden files ein/aus.
  - `confirmBeforeDelete`: Bool – zeigt Bestätigungsdialog vor Löschen.
  - `showStatusBar`: Bool – Statusleiste ein-/aus.
  - `showFunctionBar`: Bool – Funktionsleiste (F1–F10-Buttons) ein-/aus.
  - `favoriteDirectories`: Liste von Verzeichnispfaden (JSON, via @AppStorage) – verwaltet in den Einstellungen (Hinzufügen/Entfernen/Ändern) über Dateiauswahldialoge.

## UI-Bausteine
- Statusleiste (ContentView, untere Kante):
  - Zeigt aktives Panel, Pfade beider Panels, aktuelle Auswahl.
  - Umschaltbar via Einstellungen und Menü.
- Funktionsleiste (ContentView):
  - Buttons mit Beschriftungen korrespondierend zu F1–F10.
  - Umschaltbar via Einstellungen.
- Dateiliste (FileListView):
  - Spaltenbreiten verstellbar, Listendarstellung `.listStyle(.plain)`, Headerzeilen, Up-Row (`..`).
  - Sortierung wie im klassischen Commander: Verzeichnisse zuerst, dann alphabetisch (`localizedStandardCompare`).
- Favoriten-Kopfzeile (über der Liste):
  - Button "Favoriten" (Popover), Favoriten-Picker und aktuelle Pfadanzeige
  - Einheitliche, systemorientierte Kopfzeile mit abgesetztem Hintergrund und Trennlinie; Pfad in gut lesbarer Systemfarbe

## Favoriten-Verzeichnisse
- Verwaltung in den Einstellungen unter "Favoriten":
  - Hinzufügen: Dateiauswahl (Ordner), Mehrfachauswahl möglich.
  - Entfernen: Auswahl in der Liste löschen.
  - Ändern: Auswahl in der Liste bearbeiten und neuen Ordner wählen.
- Speicherung: `@AppStorage("favoriteDirectories")` als JSON-Array von Pfaden.
- Nutzungsidee (zukünftig): Favoriten in der UI schnell zugänglich machen (z. B. Seitenleiste, Menüeinträge, Shortcuts).
- Popover-Bedienung: Über jedem Panel befindet sich ein Button "Favoriten" (Stern-Icon). Ein Klick öffnet ein Popover mit:
  - Suchfeld zum Filtern der Favoriten
  - Liste der Favoriten (mit Kontextmenü: Ändern/Entfernen)
  - Tastatursteuerung im Popover: Pfeile (hoch/runter) zur Navigation, Enter zum Auswählen, Esc zum Schließen
  - Zusätzlich kann das Popover per Tastatur geöffnet werden: Option+F1 (linkes Panel), Option+F2 (rechtes Panel)

## Entscheidungen und Patterns
- Event-Handling: Global vs. lokal strikt getrennt; nur tatsächlich behandelte Events werden konsumiert.
- Dateifilter: Versteckte Dateien werden anhand von Dotfile-Präfix und `NSURLIsHiddenKey` gefiltert.
- Editor-Öffnung: `NSWorkspace.shared.open` für Systemstandard; `/usr/bin/open -a <App>` für spezifische Apps.
- UI-Stile: Vermeidung veralteter APIs (`.textFieldStyle(.roundedBorder)`, `.listStyle(.plain)`).

## Bekannte To-Dos / Ideen
- Menü/Shortcut zum Umschalten der Funktionsleiste (analog Statusleiste) hinzufügen.
- Papierkorb-Unterstützung statt hartem Löschen (NSWorkspace-Recycle).
- Startverzeichnisse konfigurierbar machen.
- Fehler-/Berechtigungsfälle beim Öffnen/Schreiben robuster behandeln.
- Tests für Navigation/Shortcuts (UI-Tests) ergänzen.
- Optional: Zusätzlicher Favoriten-Zugriff über ein eigenes Menü "Favoriten".

## Konventionen zur Dokumentpflege
- Diese README ist die primäre, stets aktuelle Referenz. Bei jeder neuen Anforderung oder Änderung: Inhalte hier ergänzen (Was, Warum, Wo im Code).
- Neue Features: Kurzbeschreibung, relevante Dateien/Typen, Interaktionskonzept (Shortcuts/Settings), und eventuelle Migrationshinweise.
- Verweise auf Quellcodeabschnitte (Dateinamen, Typsignaturen) in `code voice` schreiben.

## Wartung und Anpassung
- Bei jeder neuen Anforderung: Hier dokumentieren (Was, Warum, Wo geändert).
- Konsistenten Stil beibehalten (Benennungen, Architektur, Event-Handling-Konventionen).
- Plattform-/API-Updates prüfen (z. B. Änderungen in SwiftUI/AppKit) und Deprecations frühzeitig beheben.

