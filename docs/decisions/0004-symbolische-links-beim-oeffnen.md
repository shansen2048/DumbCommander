# ADR 0004: Symbolische Links beim Öffnen

- Status: angenommen
- Datum: 2026-09-01

## Kontext

Symbolische Links müssen für sichere Dateioperationen eigenständige Objekte
bleiben. Für die tägliche Navigation ist es jedoch überraschend, wenn Enter,
F3, F4, Favoriten oder eine direkte Pfadangabe ein vorhandenes Linkziel nicht
öffnen können.

## Entscheidung

DumbCommander trennt explizites Öffnen von mutierenden Dateioperationen:

- Enter auf einem Verzeichnis-Link navigiert zum aufgelösten Ziel.
- Enter und F3 auf einem Datei-Link öffnen das Ziel im internen Viewer.
- F4 übergibt das aufgelöste Dateiziel an den konfigurierten Editor.
- Direkte Pfade, Favoriten und gespeicherte Sitzungspfade dürfen einen
  Verzeichnis-Link kontrolliert auflösen.
- Relative und absolute Linkziele sowie Linkketten werden unterstützt.
- Bereits besuchte Pfade erkennen Zyklen; zusätzlich endet die Auflösung nach
  höchstens 40 Verweisen. Defekte Links, Zyklen und nicht lesbare Ziele liefern
  einen verständlichen Fehler.

Kopieren, Verschieben, Umbenennen und Papierkorb erhalten weiterhin den
ursprünglich ausgewählten Link. Verzeichnislesen und rekursive Operationen
steigen nicht implizit in Linkziele ein. Finder-Aliase sind von dieser
Entscheidung nicht umfasst.

## Folgen

Die interaktive Navigation entspricht dem erwarteten Commander-Verhalten,
ohne die Sicherheitsgarantien der Dateioperationen abzuschwächen. Nach dem
Öffnen zeigt die Pfadleiste den tatsächlich aufgelösten Zielpfad. Dadurch sind
Verlauf und Sitzungswiederherstellung eindeutig und reproduzierbar.
