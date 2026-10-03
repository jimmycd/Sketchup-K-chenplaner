# TpaCAD-Makros der Werkstatt

Quellen: `docs/tpacad_felder_bearbeitungen.pdf` (Handbuch „Felder Bearbeitungen", Seiten 1–18 und 26–29 gelesen) und die
Beispieldateien in `examples/tcn_referenz/`. Das Handbuch benennt die Felder nur mit Kürzeln der Oberfläche; die
`#`-Nummern in der Datei stehen dort nicht. Sie sind unten aus den Beispieldateien **abgeleitet**, nicht dokumentiert.

**Regel (abgeleitet, bestätigt am Topfband):** Bei Feldern der Form `[Rn]` gilt `#85nn` = Rn, also R0 = `#8500`, R7 = `#8507`.
Ausdrücke dürfen `x`, `y`, `s` (Maße der Fläche) verwenden; das Topfband-Beispiel schreibt Dezimalstellen mit Komma
(`9,5`), Setup-Zeilen mit Punkt.

Der Exporter erzeugt diese Makros über den Bearbeitungstyp `makro` (Nummer, Makroname, Parameter 1:1).

## Lochreihe in X – `fittingx`, `W#1001`

| Feld (Handbuch) | `#` | Beleg |
|---|---|---|
| X Anfangsmaß | 8510 | Seite: 55 |
| XF Endmaß (Mindestabstand zum Rand) | 8511 | `x-50`, `x-30` |
| ST Schritt | 8512 | 32 / 64 / 150 |
| Z Bohrungstiefe | 8513 | `-12` (negativ) |
| Y (Querposition der Reihe) | 8518 | 35, `y-35`, 9.5 |
| TD Durchmesser | 8522 | 5, 8, 3 |
| CP auf Werkstück ausgemittelt | 8508 | Boden/Deckel: 1 bei Schritt 150, Rand 30 |
| QP gerade Anzahl | 8509 | dito |
| EY1 doppelte Reihe | 8517 | immer 0 |
| TP Werkzeugart (Durchgang/Blind) | 8525 | immer 0 *(vermutet)* |
| RI / RO (Qri / Qro) | 8520 / 8521 | immer 1 *(vermutet, Bedeutung unklar)* |
| Fläche | `#6=1` | immer 1 *(Bedeutung unklar; SIDE legt die Fläche fest)* |

Mit CP=1 verteilt die Maschine die Bohrungen gleichmäßig zwischen X und XF mit höchstens ST Abstand. Das entspricht dem
Konzept-Modus `randabstand_max`. Mit CP=0 gilt fester Schritt ab X (Konzept-Modus `raster`). Der zweite Y-Wert (Y1) und
der Rest sind in den Beispielen nicht belegt.

## Lochreihe in Y – `fittingy`, `W#1003`
Wie oben, aber entlang Y: `#8510` Y-Anfang, `#8511` YF, `#8518` X-Position. Beleg: `Seite`, `#8518=7.5`, `x-7.5`.

## Topfbandbohrung – `inge100`, `W#1506` (Handbuch S. 12, voll belegt)

| Feld | `#` | Beispiel `T_rR` |
|---|---|---|
| R0 Durchmesser Topfband | 8500 | 35 |
| R1 Durchmesser Nebenlöcher | 8501 | 8 |
| R2 Abstand Nebenlöcher (Zentrum–Zentrum) | 8502 | 45 |
| R3 Abstand Topfband – Nebenlöcher | 8503 | 9,5 |
| R4 Tiefe Topfband | 8504 | 14 |
| R5 Tiefe Nebenlöcher | 8505 | 14 |
| R6 Nebenlöcher andere Seite | 8506 | 1 |
| R7 Einfügemaß X | 8507 | `55+2+16` (= 73) und `55+2+16+576` |
| R8 Einfügemaß Y | 8508 | `y-21,5` (Topfmitte 21,5 vom Rand, d. h. 17,5 + 4 mm) |

Die Türen werden mit der Innenseite oben (F1) bearbeitet; `T_rR` hat nur SIDE 1.

## Formatieren – `squad`, `W#1510` (Handbuch S. 15)
Besäumt/formatiert rechteckige Teile mit Fräser. In allen Beispielen außer der Tür steht es als erste Bearbeitung.
Handbuch-Felder: A Eingangsbogen, OA Ausgangsbogen, T Werkzeug, Z Startpunkt, D Uhrzeigersinn, NG Nesting,
ED Versatz Eingangsbewegung, SS Ausführung in zwei Fräsungen, FSS, MSS. Abgeleitet aus den Beispielen
(`#8500=50 #8501=50 #8502=1000 #8503=-s-2 … #8509=0.5 #8511=-s+1 #8514=10`): 8500/8501 = Ein-/Ausgangsbogen 50,
8503 = Z bis 2 mm durch das Teil. Die Zuordnung der übrigen Nummern ist unklar. Die Formatierung deutet darauf hin, dass
die Maschine das Teil aus einem größeren Rohling besäumt. Die Kopfmaße der Datei sind das Fräsmaß (Fertigmaß minus Anleimer).

## Weitere Funktionen im Handbuch (noch keine `#`-Zuordnung, keine Beispieldatei)

- **Schnitt in X / Y** (Säge, S. 5–6): Anfang/Ende, Querposition Qy/Qx, Tiefe Zp, Nutbreite SL (mehrere Schnitte, wenn breiter als
  das Blatt), Werkzeug-ID T, Sehnenberechnung CORD, Korrektur DN, zweiter Durchlauf Z2EN/Z2. Die Positionen beziehen sich auf die
  Mitte des Sägeblatts.
- **Schnitt in XY** (S. 7–10): beliebige Richtung, Z-Anwendungsmaß, Z absolut, Winkel A, Modul U, Beta.
- **Schnitt horizontal** (S. 11): Schnitt in eine Seitenfläche (FA = 3, 4, 5, 6), aufgerufen in Fläche 1.
- **Schlosskasten** (S. 13–14): R0–R23 für Schlosskasten mit Drücker-/Zylinderloch und Stulp; wird in Fläche 1 aufgerufen,
  bearbeitet Fläche 3 oder 5.
- **Bohrung mit Ausräumen** (S. 26), **Fräser-Setup** (S. 27–29, mit Korrektur, Ein-/Ausgangsstrecke).

Nicht gelesen: Seiten 19–28 und 30–49 des PDFs (Formatieren Z-Offset, Alfa-Beta-Linear, Gewinde, orientiertes Setup,
Fräse-Setup orientiert, verdecktes Türband, ClamexP, Magic Corner).
