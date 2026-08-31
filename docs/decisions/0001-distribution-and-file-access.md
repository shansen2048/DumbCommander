# ADR 0001: Distribution und Dateisystemzugriff

- Status: angenommen
- Datum: 2026-08-31

## Kontext

DumbCommander soll als Zwei-Panel-Dateimanager beliebige lokale Verzeichnisse lesen und dort auf ausdrücklichen Benutzerbefehl Dateien kopieren, verschieben, umbenennen und in den Papierkorb bewegen. Zusätzlich enthält der Prototyp eine experimentelle Shell-Konsole.

Die bisherige Projektkonfiguration aktivierte App Sandbox und erlaubte benutzergewählte Dateien nur lesend. Gleichzeitig starteten beide Panels im Benutzerverzeichnis und die App versuchte dort ohne Security-Scoped Bookmarks zu schreiben. Konfiguration und Produktverhalten widersprachen sich.

Eine Sandbox-Auslieferung wäre möglich, würde aber eine Auswahl zugelassener Wurzelverzeichnisse sowie persistente Security-Scoped Bookmarks voraussetzen. Dieser Zugriff passt schlechter zum angestrebten Commander-Arbeitsfluss und zur experimentellen Shell.

## Entscheidung

DumbCommander wird vorerst als direkt verteilte, signierte und notarisierte macOS-App außerhalb des Mac App Store entwickelt.

- App Sandbox ist deaktiviert.
- Hardened Runtime bleibt aktiviert.
- Die Zielplattform ist ausschließlich macOS ab Version 14.
- Die App fordert nicht pauschal Full Disk Access an.
- macOS-Datenschutzbeschränkungen und POSIX-Berechtigungen werden respektiert und als normale Fehlerzustände angezeigt.
- Jede mutierende Aktion benötigt eine ausdrückliche Benutzerhandlung.
- Die Shell bleibt als experimentelles Power-User-Feature gekennzeichnet.

## Folgen

Die App kann den für einen Commander erwarteten lokalen Dateisystemzugriff anbieten, ohne jedes Wurzelverzeichnis über einen Open-Dialog freizuschalten. Bestimmte geschützte macOS-Verzeichnisse bleiben dennoch eingeschränkt.

Eine Veröffentlichung im Mac App Store ist mit dieser Entscheidung nicht möglich. Ein späterer Wechsel zur Sandbox erfordert ein eigenes Berechtigungs- und Bookmark-Modell und muss als neue Architekturentscheidung dokumentiert werden.

Codesignierung, Hardened Runtime und Notarisierung müssen vor einem öffentlichen Release mit einer echten Release-Konfiguration geprüft werden. Ein Build mit `CODE_SIGNING_ALLOWED=NO` validiert diese Eigenschaften nicht.
