# App Icon

Stand: 14. Oktober 2026.

Das neue Icon zeigt zwei Dateipanels auf einer dunkelblauen, abgerundeten Kachel. Cyan kennzeichnet das aktive Panel, ein warmer Pfeil den Transfer zum zweiten Panel. Die Form bleibt ohne Schrift lesbar und greift das Quelle-Ziel-Modell der Anwendung auf.

Der Assetsatz liegt unter `DumbCommander/Assets.xcassets/CommanderIcon.appiconset`. Beide Buildkonfigurationen verwenden `CommanderIcon`. Alle zehn macOS-Größen von 16 bis 1024 Pixeln sind enthalten; transparente Außenränder bleiben erhalten. Der bisherige Assetsatz bleibt als unbenutzter Altbestand erhalten.

Erzeugt mit dem eingebauten ImageGen-Werkzeug; die Größen wurden anschließend mit macOS `sips` abgeleitet. Für eine erneute Generierung wurde folgender Prompt verwendet:

> Use case: logo-brand. Asset type: production macOS application icon for DumbCommander, a native keyboard-first two-pane file manager. Create one refined app icon centered on a transparent square canvas, 1024 x 1024. A generously rounded square app tile with a deep ink-blue body, subtle dimensional bevel and soft studio light. Inside, two equal upright folder/list panels side by side, separated by a narrow gap: the active left panel luminous cool cyan-blue, right panel soft pearl silver. Each panel has three strong horizontal file-list strokes, readable even at small size. One restrained warm amber rightward transfer arrow bridges the central gap in the lower middle. Precise simple silhouette, calm professional Mac utility, slightly tactile materials, front-on orthographic view, carefully balanced spacing and generous outer safe margin around the tile. No words, letters, numbers, mascot, Finder face, existing brand logos, tiny details, decorative particles, mockup, background scene or watermark. Actual alpha transparency outside the rounded tile; do not draw a checkerboard.

Vor der Veröffentlichung zusätzlich im Dock, Finder und in der App-Umschaltung auf hellem und dunklem Hintergrund prüfen. Die Einbindung ersetzt keine vollständige Release-Abnahme.
