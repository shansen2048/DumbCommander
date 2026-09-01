# ADR 0003: Befehle, Sitzung und interner Viewer

- Status: angenommen
- Datum: 2026-09-01

## Kontext

Menü, Toolbar, Funktionsleiste und lokale Ereignismonitore definierten Befehle
und Beschriftungen mehrfach. Das erschwerte konsistente Shortcuts und eine
zuverlässige Sperre während Texteingaben. Panelpfade wurden nicht über
App-Neustarts hinweg erhalten. F3 öffnete Dateien mit einer externen App statt
eines Commander-typischen internen Viewers.

## Entscheidung

`CommandRegistry` ist die gemeinsame Quelle für Befehlsidentität, deutsche
Beschriftung, Symbol und Shortcut. Menü, Toolbar, Funktionsleiste und der globale
Ereignismonitor leiten ihre Darstellung daraus ab. Lokale Pfeil-, Enter-,
Leertasten- und Tab-Navigation bleibt beim betroffenen Panel, weil sie dessen
Cursorzustand direkt verändert.

Commander-Shortcuts werden nicht verarbeitet, solange ein Textfeld oder ein
modaler Dialog aktiv ist. Nicht behandelte `NSEvent`-Ereignisse werden
unverändert weitergereicht.

Die bewusste Abweichung vom Total Commander bleibt bestehen: F1 aktiviert das
linke und F2 das rechte Panel. Tab wechselt zwischen den Panels. F3 bis F8 und
Shift+F6 behalten ihre Commander-Bedeutung.

`CommanderSessionStore` speichert ausschließlich die beiden Verzeichnispfade
und das aktive Panel. Die Pfade werden beim Start asynchron über
`FileSystemServing` validiert. Nicht verfügbare Verzeichnisse und Symlinks werden
verworfen. Security-Scoped Bookmarks werden nicht erzeugt, weil ADR 0001 eine
direkte, nicht sandboxed Distribution festlegt.

Der interne Viewer liest außerhalb des Main Actors höchstens 4 MiB für Text und
Hex beziehungsweise 64 MiB für ein Bild. Text und Hex werden vor der Übergabe an
die UI vorbereitet; Bildvorschauen werden auf maximal 2048 Pixel dekodiert. Die
UI hält dadurch nicht unbeschränkt große Dateien im Speicher. Finder-Aliase und
symbolische Links werden nicht automatisch aufgelöst.

## Folgen

Beschriftungen und Shortcuts können nicht mehr unabhängig voneinander driften.
Normale Dateioperationen bleiben vollständig per Tastatur erreichbar, ohne
Texteingaben zu stören. Die letzte Sitzung wird reproduzierbar wiederhergestellt,
ohne Tests oder Startlogik an `UserDefaults.standard` zu koppeln.

Der Viewer ist bewusst eine begrenzte Vorschau und kein vollständiger Editor.
Suche im Viewer, Streaming über mehrere Fenster und weitere Binäransichten sind
spätere Erweiterungen.
