# Schritt 1 (MVP) – Vorbereitung

Ziel laut Konzept: ein einzelner Unterschrank (`US-T1` auf `US-BASIS`), der als korrekte TCN-Datei an der
Maschine läuft. Quelle: `docs/konzept.pdf` (Roadmap Punkt 1).

## Bereits vorbereitet

- [x] Alle 9 JSON-Schemata aus dem Konzept (`schemas/`), validierbar mit `tools/validate.py`
- [x] Vorlagen `US-BASIS` (abstrakt, Korpus) und `US-T1` (1 Tür, 1 Einlegeboden)
- [x] Die drei MVP-Regeln `r_seite_boden`, `r_lochreihe`, `r_rueckwand_nut`
- [x] Beschlag-Entwürfe (Minifix, Topfband) und Set `haefele_standard` – **mit Platzhaltern `<...>`**
- [x] Beispielprojekt `examples/projekt_mueller.json` mit einem `US-T1` (A1, 450 mm)

## Antworten auf die offenen Fragen (Stand 2026-10-03)

| # | Antwort | Auswirkung |
|---|---|---|
| 1 | Profit H200, 4 Achsen, TpaCAD (Format 4, TPACAD 4.0). Bearbeitbar: F1, F3, F4, F5, F6 (**nicht F2**). Nutsäge X/Y, Nutfräser 8 mm, Graviermesser V und rund | `examples/profile/werkstatt.tcnprofil.json` angelegt |
| 2 | F1: Bohrer in allen Durchmessern, Lochreihenbohrer, Forstner (Topfband). Seitenflächen: Horizontalbohrer, Schlosskastenaggregat | Werkzeugliste im Profil; Durchmesser noch `null` |
| 3 | Austauschbar/konfigurierbar, Häfele als Referenz | Entwurfswerte in `catalog/hardware/`, ungeprüft |
| 4 | Unterschrank: Seiten durchgehend. Oberschrank: mit Deckel (aufgesetzt) | `bauweise` je Kategorie nötig, siehe unten |
| 5 | Eigenständiges Plugin, nutzt OCL; TCN-Export direkt, ohne DXF- oder OCL-Export | Exporter liest `kp_part` direkt |
| 6 | OCL zieht Kanten nicht ab; Fräsoffset aus Zuschnittmaß minus Fertigmaß | siehe „Fräsoffset" |
| 7 | Katalog zunächst im Plugin, später Netzlaufwerk | Katalogpfade bleiben konfigurierbar (`kataloge` im Projekt) |

### Folgen für das Datenmodell

- **F2 nicht bearbeitbar.** Bearbeitungen auf F2 (z. B. Topfbänder in der Tür, Schrank-Unterseite) muss der Exporter
  durch Wenden auf F1 abbilden (`wenden: true`, Koordinaten spiegeln). Das ist eine Exporter-Aufgabe, keine
  Katalog-Änderung. Das Profil enthält deshalb kein `F2`.
- **Bauweise je Kategorie.** `projekt.standards.bauweise` ist heute ein Einzelwert. Unterschrank
  `seiten_durchgehend`, Hängeschrank `seiten_durchgehend_deckel_aufgesetzt`. Vorschlag: Regeln und Vorlagen
  bekommen ihre Bauweise über `gilt_fuer.kategorien` (Regel) bzw. Vorlagen-Basis (`HS-BASIS`), das Projekt-Feld
  bleibt Vorgabe. Für Schritt 1 (nur Unterschrank) ist nichts zu ändern; `HS-BASIS` folgt in Roadmap-Punkt 4.
- **Fräsoffset.** OCL liefert das Zuschnittmaß ohne Kantenabzug. Ausgegeben wird das Fertigmaß. Der Exporter
  rechnet den Offset je Seite als `(Zuschnittmaß − Fertigmaß) / 2`, da der Unterschied auf beide Seiten
  verteilt wird. **Bitte bestätigen:** in der Nachricht stand „/7", ich lese das als Tippfehler für „/2".

## Noch offen

- **TPA-Format:** Das Autodesk-Forum ist aus dieser Umgebung nicht erreichbar (Proxy 403). Ohne die Spezifikation
  (`FORMAT4_TPACAD_4_0_CODE_DEFINITION`) bleiben die Bausteine im Profil Platzhalter (`<TPA ...>`). Bitte PDF
  hochladen oder ins Repo legen (z. B. `docs/`). Besser noch: eine echte, von der Maschine akzeptierte
  `.tcn`-Datei mit Bohrung, Bohrreihe, Nut und Horizontalbohrung als Referenz.
- Durchmesser aller Werkzeuge (Horizontalbohrer, Nutsägeblätter, Gravurmesser, Reihenbohrkopf).
- Beschläge: Die Entwürfe (Minifix, Dübel 8x35, Bodenträger, Sockelfuß, Topfbänder) enthalten Standardwerte bzw.
  Platzhalter und sind **nicht** gegen Häfele-Datenblätter geprüft; Artikelnummern fehlen. Ich kann die
  Datenblätter nicht abrufen. Bitte konkrete Artikelnummern oder Datenblatt-PDFs liefern.
- Ort der csv2tcn-Logik (Repo/Pfad).
- Annahme `/2` beim Fräsoffset bestätigen.

## Noch nicht begonnen (hängt an Antworten oder folgt als Code)

1. Ruby-Gerüst des Plugins (Extension-Registrierung, Menü, eigenständig, OCL als Abhängigkeit)
2. Formel-Auswerter (`=B-2*S`, `min/max/round/floor/ceil`, `P.`/`V.`-Pfade)
3. Generator: Vererbung, Teile berechnen, Kontakte erkennen, Regeln nach Priorität, Beschläge platzieren
4. Ablage in `kp_part.data`, OCL-Material und -Namen setzen
5. TCN-Exporter mit Profil (csv2tcn-Logik einbinden – wo liegt csv2tcn? bitte Repo/Pfad nennen)
6. Probeschrank fräsen und montieren (Abnahmetest)
