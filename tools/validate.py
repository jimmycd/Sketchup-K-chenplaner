#!/usr/bin/env python3
"""Validiert Katalog- und Projektdateien gegen die JSON-Schemata in schemas/.

Aufruf: python3 tools/validate.py            (alles prüfen)
        pip install jsonschema referencing    (Voraussetzung)
"""
import json
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
    print(f"{checked} Dateien geprüft, {errors} Fehler, {placeholders} offene Platzhalter (<...>)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
