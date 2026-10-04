#!/usr/bin/env python3
"""Validiert Katalog- und Projektdateien gegen die JSON-Schemata in schemas/.

Aufruf: python3 tools/validate.py            (alles prüfen)
        pip install jsonschema referencing    (Voraussetzung)
"""
import json
import pathlib
import sys
from pathlib import Path

from jsonschema import Draft202012Validator
from referencing import Registry, Resource

ROOT = Path(__file__).resolve().parent.parent
SCHEMAS = ROOT / "schemas"

# Datei-Glob -> Schema; Listen (Regeldateien) werden elementweise geprüft
TARGETS = [
    ("catalog/templates/*.json", "vorlage"),
    ("catalog/hardware/*.json", "beschlag"),
    ("catalog/hardware_sets/*.json", "beschlagset"),
    ("catalog/rules/*.json", "regel"),
    ("examples/projekt_*.json", "projekt"),
    ("examples/teil_*.json", "teil"),
    ("examples/profile/*.json", "tcnprofil"),
]


def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def build_registry():
    registry = Registry()
    for f in SCHEMAS.glob("*.schema.json"):
        doc = load(f)
        registry = registry.with_resource(doc["$id"], Resource.from_contents(doc))
    return registry


def pruefe_generierte_teile(registry):
    """Erzeugt mit dem Generator (Ruby) die Teile des Beispielprojekts und prüft sie gegen teil.schema.json."""
    import shutil
    import subprocess
    import tempfile

    if shutil.which("ruby") is None:
        print("Hinweis: ruby nicht gefunden, generierte Teile werden nicht geprüft")
        return 0
    fehler = 0
    validator = Draft202012Validator(load(SCHEMAS / "teil.schema.json"), registry=registry)
    for projekt in sorted((ROOT / "examples").glob("projekt_*.json")):
        with tempfile.TemporaryDirectory() as tmp:
            r = subprocess.run(["ruby", str(ROOT / "tools" / "generate.rb"), str(projekt), "-", tmp], capture_output=True, text=True)
            if r.returncode != 0:
                print(f"FEHLER Generator ({projekt.name}):", r.stderr[-300:])
                return 1
            for datei in sorted(pathlib.Path(tmp).glob("*.json")):
                for err in validator.iter_errors(load(datei)):
                    fehler += 1
                    loc = "/".join(map(str, err.absolute_path)) or "(Wurzel)"
                    print(f"FEHLER generiertes Teil {datei.name} [{loc}]: {err.message[:150]}")
            print(f"{len(list(pathlib.Path(tmp).glob('*.json')))} generierte Teile aus {projekt.name} gegen teil.schema.json geprüft")
    return fehler


def main():
    registry = build_registry()
    errors = placeholders = checked = 0
    for pattern, name in TARGETS:
        schema = load(SCHEMAS / f"{name}.schema.json")
        validator = Draft202012Validator(schema, registry=registry)
        for path in sorted(ROOT.glob(pattern)):
            data = load(path)
            checked += 1
            for item in (data if isinstance(data, list) else [data]):
                for err in sorted(validator.iter_errors(item), key=lambda e: list(e.path)):
                    errors += 1
                    loc = "/".join(map(str, err.absolute_path)) or "(Wurzel)"
                    print(f"FEHLER {path.relative_to(ROOT)} [{loc}]: {err.message[:200]}")
            placeholders += path.read_text(encoding="utf-8").count('"<')
    errors += pruefe_generierte_teile(registry)
    print(f"{checked} Dateien geprüft, {errors} Fehler, {placeholders} offene Platzhalter (<...>)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
