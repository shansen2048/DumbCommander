# ADR 0005: Power Tools und externe Prozesse

- Status: angenommen
- Datum: 1. September 2026

## Kontext

Stufe 4 ergänzt rekursive Suche, virtuelle Ergebnisse, Verzeichnisabgleich,
Mehrfachumbenennung, Prüfsummen, Archive und benutzerdefinierte Befehle. Diese
Funktionen dürfen weder den Main Actor blockieren noch die Konflikt- und
Symlinkregeln des bestehenden Operationskerns umgehen.

ZIP und TAR sind unter macOS bereits durch Systemprogramme verfügbar. Eine
zusätzliche Archivbibliothek würde Abhängigkeiten und Angriffsfläche erhöhen.
Die bisherige experimentelle Kommandozeile führte dagegen über `bash -c` einen
beliebigen String synchron aus; Arbeitsverzeichnis, Ausgabekanäle und Abbruch
waren nicht sauber modelliert.

## Entscheidung

1. Power-Tool-Logik lebt in kleinen asynchronen Diensten außerhalb der Views.
   Views liefern Eingaben und zeigen Vorschau oder Ergebnis.
2. Suchergebnisse sind unveränderliche virtuelle `PanelState`-Inhalte in einem
   normalen Panel-Tab. Sie dürfen Quelle einer Operation sein, aber niemals
   Ziel für Kopieren, Verschieben, Drag-and-drop, Ordneranlage oder Entpacken.
3. Verzeichnissynchronisation erstellt nur die Quellliste und übergibt sie dem
   bestehenden `FileOperationCoordinator`. Konflikte werden nicht separat oder
   stillschweigend entschieden.
4. Mehrfachumbenennung validiert alle Zielnamen, verschiebt zunächst auf
   eindeutige temporäre Namen und rollt Teilergebnisse bei Fehlern zurück. Undo
   gilt ausschließlich für die letzte erfolgreiche Ausführung im offenen Dialog.
5. Archive werden durch `/usr/bin/zip`, `/usr/bin/unzip`, `/usr/bin/tar` und
   `/usr/bin/ditto` mit getrennten Argumenten verarbeitet. Vor dem Entpacken
   werden absolute und aufsteigende Pfade sowie bestehende Ziele abgewiesen.
6. `CommandRunner` erhält Programm, Argumentliste und Arbeitsverzeichnis
   getrennt, sammelt Standardausgabe und Standardfehler separat, prüft den
   Exit-Code und beendet den Prozess bei Abbruch.
7. Die experimentelle Kommandozeile zerlegt Anführungszeichen und Escapes,
   wertet aber keine Shell-Variablen, Umleitungen, Pipes oder Substitutionen aus.
   Benutzerdefinierte Befehle benötigen einen expliziten Programmpfad und
   erlauben nur die Platzhalter `%P` und `%F` in Argumenten.
8. Alle regulären Dateioperationen laufen weiterhin in einer sequenziellen
   Warteschlange des `FileOperationViewModel`. Die Warteschlange ist bewusst
   nicht persistent.

## Folgen

- Lange Werkzeuge und Prozesse bleiben abbrechbar und blockieren die UI nicht.
- Die zentrale Konflikt- und Symlinksemantik gilt auch für Synchronisation und
  Drag-and-drop.
- Archive sind zunächst ein sicherer Browserdialog, kein beschreibbares
  virtuelles Dateisystem im Panel.
- ZIP/TAR-Funktionalität hängt von den dokumentierten macOS-Systemprogrammen ab,
  benötigt aber keine externe Paketabhängigkeit.
- Persistente Operationswarteschlangen, langlebiges Undo und ein echtes
  Archiv-Dateisystem bleiben mögliche spätere Erweiterungen.
