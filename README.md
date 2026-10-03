# SketchUp-Küchenplaner

SketchUp-Plugin, das eine Küche aus einem Standardkatalog plant und jedes Holzteil mit Bohrungen,
Nuten und Fräsungen als TCN-Datei für die CNC ausgibt. Konzept und Schemata: `docs/konzept.md`.

## Stand: Vorbereitung Schritt 1 (MVP)

Schritt 1 der Roadmap: `US-BASIS` + `US-T1`, Generator für Korpusteile, Regeln `r_seite_boden`,
`r_lochreihe`, `r_rueckwand_nut`, Teile in OpenCutList sichtbar, TCN-Export über Profil.
Siehe `docs/schritt1.md` für den Plan, was vorbereitet ist und was noch blockiert.

## Struktur

| Pfad | Inhalt |
|---|---|
| `schemas/` | JSON-Schemata (Draft 2020-12), 1:1 aus dem Konzept |
| `catalog/templates/` | Schranktyp-Vorlagen (`US-BASIS`, `US-T1`) |
| `catalog/rules/` | Konstruktionsregeln |
| `catalog/hardware/`, `catalog/hardware_sets/` | Beschläge und Sets (Bohrbilder noch Platzhalter) |
| `examples/` | Beispielprojekt |
| `tools/validate.py` | Prüft alle Daten gegen die Schemata |

## Prüfen

```
pip install jsonschema referencing
python3 tools/validate.py
```
