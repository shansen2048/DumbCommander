# ADR 0002: Konflikte und sichere Dateioperationen

- Status: angenommen
- Datum: 2026-08-31

## Kontext

Dateioperationen wurden im Prototyp unmittelbar aus `ContentView` gestartet.
Zielkollisionen konnten nur pauschal scheitern; Planung, Fortschritt, Abbruch und
strukturierte Teilergebnisse fehlten. Ein Commander muss vor jeder Mutation
eindeutig festlegen, welche Quellen und Ziele betroffen sind.

## Entscheidung

Jede mutierende Aktion durchläuft drei getrennte Phasen:

1. `FileOperationCoordinator.plan` normalisiert und validiert Quelle und Ziel,
   ermittelt Größen und erzeugt explizite Konflikte.
2. Die Oberfläche sammelt Entscheidungen, ohne bereits Dateien zu verändern.
3. `FileOperationCoordinator.execute` führt den unveränderlichen Plan über
   `FileSystemServing` aus und liefert einen strukturierten Bericht.

Konflikte verwenden ausschließlich folgende Entscheidungen:

- `replace`: Das neue Element wird zunächst vollständig als temporäres
  Geschwisterelement erzeugt und erst danach an die Stelle des Ziels gesetzt.
- `skip`: Quelle und Ziel bleiben unverändert.
- `keepBoth`: Ein deterministischer Name mit „Kopie“-Suffix wird verwendet.
- `merge`: Nur für zwei echte Verzeichnisse. Nicht kollidierende Inhalte
  werden übernommen; verschachtelte Zielkonflikte bleiben unverändert und
  erscheinen einzeln als übersprungen im Bericht.
- `cancel`: Vor Ausführungsbeginn bleibt die gesamte Operation unverändert;
  während der Ausführung stoppt sie am nächsten Abbruchpunkt.

„Für alle“ gilt nur für spätere Konflikte mit derselben Kombination aus Quell-
und Zieltyp. Eine Entscheidung für zwei Verzeichnisse wird beispielsweise nicht
auf einen Datei-gegen-Datei-Konflikt übertragen.

Reguläre Dateien werden blockweise kopiert. Zwischen Blöcken und rekursiven
Einträgen werden Abbruchpunkte geprüft. Symbolische Links werden bei
Dateioperationen als Linkobjekte kopiert und nie traversiert. Das in ADR 0004
beschlossene explizite Öffnen eines Linkziels ändert diese Operationssemantik
nicht.

## Folgen

Es gibt kein stilles Überschreiben und keinen impliziten Wechsel zu einer
destruktiveren Strategie. Große Einzeldateien liefern Fortschritt und können
abgebrochen werden. Unvollständige neue Kopierziele werden bei Fehler oder
Abbruch entfernt; die Quelle bleibt erhalten.

Ein Verschieben fällt ausschließlich bei `EXDEV`, also einem Wechsel des
Dateisystems, kontrolliert auf Kopieren und anschließendes Entfernen der Quelle
zurück. Andere Fehler werden unverändert gemeldet. Schlägt das Entfernen nach
erfolgreichem Kopieren fehl, bleibt die Quelle bestehen und der Bericht weist
den Teilzustand ausdrücklich aus.

Die aktuelle Verzeichniszusammenführung entscheidet verschachtelte Konflikte
bewusst nicht automatisch neu. Eine spätere erweiterte Konfliktoberfläche darf
diese Semantik erweitern, aber niemals bestehende Ziele ohne erneute explizite
Entscheidung ersetzen.
