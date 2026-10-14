# ADR 0006: Verankerte Dateioperationen, Archivprüfung und Wiederherstellung

- Status: angenommen
- Datum: 2026-10-14
- Ergänzt ADR 0002 und ADR 0005; Distribution, Sandbox und Hardened Runtime bleiben unverändert.

## Anlass

Die Befunde F01–F05 der Projektprüfung zeigten unvollständigen Metadatenerhalt,
unsichere Fehlerbereinigung, direkte Archivextraktion und einen nicht
abbruchfesten Rename-Rollback. Existenzprüfung und spätere Pfadmutation allein
reichen nicht aus, wenn andere Prozesse dieselben Verzeichnisse ändern.

## Dateioperationen

SafeDirectory öffnet Verzeichniskomponenten ohne Linkverfolgung und hält
Dateideskriptoren fest. Nur die festen macOS-Systemaliase /tmp, /var und
/etc werden auf /private/... abgebildet. Weitere Linkkomponenten in
Operationspfaden werden abgewiesen; das bewusste Öffnen eines Linkziels bleibt
ein eigener Navigationspfad.

Pläne erfassen Geräte-/Inodeidentität und Änderungsmerkmale von Quelle und
vorhandenem Ziel sowie die Identität ihrer Eltern. Die Ausführung prüft diese
Voraussetzungen erneut. Fehlende Einträge werden von Zugriffsfehlern
unterschieden. FIFOs und andere Spezialdateien werden nicht als Datenstrom
kopiert.

Neue Kopien entstehen in einem exklusiv angelegten privaten Geschwisterordner
mit Modus 0700. Reguläre Dateien werden exklusiv geöffnet und blockweise
kopiert. Die Veröffentlichung nutzt renameatx_np mit RENAME_EXCL; ein inzwischen
vorhandenes Ziel führt zu einem Fehler. Es gibt keinen Fallback auf
überschreibendes Umbenennen. Falls ein Dateisystem diesen Mechanismus nicht
unterstützt, scheitert die Operation sichtbar.

Beim expliziten Ersetzen wird zuerst die gesamte neue Kopie erzeugt. Der
vorhandene Zielbaum wird vor und nach dem Verschieben in den privaten
Arbeitsbereich geprüft. Erst dann wird die neue Kopie ohne Überschreiben
veröffentlicht. Scheitert die Veröffentlichung, wird das vorherige Ziel
ebenfalls ohne Überschreiben zurückgestellt. Blockiert ein fremder Eintrag
die Wiederherstellung, bleiben die Daten unter dem im Fehler genannten
Arbeitsverzeichnis erhalten (previous und gegebenenfalls new).

Eine fehlgeschlagene Erstellung löscht niemals pauschal den öffentlichen
Zielpfad. Bereinigung betrifft ausschließlich den eigenen, identitätsgeprüften
Arbeitsbereich. Beim Kopier-Fallback eines Verschiebens wird die Quelle nach
erfolgreicher Veröffentlichung erneut als Baum geprüft, in einen privaten
Bereich verschoben und dort vor dem Entfernen nochmals geprüft. Ein
veränderter oder nicht entfernbarer Quellbaum erzeugt einen ausdrücklichen
Teilbericht. Ausschließlich EXDEV erlaubt diesen Fallback.

## Metadatenpolitik

Für reguläre Dateien und Verzeichnisse müssen POSIX-Modus, Änderungszeit,
Erstellungszeit, Dateiflags, Extended Attributes einschließlich Resource Fork
und erweiterte ACL erhalten bleiben. Nach der Übertragung mit dem nativen
fcopyfile und COPYFILE_METADATA wird die Erstellungszeit zusätzlich explizit
über fsetattrlist gesetzt; anschließend werden alle zugesagten Merkmale überprüft. Ein Fehler
verhindert die Veröffentlichung und insbesondere das Entfernen einer
Verschiebequelle. Der Inhalt regulärer Dateien wird vorab blockweise kopiert.
Symlinkdeskriptoren mit O_SYMLINK kopieren Linkdaten und Metadaten ohne
Öffnen des Linkziels.

Besitzerwechsel, die Topologie mehrerer Hardlinks und die physische
Sparse-/Kompressionsdarstellung werden nicht zugesagt. Der logische Inhalt
und die oben genannten Metadaten dürfen nicht still verloren gehen.
Zielvolumes mit abweichender Metadatenunterstützung scheitern im Zweifel
mit Fehler. Reale Tests auf anderen Volumes ergänzen die automatisierte
EXDEV-Injektion; sie werden nicht durch diese ersetzt. Die lokale Suite erzeugt
dafür ein separates temporäres APFS-Diskimage, prüft den tatsächlichen
Volume-Wechsel und hängt es anschließend wieder aus. Andere Dateisystemtypen
und physische externe Medien benötigen ergänzende Abnahme.

