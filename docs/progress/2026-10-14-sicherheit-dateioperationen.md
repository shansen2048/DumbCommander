# Sicherheitskorrekturen für Dateioperationen, Archive und Mehrfachumbenennung

Stand: 14. Oktober 2026. Dieser Nachweis ergänzt die Projektprüfung vom
9. Oktober und den früheren Bedienungsnachweis vom 14. Oktober. Vorhandene
Änderungen an Oberfläche, Sitzungen und App-Icon wurden beibehalten.

## Umgesetzte Korrekturen

| Befund | Korrektur | Regressionen |
| --- | --- | --- |
| F01 – Archive | System-libarchive liest typisierte Einträge; Prüfung des gesamten Manifests, kontrolliertes Entpacken in privaten Arbeitsbereich und anschließende exklusive Veröffentlichung über den Operationskoordinator | ZIP und TAR: aufsteigende/absolute Pfade, Namensaliase, Dateien/Links als Eltern, Linkzyklen, vorhandene defekte Links, Hardlinks, Spezialdateien, manipulierte oder abgeschnittene Daten, Größen-/Eintragslimits, Abbruch und späte Zielkonflikte |
| F02 – Metadaten | Native Metadatenübertragung mit anschließender Prüfung von Modus, Erstellungs-/Änderungszeit, Flags, xattrs einschließlich Resource Fork und ACL; Quelle bleibt bei Fehlschlag erhalten | Kopieren mit Metadaten, injizierter Fehler vor Veröffentlichung, echter Volume-Wechsel auf temporäres APFS sowie gezielt ausgelöstes EXDEV |
| F03 – Konkurrenz und Bereinigung | Quellen/Ziele und Eltern identifizieren; Verzeichnisbäume im Plan erfassen; über Dateideskriptoren arbeiten; neue Daten nur mit RENAME_EXCL veröffentlichen; ausschließlich eigenen Arbeitsbereich bereinigen | Veränderte Quelle, Ziel und tief verschachtelter Zieleintrag; plötzlich belegtes Ziel; ausgetauschter Elternpfad; Fehler nach Sicherung des bisherigen Ziels; geänderte Verschiebequelle; Zugriffsfehler werden nicht als fehlende Datei behandelt |
| F04 – Mehrfachumbenennung | Zweiphasige Wiederherstellung ohne geerbte Cancellation; tatsächliche Pfade und Teilfehler pro Element; Undo mit Identitätsprüfung; synchronisiertes Journal vor jedem Rename, auch bei erneutem Wiederherstellungsversuch | Ketten/Zyklen, reine Änderung der Schreibweise, Fehler in Staging und Zielphase, Abbruch, blockierte Wiederherstellung, erneuter blockierter Versuch, erfolgreiche spätere Wiederherstellung und ausgetauschte Undo-Quelle |
| F05 – Lebenszyklus | Gemeinsame Erfassung direkter, Archiv- und Batch-Mutationen mit Abbruch und Sitzungsberichten; Schließen/Beenden wartet auf Abschluss beziehungsweise Wiederherstellung; betroffene Panels werden auch nach Fehlern aktualisiert | Registry wartet auf sämtliche Jobs und erhält Berichte; lokal signierte UI prüft F10, Fensterschließen und Cmd-Q während einer langsamen Kopie |

Die Architektur und bewusst eingeschränkte Metadaten-/Archivpolitik stehen in
[ADR 0006](../decisions/0006-sichere-dateimutationen.md). Das Distributionsmodell,
die Entitlements und die vorgesehenen Hardened-Runtime-Einstellungen wurden
nicht geändert.

## Testumgebung und Prüfstand

Die neuen Sicherheitsfälle liegen in `DumbCommanderTests/SecurityTests.swift`.
Alle Daten und Diskimages entstehen in einer frisch erzeugten temporären
Fixture. Der APFS-Test erzeugt ein 64-MiB-Sparseimage, hängt es innerhalb dieser
Fixture ein, prüft unterschiedliche Gerätekennungen und den echten
Verschiebe-Fallback und hängt es anschließend aus. Fremde Dateien, echte
Favoriten und produktive Einstellungen werden nicht verwendet.

Konkurrierende Änderungen und Fehler werden über schmale, im Produktbetrieb
unbelegte Hooks deterministisch ausgelöst. Der Kopierabbruch erfolgt nach
beobachtetem Fortschritt statt nach einem zufälligen Zeitintervall. Die UI
verlangsamt ausschließlich im isolierten Testmodus ihre eigene Kopie.

