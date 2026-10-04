# Sonderschränke

Vorlagen für Geschirrspüler, Spülenschrank mit Mülltrennung, Backofen/Kochfeld und Eckschränke. Alle sind Katalogvorlagen
(`catalog/templates/`) auf Basis von `US-BASIS`, mit wenigen neuen Generatorfunktionen (siehe unten). Beispiel mit allen
Schränken: `examples/projekt_sonderschraenke.json` (`ruby tools/generate.rb examples/projekt_sonderschraenke.json zeile_b out/`).
Was einstellbar ist, steht als Vorlagenparameter und lässt sich im Editor über die Overrides ändern, z. B.
`parameter.anschluss_b.default = 420`.

Konventionen wie im ganzen Projekt: Rohmaß = Fräsmaß + 10 mm, Topfbänder an der 32er-Systemlochreihe, keine Extra-Bohrungen in den Seiten.

## Vorlagen

| Code | Inhalt | Wichtige Parameter |
|---|---|---|
| `US-GS-VOLL` | Geschirrspüler-Nische, vollintegriert: nur vordere und hintere Strebe plus Gerätefront (Höhe wie Schrank) | `breite` 450/600 |
| `US-GS-TEIL` | teilintegriert: Front um die Bedienblende des Geräts kürzer, darüber offen | `bedienblende_h` (90) |
| `US-GS-FREI` | freistehend/unterbaufähig: Nische mit Streben, ohne Front | |
| `US-SPUE` | Spülenschrank: wasserfester Boden, ein hoher Frontauszug (Blum, Abfalltrennsystem) mit U-Ausschnitt im Schubkastenboden, feste Blende oben, Rückwandausschnitt für Anschlüsse | `blende_h`, `anschluss_x/y/b/h`, `siphon_b/t`; Breiten 450 bis 1200 |
| `US-HERD-OFEN` | Backofenschrank (Ofen im Unterschrank): Nische oben (Standard 560 x 550 x 590), tragender Zwischenboden, eine Schublade darunter, keine Traversen, Lüftungsausschnitt in der Rückwand; Kochfeld getrennt | `ofen_nische_h`, `lueftung_b` |
| `US-HERD-KF` | Schrank unter dem Kochfeld mit Muldenlüfter (Abluft in der Herdplatte): 2 Schubladen, Abluftkanal hinten (Boden-Ausschnitt, hintere Traverse entfällt, Schubkasten-NL um die Kanaltiefe kürzer) | `kanal_b/t/x`; Breiten 600/800/900 |
| `HS-BASIS` | Hochschrank-Korpus (abstrakt): Boden, Deckel, Seiten 2100 hoch | |
| `HS-OFEN` | Hochschrank mit Backofen, zwei großen Schubladen (70 kg) darunter und einem Fach mit Tür und Einlegeboden darüber | `schub_zone` (700), `ofen_nische_h` (600), `lueftung_b` |
| `ES-BLIND-L/-R` | Blind-Eckschrank 900 bis 1200: Tür über der Öffnung, daneben eine feste Blindfront; Blindteil links bzw. rechts | `tuer_b` (600) |
| `ES-L-KARUSSELL`, `ES-L-LEMANS` | L-Eckschrank, Ecke hinten links, mit Falttür (zwei Flügel); Karussell bzw. LeMans nur als Zubehör-Vermerk |
| `ES-LR-KARUSSELL`, `ES-LR-LEMANS` | dasselbe als Spiegelbild, Ecke hinten rechts (Topfbänder am linken Schenkelende, gleiche Teil-IDs) | `breite`, `tiefe` (je 900 bis 1200), `schenkel_t` (560) |

## Neue Funktionen im Generator

- Vorlagenparameter außer `breite/hoehe/tiefe` stehen in Formeln als `V.<name>` zur Verfügung.
- `teile_ohne` / `teile_aendern` / `teile_zusatz`: Basisteile streichen, ändern (Felder werden gemischt) oder neue ergänzen.
- `bearbeitungen` je Teilrolle, im Teilsystem. Neuer Typ `ausschnitt` (Mitte `x`/`y`, `laenge`, `breite`, `eckradius`, optional `tiefe`; Standard durchgehend Dicke + 2 mm) wird zu einer geschlossenen Kontur mit Fräserkorrektur links (Abfall innen).
- Frontfelder: feste Höhe (`hoehe`), Teilbreite (`breite`, `ab`), `neben` (steht neben dem vorigen Feld), neue Arten `blende`, `offen` (Öffnung ohne Front) und `eckfront`; Türen mit `beschlag: "keiner"` und `anschlag: "unten"` für Gerätefronten.
- `einbauten`: `geraet` und `auszug_innen` erzeugen keine Teile, prüfen nur das Nischenmaß (Warnung); Einlegeböden mit `bereich` nur in einem Fach.
- Feste Zwischenböden (Rolle `zwischenboden`) bekommen die Gegenstück-Dübel in beiden Seiten.
- `schubkasten` in der Vorlage überschreibt `standards.schubkasten` (z. B. `nl`, `last`).
- `merkmale` steuern Regeln (`gilt_fuer.merkmal` / `ohne_merkmal`): `ohne_boden`, `ohne_traverse`, `deckel`, `ohne_lochreihe`, `ohne_verbindung`. Neue Regeln in `catalog/rules/sonderschraenke.json` (Dübel nur am Bodenende, nur am Traversenende, an beiden Enden bei Hochschränken).
- Frontbefestigung der Schublade: obere Lochpaare entfallen bei niedrigen Fronten (unter 190 bzw. 222 mm), weil sie sonst außerhalb der Front lägen.
- Neues Projektmaterial `korpus.material_wasserfest` (Standard `spano_wasserfest_19`, muss unter `materialien` stehen).

## Annahmen und offene Punkte

1. **Geschirrspüler ohne eigene Seiten.** Die Nische liegt zwischen den Nachbarschränken (lichte Breite 600); die Streben werden mit Schraubwinkeln befestigt, deshalb ohne Dübelbohrungen. Gerätefront-Bohrbild des Herstellers fehlt (`geraetefront_befestigung`, Warnung).
2. **L-Eckschrank (links und rechts).** Grundriss und Maße sind eine Annahme (Schenkeltiefe 560, die Flügel der Falttür liegen an den Fronten der beiden Schenkel). Dübel- und Schraubenbohrungen der L-Teile werden nicht erzeugt (Warnung), ebenso die Faltscharniere (`eck_faltscharnier`) und die Karussell-/LeMans-Beschläge (`eck_karussell`, `eck_lemans`). Vor dem Bau am Probeschrank prüfen.
3. **Fräserkorrektur der Ausschnitte.** Die Kontur läuft gegen den Uhrzeigersinn mit Korrektur links, der Fräser liegt damit im Abfall. Ob das mit dem Maschinenprofil stimmt, ist an der Maschine zu prüfen.
4. **`HS-OFEN`**: Die Lochreihe läuft über die ganze Seite, auch hinter den Schubladen (Warnung `Aussparung nur hinter einem Teil der Fronten`). Das Ausparen einzelner Bereiche ist noch nicht umgesetzt.
5. **Backofenschrank**: Ohne Traversen. Die Arbeitsplatte wird über Winkel an den Seiten befestigt; bei `US-HERD-KF` gibt es bewusst keinen Hitzeschutzboden.
6. **Mülltrennung** ist als Frontauszug mit dem Blum-Abfalltrennsystem vorgesehen. Das System selbst ist kein CNC-Teil (Platzhalter `blum_muellsystem`); der Boden des Schubkastens trägt nur den Siphonausschnitt.
