// DumbCommander

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
  - `Item`/SwiftData: Beispielmodell (derzeit nicht relevant für Dateimanager-Logik).
- Datenfluss:
  - `AppState` (ObservableObject) trägt `leftDirectory`, `rightDirectory`, `activePanel`, `selectedFile`, `showGotoDirectoryPrompt`.
  - Bindings von `ContentView` zu `FileListView` via `@Binding currentDirectory`.

## Tastatur- und Interaktionskonzept
- Globale Shortcuts (in `ContentView` via `KeyEventHandlingView`):
  - F1–F10: Aktionen (Panels aktivieren, Anzeigen, Bearbeiten, Kopieren, Verschieben, Neuer Ordner, Löschen, Beenden).
  - Command+Q wird nicht abgefangen (System übernimmt).
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
- Settings-Szene verfügbar (Cmd+,) und zusätzlicher Toggle im Menü “Ansicht” für Statusleiste (Cmd+/).

## UI-Bausteine
- Statusleiste (ContentView, untere Kante):
  - Zeigt aktives Panel, Pfade beider Panels, aktuelle Auswahl.
  - Umschaltbar via Einstellungen und Menü.
- Funktionsleiste (ContentView):
  - Buttons mit Beschriftungen korrespondierend zu F1–F10.
  - Umschaltbar via Einstellungen.
- Dateiliste (FileListView):
  - Spaltenbreiten verstellbar, Listendarstellung `.listStyle(.plain)`, Headerzeilen, Up-Row (`..`).

## Entscheidungen und Patterns
- Event-Handling: Global vs. lokal strikt getrennt; nur tatsächlich behandelte Events werden konsumiert.
- Dateifilter: Versteckte Dateien werden anhand von Dotfile-Präfix und `NSURLIsHiddenKey` gefiltert.
- Editor-Öffnung: `NSWorkspace.shared.open` für Systemstandard; `/usr/bin/open -a <App>` für spezifische Apps.
- UI-Stile: Vermeidung veralteter APIs (`.textFieldStyle(.roundedBorder)`, `.listStyle(.plain)`).

## Bekannte To-Dos / Ideen
- Menü/Shortcut zum Umschalten der Funktionsleiste (analog Statusleiste) hinzufügen.
- Visuelles Feedback in der Funktionsleiste bei Tastaturaktionen (kurzes Highlighting).
- Papierkorb-Unterstützung statt hartem Löschen (NSWorkspace-Recycle).
- Startverzeichnisse konfigurierbar machen.
- Fehler-/Berechtigungsfälle beim Öffnen/Schreiben robuster behandeln.
- Tests für Navigation/Shortcuts (UI-Tests) ergänzen.

## Wartung und Anpassung
- Bei jeder neuen Anforderung: Hier dokumentieren (Was, Warum, Wo geändert).
- Konsistenten Stil beibehalten (Benennungen, Architektur, Event-Handling-Konventionen).
- Plattform-/API-Updates prüfen (z. B. Änderungen in SwiftUI/AppKit) und Deprecations frühzeitig beheben.
