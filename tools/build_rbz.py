#!/usr/bin/env python3
"""Baut dist/kp_kuechenplaner_<version>.rbz (SketchUp-Erweiterungspaket).

Aufbau im Paket: kp_kuechenplaner.rb (Lader) und kp_kuechenplaner/ mit main.rb, lib/, schemas/, catalog/, examples/.
Aufruf: python3 tools/build_rbz.py
"""
import pathlib
import re
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
PLUGIN = ROOT / "plugin"
VERSION = re.search(r"VERSION = '([^']+)'", (PLUGIN / "kp_kuechenplaner.rb").read_text(encoding="utf-8")).group(1)

EINTRAEGE = [
    (PLUGIN / "kp_kuechenplaner.rb", "kp_kuechenplaner.rb"),
    (PLUGIN / "kp_kuechenplaner" / "main.rb", "kp_kuechenplaner/main.rb"),
]
for ordner, ziel, muster in [
    (ROOT / "lib", "kp_kuechenplaner/lib", "**/*.rb"),
    (ROOT / "schemas", "kp_kuechenplaner/schemas", "*.json"),
    (ROOT / "catalog", "kp_kuechenplaner/catalog", "**/*.json"),
    (ROOT / "examples", "kp_kuechenplaner/examples", "projekt_*.json"),
    (ROOT / "examples" / "profile", "kp_kuechenplaner/examples/profile", "*.json"),
]:
    for datei in sorted(ordner.glob(muster)):
        EINTRAEGE.append((datei, f"{ziel}/{datei.relative_to(ordner).as_posix()}"))

out = ROOT / "dist" / f"kp_kuechenplaner_{VERSION}.rbz"
out.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for quelle, name in EINTRAEGE:
        z.write(quelle, name)
print(f"{out.relative_to(ROOT)}: {len(EINTRAEGE)} Dateien, Version {VERSION}")
