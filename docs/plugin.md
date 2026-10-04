# SketchUp-Plugin: Installation, Entwicklung, Tests

## Was geprüft ist und was nicht

- **Getestet (automatisch):** Generator, Formel-Auswerter, Exporter und der Ablauf des Plugins gegen eine **SketchUp-Attrappe**
  (`test/support/fake_sketchup.rb`): Menü, Gruppen und Komponenten anlegen, Attribute setzen, TCN schreiben, Fehlerfälle, Neu laden.
- **Nicht getestet:** Die echte SketchUp-API. Ich habe hier kein SketchUp. Abweichungen zwischen Attrappe und echter API (z. B. Flächenorientierung,
  Gruppen-Transformation, Einheiten) zeigen sich erst in SketchUp. Dafür gibt es den **Selbsttest** im Menü und die Ruby-Konsole.
- Läuft mit Ruby 2.7 und neuer (SketchUp 2022+), keine Syntax ab Ruby 3.0.

## Installation (fertiges Paket)

1. `dist/kp_kuechenplaner_0.2.0.rbz` (liegt im Repository).
2. SketchUp: **Fenster → Erweiterungsmanager → Erweiterung installieren** und die `.rbz` wählen, SketchUp neu starten.
3. Menü **Erweiterungen → Küchenplaner**: *Beispielprojekt wählen*, *Selbsttest*, *Küche generieren*, *TCN exportieren…*.

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

## Projektdatei

Pfade in `projekt.json` (`kataloge`, `standards.maschine.exporter_profil`) gelten **relativ zur Projektdatei**. Ohne `kataloge` wird der mitgelieferte Katalog verwendet.
Das Beispielprojekt `examples/projekt_mueller.json` liegt im Paket und im Repository.

## Tests

```
for f in test/test_*.rb; do ruby $f; done
python3 tools/validate.py
python3 tools/verify_rbz.py
```
