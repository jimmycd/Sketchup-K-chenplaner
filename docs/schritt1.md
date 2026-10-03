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
| 1 | Profit H200, 4 Achsen, TpaCAD (Format 4, TPACAD 4.0), Spezifikation in `docs/tpacad_format4_spec.pdf`. Bearbeitbar: F1, F3, F4, F5, F6 (**nicht F2**). Nutsäge X/Y, Nutfräser 8 mm, Graviermesser V und rund | `examples/profile/werkstatt.tcnprofil.json` angelegt |
| 2 | F1: Bohrer in allen Durchmessern, Lochreihenbohrer, Forstner (Topfband). Seitenflächen: Horizontalbohrer, Schlosskastenaggregat | Werkzeugliste im Profil; Durchmesser noch `null` |
| 3 | Alle Standarddurchmesser vorhanden | keine Werkzeug-Durchmesser nötig |
| 3b | Beschläge: später | Entwürfe bleiben ungeprüft |
| 4 | Unterschrank: Seiten durchgehend. Oberschrank: mit Deckel (aufgesetzt) | `bauweise` je Kategorie nötig, siehe unten |
| 5 | Eigenständiges Plugin, nutzt OCL; TCN-Export direkt, ohne DXF- oder OCL-Export | Exporter liest `kp_part` direkt |
| 6 | OCL zieht Kanten nicht ab; Fräsmaß = Fertigmaß − Anleimer (2 mm sichtbare Kanten) | siehe „Fertigmaß, Fräsmaß und Anleimer" |
| 7 | Katalog zunächst im Plugin, später Netzlaufwerk | Katalogpfade bleiben konfigurierbar (`kataloge` im Projekt) |

### Folgen für das Datenmodell

- **Flächennummern unterscheiden sich.** Konzept: F3 vorne, F4 hinten, F5 links, F6 rechts. TpaCAD: 3 vorne,
  4 rechts, 5 hinten, 6 links. Das Profil mappt `F1→1, F3→3, F4→5, F5→6, F6→4` (die erste Profilfassung mit
  Identität war falsch und ist korrigiert). Die Teil-Achsen stimmen mit TpaCAD überein (x Länge, y Breite, z Dicke,
  Ursprung links vorne unten), Tiefen werden negativ ausgegeben (`#3=-Tiefe`).
- **F2 nicht bearbeitbar** (laut Profil). Bearbeitungen auf F2 gehen in eine zweite Datei `<uid>_B.tcn`
  (zweite Aufspannung, Teil um die Längsachse gewendet: `y' = W − y`). Achse einstellbar (`wenden.spiegeln`).
- **Kantenbearbeitungen (F3–F6):** Koordinate entlang der Kante (`x` bei F3/F4, `y` bei F5/F6) und Höhe in der
  Dicke `z` (gemessen von F2, Default Mitte). Das war im Konzept nicht eindeutig festgelegt.
- **Bauweise je Kategorie.** Unterschrank `seiten_durchgehend`, Oberschrank mit aufgesetztem Deckel
  (`seiten_durchgehend_deckel_aufgesetzt`). `HS-BASIS` folgt in Roadmap-Punkt 4.
- **Fertigmaß, Fräsmaß und Anleimer (bestätigt).** SketchUp arbeitet mit dem Fertigmaß (inkl. Anleimer, sichtbare
  Kanten 2 mm). Die Kopfmaße `DL/DH/DS` der TCN-Datei sind das **Fräsmaß = Fertigmaß − Anleimer**; OpenCutList zieht
  die Kanten nicht ab. Im Teil (Schema 4) steht dafür `kantenstaerke` je Seite (`vorne`, `hinten`, `links`, `rechts`
  in mm, vom Generator aus den OCL-Kanten aufgelöst). Der Exporter rechnet:
  `DL = L − links − rechts`, `DH = W − vorne − hinten`; alle Koordinaten verschieben sich um Anleimer links (x) und
  vorne (y), bei gewendeten Teilen um die Gegenseite. Auf einer beklebten Kantenfläche (F3–F6) wird die Tiefe um deren
  Anleimer verringert. Die Rechnung ist je Kante exakt, nicht symmetrisch „/2" (bei Kante nur vorne ist die Verschiebung
  2 mm, nicht 1 mm). Das Beispiel stimmt mit den Maschinendateien: `Boden` Fertig 862 × 560, Kante vorne 2 → 862 × 558;
  `Seite` Fertig 720 × 560, Kanten vorne und je an beiden Enden 2 → 716 × 558.
  Die frühere Profiloption `bearbeitung_auf` ist entfernt.

## TCN-Export (implementiert)

`lib/kp/tcn/exporter.rb` (Ruby, ohne SketchUp-Abhängigkeit) schreibt aus einem Teil (Schema 4) und dem Profil
TpaCAD-Dateien nach `docs/tpacad_format4_spec.pdf`. Aufruf: `ruby tools/export_tcn.rb teil.json profil.json ausgabe/`,
Tests: `ruby test/test_exporter.rb` (12 Tests).

| Konzept | TpaCAD | Stand |
|---|---|---|
| `bohrung` | `W#81 ::WTp` (nach Durchmesser, `#1002`) | fertig |
| `bohrreihe` | Makro `fittingx` (`W#1001`) / `fittingy` (`W#1003`); mit `ausgemittelt` verteilt die Maschine gleichmäßig (Rand `ende`, Abstand höchstens `raster`) | fertig, Parameter aus Beispielen abgeleitet |
| `nut` achsparallel auf F1 | Säge X `W#1050` / Säge Y `W#1051` (Breite > Blatt: `#8503`); sonst Nutfräser, 2 Bahnen bei Breite > Fräser | fertig, ungetestet an Maschine |
| `kontur` | `W#89 ::WTs` + `W#2201` Linie, `W#2101` Bogen, Fräserkorrektur `#40` | fertig, ungetestet an Maschine |
| `tasche`, `saegeschnitt` | – | meldet „noch nicht implementiert" |

