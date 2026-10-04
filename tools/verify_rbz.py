#!/usr/bin/env python3
"""Baut das Paket, entpackt es in ein Temp-Verzeichnis und startet den Plugin-Selbsttest dort (mit SketchUp-Attrappe).
Prüft so, dass das .rbz vollständig ist und ohne das Repository funktioniert. Aufruf: python3 tools/verify_rbz.py
"""
import pathlib
import subprocess
import sys
import tempfile
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
subprocess.run([sys.executable, str(ROOT / "tools" / "build_rbz.py")], check=True)
rbz = sorted((ROOT / "dist").glob("kp_kuechenplaner_*.rbz"))[-1]
with tempfile.TemporaryDirectory() as tmp:
    with zipfile.ZipFile(rbz) as z:
        namen = z.namelist()
        assert "kp_kuechenplaner.rb" in namen and "kp_kuechenplaner/main.rb" in namen, "Paketstruktur falsch"
        assert not any("\\" in n for n in namen), "Rückwärts-Schrägstriche im Paket"
        z.extractall(tmp)
    code = (
        "require 'sketchup'; "
        f"require '{tmp}/kp_kuechenplaner'; require '{tmp}/kp_kuechenplaner/main'; "
        "abort('Basis falsch') unless Kp::Plugin::BASE.start_with?(ARGV[0]); "
        "exit(Kp::Plugin.selbsttest ? 0 : 1)"
    )
    r = subprocess.run(["ruby", "-I", str(ROOT / "test" / "support"), "-e", code, tmp], capture_output=True, text=True)
    print(r.stdout[-700:])
    print(r.stderr[-300:])
    sys.exit(r.returncode)
