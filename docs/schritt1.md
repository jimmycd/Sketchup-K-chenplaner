# Schritt 1 (MVP) – Vorbereitung

Ziel laut Konzept: ein einzelner Unterschrank (`US-T1` auf `US-BASIS`), der als korrekte TCN-Datei an der
Maschine läuft. Quelle: `docs/konzept.pdf` (Roadmap Punkt 1).

## Bereits vorbereitet

- [x] Alle 9 JSON-Schemata aus dem Konzept (`schemas/`), validierbar mit `tools/validate.py`
- [x] Vorlagen `US-BASIS` (abstrakt, Korpus) und `US-T1` (1 Tür, 1 Einlegeboden)
- [x] Die drei MVP-Regeln `r_seite_boden`, `r_lochreihe`, `r_rueckwand_nut`
- [x] Beschlag-Entwürfe (Minifix, Topfband) und Set `haefele_standard` – **mit Platzhaltern `<...>`**
- [x] Beispielprojekt `examples/projekt_mueller.json` mit einem `US-T1` (A1, 450 mm)

## Blockiert durch offene Fragen (Konzept, Abschnitt „Offene Fragen")

| # | Frage | Blockiert |
|---|---|---|
| 1 | Welche Maschine / Steuerungssoftware liest die TCN-Dateien? | Exporter-Profil: Flächennummern, TCN-Bausteine (`tcnprofil`) |
| 2 | Welche Werkzeuge im Magazin (Durchmesser, Horizontalbohrkopf, Säge)? | Werkzeugliste im Profil, Prüfung „Werkzeug verfügbar" |
| 3 | Welche Beschlagssysteme standardmäßig (Schubkasten, Topfband, Verbinder)? | echte Bohrbilder, Artikelnummern; Platzhalter in Beschlägen |
| 4 | Bauweise: Seiten oder Boden durchgehend? Traversen oder Deckel? | `bauweise` im Projekt; `US-BASIS` ist derzeit auf seiten_durchgehend + Traversen gesetzt (Annahme aus dem Konzept-Beispiel) |
| 5 | Eigenständig oder als OCL-Erweiterung? | Menü-/Plugin-Struktur |
| 6 | Kanten vor Zuschnitt abziehen (Zuschnittmaß) oder macht das OCL? | `vorher_abziehen` bzw. `zuschnittmass` im Teil |
| 7 | Katalog lokal im Plugin-Ordner oder Netzordner? | Katalogpfade, Ladelogik |

Zusätzlich fehlen konkrete Angaben: Bohrmaße der Beschläge aus Datenblättern (Minifix Bohrmaß `b`, Tiefen),
Dübel `duebel_8x35`, `bodentraeger_5mm`, `sockelfuss_100`, Topfband 155°. Diese Beschläge sind im Set
referenziert, aber noch nicht angelegt.

## Noch nicht begonnen (hängt an Antworten oder folgt als Code)

1. Ruby-Gerüst des Plugins (Extension-Registrierung, Menü) – hängt an Frage 5
2. Formel-Auswerter (`=B-2*S`, `min/max/round/floor/ceil`, `P.`/`V.`-Pfade)
3. Generator: Vererbung, Teile berechnen, Kontakte erkennen, Regeln nach Priorität, Beschläge platzieren
4. Ablage in `kp_part.data`, OCL-Material und -Namen setzen
5. TCN-Exporter mit Profil (csv2tcn-Logik einbinden – wo liegt csv2tcn? bitte Repo/Pfad nennen)
6. Probeschrank fräsen und montieren (Abnahmetest)