Der vollständige abschließende Lauf ist erfolgreich:

- 79 Unit-/Integrationstests: 53 bestehende und 26 neue Sicherheitsprüfungen,
  keine Fehler; einschließlich des echten APFS-Volume-Wechsels.
- 20 UI-Testausführungen: 18 Haupttests und zwei Launch-Konfigurationen,
  keine Fehler; lokal mit Ad-hoc-Signierung gestartet.
- Vorgegebener macOS-Debug-Build mit `CODE_SIGNING_ALLOWED=NO`: erfolgreich.
- `git diff --check`: erfolgreich.

Ergebnisbundle: `build/Security-20261014-verified.xcresult`.
Testlog: `/tmp/DumbCommander-security-verified.log`.
Buildlog: `/tmp/DumbCommander-security-debug-build.log`.
Die reproduzierbaren Befehle stehen in der Root-README; das Testbundle wurde
zusätzlich mit `-resultBundlePath build/Security-20261014-verified.xcresult`
gespeichert. Generierte Produkte und Resultate sind nicht zum Commit vorgesehen.

Der Build enthält keine Swift-Compilerwarnungen. Xcode meldet die ausgelassene
AppIntents-Metadatenextraktion, da die App AppIntents nicht verwendet. Im UI-Lauf
erscheinen zudem Meldungen aus Xcodes Automatisierungs-/Accessibility-Laufzeit
und eine interne QoS-Warnung; sie führten zu keinen Testfehlern und wurden
nicht unterdrückt.

Während der Entwicklung aufgedeckte Fehler wurden korrigiert: inkompatible
Flags beim Öffnen von Symlinkdeskriptoren, doppelte Freigabe eines fehlgeschlagenen
Archivlesers, nicht exakt erhaltene Erstellungszeit und ein mehrdeutiger
Accessibility-Selektor im Beendigungstest. Frühere fehlgeschlagene Läufe sind
keine Erfolgsnachweise; maßgeblich ist ausschließlich der abschließende Lauf.

## Bewusste Grenzen und nächste Abnahme

- Ein Mehrfachauftrag ist keine atomare Transaktion. Bereits veröffentlichte
  Elemente bleiben bei einem späteren Fehler erhalten und erscheinen im Bericht.
- Nicht unterstützte Metadaten oder exklusive Umbenennung führen zu einem
  Fehler. ExFAT, SMB und physische externe beziehungsweise langsame Medien
  sind zusätzlich zu den lokalen APFS-Prüfungen abzunehmen.
- Archive übernehmen keine fremden Eigentümer, ACLs, Hardlinks oder
  Setuid-/Setgid-Bits. Links mit Elternkomponenten werden abgewiesen. Es gelten
  100.000 Einträge, 20 GiB entpackte Daten und 4.096 UTF-8-Bytes pro Pfad als Grenzen.
- Bei blockierter Wiederherstellung bleiben Daten und Journal erhalten.
  Das Journal enthält Pfadkandidaten und Geräte-/Inodekennungen, darf aber
  nach einem Neustart nicht ohne erneute Identitätsprüfung angewendet werden.
  Ein automatischer Import ist nicht implementiert. Alte Journale früherer
  Wiederherstellungsversuche werden zur Nachvollziehbarkeit belassen.
- Erzwungener Prozessabbruch, Stromausfall und ein böswilliger Prozess mit
  denselben Benutzerrechten beziehungsweise bereits geöffneten Schreibhandles
  sind nicht durch diese Suite als sicher abgenommen. Die App beansprucht keine
  globale Dateisystemsperre und löscht beim Start keine unbekannten Restdateien.
- Die lokale Ad-hoc-Signierung ersetzt weder Developer-ID-Prüfung noch
  Notarisierung. Die Release-Konfiguration der Hardened Runtime bleibt bestehen;
  Xcode deaktiviert sie beim lokalen Ad-hoc-Testlauf. Frische Installation,
  Upgrade und die vollständige Distributionsabnahme bleiben offen.
- Vergleichssemantik, Suchlimits, allgemeine Prozessausgabegrenzen, Performance,
  VoiceOver und CI sind eigene Arbeitspakete aus der Roadmap.
