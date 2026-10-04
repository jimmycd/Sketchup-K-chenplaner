# SketchUp-Plugin: Installation, Entwicklung, Tests

## Was geprüft ist und was nicht

- **Getestet (automatisch):** Generator, Formel-Auswerter, Exporter und der Ablauf des Plugins gegen eine **SketchUp-Attrappe**
  (`test/support/fake_sketchup.rb`): Menü, Gruppen und Komponenten anlegen, Attribute setzen, TCN schreiben, Fehlerfälle, Neu laden.
- **Nicht getestet:** Die echte SketchUp-API. Ich habe hier kein SketchUp. Abweichungen zwischen Attrappe und echter API (z. B. Flächenorientierung,
  Gruppen-Transformation, Einheiten) zeigen sich erst in SketchUp. Dafür gibt es den **Selbsttest** im Menü und die Ruby-Konsole.
- Läuft mit Ruby 2.7 und neuer (SketchUp 2022+), keine Syntax ab Ruby 3.0.

## Installation (fertiges Paket)

1. `dist/kp_kuechenplaner_0.5.0.rbz` (liegt im Repository).
2. SketchUp: **Fenster → Erweiterungsmanager → Erweiterung installieren** und die `.rbz` wählen, SketchUp neu starten.
3. Menü **Erweiterungen → Küchenplaner**: *Beispielprojekt wählen*, *Editor…*, *Selbsttest*, *Küche generieren*, *TCN exportieren…*.

Neues Paket bauen: `python3 tools/build_rbz.py`. Prüfen, dass es allein (ohne Repository) funktioniert: `python3 tools/verify_rbz.py`.

## Entwicklungsmodus: neue Version testen ohne Neuinstallation

Der Dev-Lader lädt den Küchenplaner direkt aus dem Projektordner. Änderungen gelten nach **Erweiterungen → Küchenplaner (Dev) → Neu laden**,
SketchUp muss nicht neu gestartet werden (`Kp::Dev.reload` in der Ruby-Konsole geht auch).

Einrichten (Windows, PowerShell, einmalig):

```
powershell -ExecutionPolicy Bypass -File tools\setup-windows.ps1
```

Das Skript klont das Projekt nach `E:\sketchup - küchenplaner` (Parameter `-Ziel`, `-Branch`) oder aktualisiert es und legt in jedem
SketchUp-Plugins-Ordner (`%APPDATA%\SketchUp\SketchUp 20xx\SketchUp\Plugins`) die Datei `kp_kuechenplaner_dev.rb` ab, die `dev/kp_dev_loader.rb` aus dem Projekt lädt.

Neue Version holen: im Projektordner `git pull`, in SketchUp **Neu laden**. Nicht zusammen mit der installierten `.rbz` verwenden (im Erweiterungsmanager deaktivieren);
der Dev-Lader meldet es in der Ruby-Konsole.

Einfachster Weg ohne Skript: Projekt von GitHub klonen oder als ZIP herunterladen und entpacken, dann `dev/kp_dev_loader.rb` in den SketchUp-Plugins-Ordner kopieren
(`%APPDATA%\SketchUp\SketchUp 20xx\SketchUp\Plugins`). Der Lader findet den Projektordner selbst (Umgebungsvariable `KP_SRC`, gemerkter Pfad,
`E:/sketchup - küchenplaner`) oder fragt beim ersten Start einmalig danach und merkt ihn sich (*Quellpfad ändern…* im Menü ändert ihn).

Manuell ohne Skript: in der Ruby-Konsole `load 'E:/sketchup - küchenplaner/dev/kp_dev_loader.rb'`.

## Editor für Projekt und Katalog (Menü: Küchenplaner > Editor…)

Ein Dialog (SketchUp-HtmlDialog) bearbeitet die JSON-Dateien, ohne dass man sie von Hand anfassen muss. Die Eingabemasken werden aus den Schemata in `schemas/`
erzeugt: neue Felder im Schema erscheinen automatisch, Auswahlfelder sind Dropdowns, Pflichtfelder sind mit * markiert, Fehler werden am Feld rot angezeigt.

- **Reiter Projekt:** Projektdaten, Standards, Zeilen und Elemente (Baum links). Elemente lassen sich ergänzen, duplizieren, verschieben und löschen.
- **Variable Anzahl:** Im Element zeigt „Anpassung der Vorlage für diesen Schrank“ die Frontfelder (und Einbauten) der Vorlage. Dort kann man Einträge hinzufügen,
  duplizieren, entfernen und verschieben, z. B. drei Schubladen mit eigenem `anteil` oder `hoehe`, alle aus demselben Grundelement des Katalogs.
  Das wird im Projekt als Override (`overrides["front.felder"]`) gespeichert, die Vorlage im Katalog bleibt unverändert. „Auf Vorlage zurücksetzen“ entfernt die Anpassung.
  Weitere Overrides (Punkt-Pfad → Wert) stehen darunter.
- **Reiter Katalog:** Vorlagen, Beschläge, Beschlag-Sets und Regeln bearbeiten oder neu anlegen (die Vorlage erbt dabei von einer wählbaren Basis).
- **Live-Änderung:** Ist die Option gesetzt, wird jede Änderung nach kurzer Pause geprüft, gespeichert und die Küche in SketchUp neu gezeichnet (Gruppe `KP_Projekt` wird ersetzt).
  Ohne Haken führt *Übernehmen* dasselbe aus. Bei Katalogänderungen wird mit dem aktuellen Projekt neu gezeichnet.