Der native Vertrag ist in Apples
[copyfile-Handbuch](https://github.com/apple-oss-distributions/copyfile/blob/main/copyfile.3)
dokumentiert; die verwendeten Flags und Signaturen sind zusätzlich gegen das
installierte macOS-SDK geprüft.

## Archive

ZIP und unkomprimiertes TAR werden mit der von macOS gelieferten
libarchive.2 gelesen. Das SDK enthält Bibliothek und Handbuchseiten, aber
keine öffentlichen Header; SystemArchive/SystemArchive.h deklariert nur
den benötigten stabilen C-ABI-Ausschnitt. Es werden weder eine zusätzliche
Bibliothek installiert noch Implementierungscode eingebettet. Die
Implementierung folgt der dokumentierten
[Streaming-Leseschnittstelle](https://github.com/libarchive/libarchive/blob/master/libarchive/archive_read.3).

Eine erste Runde prüft das vollständige Inhaltsverzeichnis: absolute Pfade,
aufsteigende Komponenten, doppelte Namen einschließlich Unicode-/Case-Aliasen,
Dateien oder Links als Eltern weiterer Einträge, nicht unterstützte Typen,
Hardlinks und unsichere Linkziele führen zum Abbruch. Symbolische Archivlinks
sind nur relativ und ohne Elternkomponenten erlaubt; direkte Linkzyklen werden
abgewiesen. Diese bewusste Einschränkung verhindert auch Umwege über kombinierte
Links und Elternkomponenten.

Die Grenzen liegen bei 100.000 Einträgen, 4.096 UTF-8-Bytes pro Pfad und
20 GiB angekündigter bzw. tatsächlich entpackter Gesamtgröße. Tests können
kleinere Grenzen injizieren. Die zweite Leserunde prüft das Manifest erneut
und schreibt ausschließlich über verankerte Deskriptoren in einen privaten
Bereich. Daten werden in 64-KiB-Blöcken gelesen; CRC-/Lesefehler, unerwartete
Größen und Abbruch verwerfen unveröffentlichte Daten. Symlinks werden zuletzt
angelegt und niemals durchlaufen.

Erst danach übernimmt der normale Operationskoordinator die obersten
entpackten Einträge. Bereits vorhandene Ziele, auch Verzeichnisse und
defekte Links, sind Konflikte; Archive führen nicht automatisch zusammen.
Spät auftretende Konflikte ergeben strukturierte Teilberichte. Schon
veröffentlichte Einträge bleiben erhalten; das Originalarchiv bleibt
unverändert und ermöglicht erneutes Entpacken.

Archiv-Metadaten haben eine eigene, eingeschränkte Politik: keine Übernahme
fremder Eigentümer, ACLs, Spezialdateien oder Setuid-/Setgid-Bits. Dateien
behalten sichere Zugriffs-/Ausführungsbits und Änderungszeit; Verzeichnisse
bleiben zugänglich. Archivextraktion ist kein verlustfreies macOS-Backup.

Beim Packen werden die Quellen zuerst über den sicheren Kopierpfad
gesichert. zip bzw. tar erhalten getrennte Argumente und mit ./ präfixierte
Operanden nach dem Optionsende. Das fertige Archiv wird ebenfalls erst
nach erfolgreichem Prozessende ohne Überschreiben veröffentlicht. Ein
bestehendes ZIP wird niemals still aktualisiert.

## Mehrfachumbenennung und Lebenszyklus

Die Ausführung validiert alle Quellen und Ziele unabhängig von der
unverbindlichen Namensvorschau. Rückrollen läuft in einem separaten Task,
der die ursprüngliche Cancellation nicht erbt. Zuerst werden alle bereits
vergebenen Namen wieder auf freie temporäre Namen verschoben; anschließend
werden die Originalnamen hergestellt. Dadurch funktionieren Namensketten
und Zyklen. Jeder Fehler, bestätigte aktuelle Pfad und erforderliche
Wiederherstellung erscheinen pro Element im Ergebnis. Undo prüft erneut
die Identität des umzubenennenden Eintrags.

Ein privates recovery.json enthält Original-, Wunsch- und aktuelle Pfade,
alle nächsten Kandidaten sowie Geräte-/Inodekennungen. Kandidaten werden
vor dem jeweiligen Rename geschrieben und synchronisiert. Das Journal
wird nach Erfolg oder vollständigem Rollback entfernt; bei unvollständiger
Wiederherstellung bleibt es erhalten. Es ist auch nach einem unerwarteten
Prozessende lesbar. Jeder erneute Wiederherstellungsversuch erstellt ein neues
Journal; ältere Nachweise werden nicht ungeprüft gelöscht. Keine automatische Mutation beim nächsten Start:
vor einer manuellen Wiederherstellung sind Identitäten erneut zu prüfen.
Eine integrierte Journal-Importoberfläche bleibt eine spätere Ergänzung.

MutationActivity erfasst direkte Operationen, Archive und Mehrfachumbenennung
gemeinsam mit Abbruchaktion und Berichten dieser Sitzung. Archive und
Mehrfachumbenennungen sperren Mehrfachstart und Dialogschließen während
der Arbeit. Beenden über F10/Cmd-Q und Fensterschließen bieten Weiterarbeiten,
Abbrechen mit anschließendem Warten oder Schließen nach Abschluss an.
Wiederherstellung und Aktualisierung der Panels sind Teil der laufenden
Arbeit. Nachfolgende Jobs löschen frühere Berichte nicht.

## Grenzen

Ein aus mehreren Einträgen bestehender Auftrag ist keine atomare
Dateisystemtransaktion. Bereits ausgeführte Teile werden explizit berichtet.
Die Prüfung von Identitäten und Bäumen ist keine Schreibsperre für andere
Prozesse mit bereits geöffneten Handles. Die App behauptet keine Isolation
gegen einen böswilligen Prozess mit denselben Benutzerrechten. Kill/Absturz,
Stromausfall, ungewöhnliche Dateisysteme und nicht reagierendes Betriebssystem-I/O
benötigen weiterhin gesonderte Abnahme. Es gibt keine automatische Löschung
unbekannter temporärer Reste beim Start.