Prüfungen vor dem Schreiben: Position im Teil, Restwand (`pruefungen.min_restwand`), Werkzeug im Profil vorhanden.
Teile mit Fehlern werden nicht geschrieben, die Fehlerliste nennt Teil und Bearbeitung.

### Abgleich mit den Beispieldateien (`examples/tcn_referenz/`)

Aus `Seite`, `Boden`, `Deckel`, `Strebe`, `T_rR` übernommen bzw. bestätigt:

- **Flächen und Achsen bestätigt:** Kantenbohrungen am Boden liegen auf SIDE 4 und 6 mit `#8518=9.5` (= Dicke/2) und
  `x-30` entlang der Kante; SIDE 2 wird nie verwendet. Das passt zu Mapping, Achsen und „z von F2, Default Mitte".
- **CRLF** bestätigt. Dateikopf, `::SIDE=`, `'tcn version`, die Blöcke `EXE … LINK` und `SIDE#0,1,3,4,5,6` mit
  `$=F #n` schreibt der Exporter jetzt wie die Maschinendateien (Test vergleicht gegen `Seite.tcn`).
- **Bohrung `W#81`:** `#201=1 #203=1 #1001=0` (statt `#1001=1`), wie in `Seite.tcn`.
- **Makros:** Die Werkstatt arbeitet mit Makros: `fittingx`/`fittingy` (`W#1001`/`W#1003`, Bohrreihen und verteilte
  Bohrungen, z. B. `#8512=150` mit `#8508=1` = gleichmäßig mit max. 150 mm Abstand, `#8518` = Querposition,
  `#8522` = Durchmesser, `#8513` = Tiefe), `inge100` (`W#1506`, Topfband: Ø35, Nebenlöcher Ø8, Position `#8507`/`#8508`)
  und `squad` (`W#1510` = Formatieren/Besäumen, steht in jeder Datei außer der Tür). Die Parameterzuordnung steht in `docs/tpa_makros.md`.
  Neu: Bearbeitungstyp **`makro`** (Schema 4 und Beschlag-Bohrbild) reicht Nummer, Makroname und Parameter 1:1
  durch; ein Test erzeugt die `T_rR`-Zeile damit exakt. So können Beschläge (Topfband, Verbinderreihe) später
  direkt auf eure Makros zeigen, ohne dass ich deren Bedeutung raten muss.
- **Maße im Kopf:** `Boden` 862 × 558, `Seite` 716 × 558, `Strebe` 562 × 100 sind Fräsmaße (Fertigmaß minus 2 mm Anleimer).

### Weitere Auffälligkeiten der Spezifikation

- Säge-Typ `#8509`: Tabelle nennt für Säge X „=1", das Beispiel nutzt 0 (X), 1 (Y), 2 (XY). Ich verwende 0/1.
  In den Beispieldateien kommt keine Säge vor, bleibt also ungeprüft.
- Vorschubwerte (`#2005`, `#2002`, `#9012`, `#9013`) werden nicht geschrieben; die Beispieldateien enthalten sie bei
  `W#81` ebenfalls nicht.
- Bohrreihen laufen wie gewünscht über `fittingx`/`fittingy` (entschieden). Auf Kantenflächen gelten Koordinaten der Fläche: `start` = [entlang der Kante, Höhe in der Dicke], Richtung `+x`/`-x`.

## Noch offen

- **Werkzeugnummern** (TpaCAD-Nummer von Nutsäge X, Nutsäge Y, Nutfräser 8 mm, ggf. weiteren Fräsern) in
  `examples/profile/werkstatt.tcnprofil.json` (`nummer`, bei Sägen auch Blattbreite `d`). Ohne sie bricht der
  Export von Nuten mit Meldung ab. Alle anderen Durchmesser sind laut dir vorhanden, Bohrungen brauchen keine Nummer.
- **Beschläge:** später, die Entwurfswerte in `catalog/hardware/` bleiben bis dahin ungeprüft.
- **Fragen zu den Beispielen:** (2) `squad` = Formatieren (laut Handbuch): soll es in jede Datei, und mit welchen Werten? (4) Bedeutung von `#8508`/`#8509`/`#8517`/`#8520`/`#8521`, falls es eine Makrodoku gibt. (5) Nuten: Beispiel mit Säge oder Fräser?
- Anleimerlogik ist geklärt (siehe oben). Offen: ob die Kantenseiten der Seitenteile (Seite: oben und unten je 2 mm?) so stimmen und wie der Generator die OCL-Kanten pro Teil in `kantenstaerke` übersetzt.

## Noch nicht begonnen (hängt an Antworten oder folgt als Code)

1. Ruby-Gerüst des Plugins (Extension-Registrierung, Menü, eigenständig, OCL als Abhängigkeit)
2. Formel-Auswerter (`=B-2*S`, `min/max/round/floor/ceil`, `P.`/`V.`-Pfade)
3. Generator: Vererbung, Teile berechnen, Kontakte erkennen, Regeln nach Priorität, Beschläge platzieren
4. Ablage in `kp_part.data`, OCL-Material und -Namen setzen
5. TCN-Exporter an SketchUp-Teile anbinden (liest `kp_part.data`); der Schreiber selbst ist fertig (siehe oben)
6. Probeschrank fräsen und montieren (Abnahmetest)
