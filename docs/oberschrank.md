# Oberschrank (Hängeschrank), Grundtyp

Vorlagen: `OS-BASIS` (abstrakt, Korpus) und `OS-T1` (Grundvorlage: 1 Tür, 1 Einlegeboden). Varianten (Doppeltür, Klappe, Glas usw.) erben von `OS-BASIS` und setzen nur `front`/`einbauten`.

## Aufbau
- Seiten durchgehend über die volle Tiefe (Standard `tiefen.hs` = 350, Höhe `hoehen.korpus_hs` = 720).
- Boden und voller Deckel zwischen den Seiten, keine Traversen. Beide enden an der Vorderkante der Rückwand (Tiefe = T − Versatz − Rückwandstärke).
- Rückwand genutet, von oben einschiebbar: die Nut in den Seiten läuft durch (Regeln `r_os_nut_seite_l/_r`). Rückwand = Innenbreite + 2 × (Nuttiefe − Luft) breit, 1 mm niedriger als die Seiten.
- Der Boden stößt hinten gegen die Rückwand; sie wird mit dem Boden verschraubt (Ø3 durch in der Rückwand, Vorbohrung Ø3 × 25 in der Hinterkante des Bodens, 3 Stück).
- Dübel und Schrauben Seite zu Boden/Deckel: Regel `r_os_seite_verbindung`, Lage nach der Boden-/Deckeltiefe `V.tb`.

## Aufhängesystem und Rückwandversatz
`aufhaengung.beschlag` wählt den Schrankaufhänger (Standard `set:schrankaufhaenger` aus dem Beschlag-Set, aktuell `haefele_aufhaenger_unsichtbar`). Je Schrank umschaltbar mit dem Override `aufhaengung.beschlag` = `haefele_aufhaenger_sichtbar` oder `haefele_aufhaenger_unsichtbar`.

Der Rückwandversatz (Abstand der Rückwand-Rückseite von der Hinterkante der Seiten, Aufhängeraum bzw. Schattenfuge) wird daraus abgeleitet: `versatz = Haken-Mindestmaß des Beschlags (haken_tiefe, 14 aus den Häfele-Skizzen) + luft_aufhaenger (2)` = 16. Einstellbar über Overrides `parameter.luft_aufhaenger.default` oder direkt `parameter.versatz.default`.

## Offen
- Die Bohrbilder der Aufhänger fehlen noch (Beschläge haben `bohrbilder: []`, Generator warnt). Aus den Skizzen sind nur Maß 14 / ≥14 sicher übernommen.
- Der sichtbare Aufhänger belegt oben unter dem Deckel etwa 46 mm Höhe und 55–60 mm Tiefe; das wird für Einlegeböden noch nicht berücksichtigt.
- Beispielprojekt: `examples/projekt_oberschrank.json`, Tests: `test/test_oberschrank.rb`.