- **Sicherheit:** Nur gültige Daten werden gespeichert und gezeichnet (Prüfung gegen die Schemata, Fehler stehen unten im Dialog). Vor dem ersten Überschreiben einer Datei
  entsteht eine Kopie `<datei>.bak`. *Rückgängig* nimmt die letzten Änderungen der geöffneten Datei zurück. Gespeichert wird im Standardformat (2 Leerzeichen Einrückung), die
  Formatierung von Hand geschriebener Dateien kann sich dadurch ändern.
- **Technik:** Oberfläche in `plugin/kp_kuechenplaner/editor/` (HTML/JS ohne Bibliotheken), Logik in `lib/kp/editor/` (`sitzung.rb`, `schema_pruefer.rb`, ohne SketchUp getestet).
  Nicht getestet ist der Dialog in echtem SketchUp (CEF): Die Oberfläche läuft in Chromium mit Attrappe der Brücke, der Rest gegen die SketchUp-Attrappe.

## OpenCutList (Zuschnittlisten und Etiketten)

Beim Generieren setzt das Plugin pro Teil, was OCL aus SketchUp liest. Es schreibt nichts in die internen OCL-Attribute.

| Was | Wie | Für OCL |
|---|---|---|
| Teilname | Name der Komponentendefinition, z. B. `A1 seite_r` (eindeutig je Teil) | Teilename in Liste und Etikett |
| Material | SketchUp-Material auf der Teil-Instanz, Name aus `standards.materialien.<schlüssel>.ocl_material` (sonst `name`) | Material, Schnittliste je Material |
| Anleimer | Kantenmaterial (`standards.kanten.<schlüssel>.ocl_material` oder `name`) auf den schmalen Seitenflächen des Teils: vorne/hinten = y-, y+, links/rechts = x-, x+ | Kantenbild und Kantenmaterial je Seite, Etikett |
| Etikettentext | Beschreibung der Komponentendefinition: Schrank, Teil, Material, Roh-/Fräs-/Fertigmaß, Kantenpositionen und Skizze | im Etikettenlayout als Beschreibung verwendbar |
| Rohdaten | Attribut `kp_part.data` (JSON mit Maßen, Bearbeitungen, `ocl`) | wird von OCL nicht ausgewertet, dient dem TCN-Export |

### OCL-Materialien anlegen (Menü: Küchenplaner > OCL-Materialien anlegen)

Legt alle in der Küche verwendeten Materialien (Platten und Kanten) im Modell an und setzt ihre OpenCutList-Eigenschaften aus den Projektstandards:
Typ (Plattenmaterial / Kantenband), Stärke, Kantenhöhe, Maserung. Danach muss in OCL nichts mehr von Hand eingegeben werden.

- **Weg:** Wenn die OCL-Klasse `Ladb::OpenCutList::MaterialAttributes` vorhanden ist, schreibt das Plugin darüber (`type=`, `std_thicknesses=` …, `write_to_attributes`),
  sonst direkt in das Attributverzeichnis `fr.lairdubois.opencutlist`. Das Ergebnis meldet je Material den Weg und nicht gesetzte Felder.
- **Abbildung:** `catalog/ocl.json` (Typnummern, Attributschlüssel, Einheit). Das ist eine **Annahme**: OCL-Quellcode konnte ich nicht lesen. Stimmt eine Anzeige in OCL nicht,
  *OCL-Attribute anzeigen* ausführen (schreibt die Attribute der Materialien und die Methoden der OCL-Klasse in `kp_ocl_diagnose.txt` im Temp-Ordner), die Datei schicken oder
  die Schlüssel in `catalog/ocl.json` anpassen. Am sichersten: ein Material einmal in OCL von Hand einstellen und die Diagnose danach ansehen.
- Vorhandene Materialien werden wiederverwendet (Farbe bleibt unverändert).

### Etiketten: Rohmaß, Fräsmaß, Fertigmaß und Kantenskizze

Die Beschreibung jeder Komponentendefinition enthält für das OCL-Etikett:

```
Schrank A1 · A1 seite_r
Material: Spanplatte melaminbeschichtet weiß
Rohmaß: 778 × 560 × 19
Fräsmaß: 768 × 550 × 19
Fertigmaß: 772 × 552 × 19
Kanten vorne: ABS weiß 2 mm, links: ABS weiß 2 mm, rechts: ABS weiß 2 mm
+────────────+
║            │   (Skizze, Ansicht auf Fläche 1: ═ ║ = Anleimer)
...
```

- **Fertigmaß:** Konstruktionsmaß in SketchUp inkl. Anleimer. **Fräsmaß:** Kopf der TCN-Datei, Fertigmaß minus Anleimer. **Rohmaß:** Zuschnitt = Fräsmaß + 10 mm
  je Richtung (`standards.zuschnitt.aufmass`, Standard 10, einstellbar).
- **Skizze:** unten = Kante `vorne` des Teilsystems (y = 0), oben = `hinten`, links = x 0, rechts = x L, jeweils gesehen auf Fläche 1; `═`/`║` bedeutet Anleimer.
  In OCL (Etikettenlayout) das Element *Beschreibung* einblenden und eine Schrift mit gleicher Zeichenbreite (z. B. Courier) wählen. OCL zeigt die Kanten außerdem selbst als Symbole, da das
  Kantenmaterial auf den richtigen Seitenflächen liegt.
- Der TCN-Export rechnet die Kanten selbst; die Information geht nur wegen der Etiketten an OCL.

## Projektdatei

Pfade in `projekt.json` (`kataloge`, `standards.maschine.exporter_profil`) gelten **relativ zur Projektdatei**. Ohne `kataloge` wird der mitgelieferte Katalog verwendet.
Das Beispielprojekt `examples/projekt_mueller.json` liegt im Paket und im Repository.

## Tests

```
for f in test/test_*.rb; do ruby $f; done
python3 tools/validate.py
python3 tools/verify_rbz.py
```
