<#
 Richtet die Entwicklungsumgebung auf Windows ein:
  1. klont das Projekt (oder aktualisiert es) nach -Ziel
  2. legt in jedem gefundenen SketchUp-Plugins-Ordner eine kleine Datei ab, die den Dev-Lader aus dem Projekt lädt

 Aufruf (PowerShell):
   powershell -ExecutionPolicy Bypass -File setup-windows.ps1
   powershell -ExecutionPolicy Bypass -File setup-windows.ps1 -Ziel "E:\sketchup - küchenplaner" -Branch ccr-3164b6fe-v6h746
#>
param(
  [string]$Ziel = "E:\sketchup - küchenplaner",
  [string]$Repo = "https://github.com/jimmycd/Sketchup-K-chenplaner.git",
  [string]$Branch = "ccr-3164b6fe-v6h746"
)
$ErrorActionPreference = "Stop"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "git wurde nicht gefunden. Bitte Git for Windows installieren." }

if (Test-Path (Join-Path $Ziel ".git")) {
  Write-Host "Projekt vorhanden, aktualisiere: $Ziel"
  git -C $Ziel fetch origin $Branch
  git -C $Ziel checkout $Branch
  git -C $Ziel pull origin $Branch
} else {
  Write-Host "Klone $Repo nach $Ziel"
  git clone --branch $Branch $Repo $Ziel
}

$loader = Join-Path $Ziel "dev\kp_dev_loader.rb"
if (-not (Test-Path $loader)) { throw "Dev-Lader nicht gefunden: $loader" }
$rubyPfad = $loader.Replace("\", "/")
$stub = @"
# frozen_string_literal: true
# Lädt den Küchenplaner aus dem Entwicklungsordner (erzeugt von setup-windows.ps1).
load '$rubyPfad'
"@

$basis = Join-Path $env:APPDATA "SketchUp"
$ordner = @()
if (Test-Path $basis) {
  $ordner = Get-ChildItem $basis -Directory -Filter "SketchUp 20*" | ForEach-Object { Join-Path $_.FullName "SketchUp\Plugins" } | Where-Object { Test-Path $_ }
}
if ($ordner.Count -eq 0) {
  Write-Warning "Kein SketchUp-Plugins-Ordner unter $basis gefunden. Datei manuell ablegen: kp_kuechenplaner_dev.rb mit der Zeile: load '$rubyPfad'"
} else {
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  foreach ($o in $ordner) {
    [System.IO.File]::WriteAllText((Join-Path $o "kp_kuechenplaner_dev.rb"), $stub, $utf8)
    Write-Host "Dev-Lader installiert in: $o"
  }
}
Write-Host ""
Write-Host "Fertig. SketchUp neu starten, dann: Erweiterungen > Küchenplaner (Dev) > Neu laden."
Write-Host "Spätere Änderungen: git pull im Ordner $Ziel, dann in SketchUp 'Neu laden' (kein Neustart nötig)."
