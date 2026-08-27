<#
    HP1 Co-op installer.

    Installs HP1Coop.u into an existing Harry Potter 1 install and points the
    engine's Console= key at it. Does not modify any shipped game file.

    Two config files matter, and this was learned the hard way:
      - <Game>\System\Default.ini            the seed, used to create the next one
      - %USERPROFILE%\Documents\Harry Potter\HP.ini   the file the game ACTUALLY reads
    Patching only Default.ini does nothing on a machine that has already run the
    game once.

    Both are rewritten as ANSI with no BOM. Writing a UTF-8 BOM makes the engine
    fail to start (verified).
#>

param(
    [string]$GameDir
)

$ErrorActionPreference = "Stop"

function Find-GameDir {
    $candidates = @(
        "C:\Program Files (x86)\EA Games\Harry Potter y la Piedra Filosofal",
        "C:\Program Files (x86)\EA Games\Harry Potter and the Sorcerer's Stone",
        "C:\Program Files (x86)\EA Games\Harry Potter and the Philosopher's Stone",
        "C:\Program Files\EA Games\Harry Potter y la Piedra Filosofal",
        "C:\Games\Harry Potter"
    )
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c "System\HarryPotter.u")) { return $c }
    }
    return $null
}

function Set-IniConsole([string]$path) {
    if (-not (Test-Path $path)) { return $false }

    $backup = "$path.hp1coop-backup"
    if (-not (Test-Path $backup)) { Copy-Item $path $backup -Force }

    # ANSI in, ANSI out. A BOM here stops the game from launching.
    $txt = [IO.File]::ReadAllText($path, [Text.Encoding]::Default)
    if ($txt -match 'Console=HP1Coop\.CoopConsole') {
        Write-Host "  already patched: $path"
        return $true
    }
    if ($txt -notmatch 'Console=HPMenu\.HPConsole') {
        Write-Warning "  no Console=HPMenu.HPConsole line in $path - skipped"
        return $false
    }
    $txt = $txt -replace 'Console=HPMenu\.HPConsole', 'Console=HP1Coop.CoopConsole'

    [IO.File]::WriteAllText($path, $txt, [Text.Encoding]::Default)
    Write-Host "  patched: $path"
    return $true
}

Write-Host ""
Write-Host "=== HP1 Co-op - instalador ===" -ForegroundColor Cyan
Write-Host ""

# --- locate the game ---------------------------------------------------------
if (-not $GameDir) { $GameDir = Find-GameDir }
if (-not $GameDir) {
    Write-Host "No encuentro el juego automaticamente."
    $GameDir = Read-Host "Escribe la carpeta del juego (la que contiene System\ y Maps\)"
}
$GameDir = $GameDir.Trim('"')
$System = Join-Path $GameDir "System"
if (-not (Test-Path (Join-Path $System "HarryPotter.u"))) {
    throw "No es una instalacion valida de HP1: falta System\HarryPotter.u en $GameDir"
}
Write-Host "Juego encontrado: $GameDir"

# --- version sanity check ----------------------------------------------------
$expected = 13972287
$actual = (Get-Item (Join-Path $System "HarryPotter.u")).Length
if ($actual -ne $expected) {
    Write-Warning "HarryPotter.u mide $actual bytes; el mod se compilo contra $expected."
    Write-Warning "Puede que sea otra edicion del juego y el mod no cargue."
    $go = Read-Host "Continuar de todas formas? (s/N)"
    if ($go -ne "s") { Write-Host "Cancelado."; exit 1 }
} else {
    Write-Host "Version del juego: coincide."
}

# --- copy the package --------------------------------------------------------
$src = Join-Path $PSScriptRoot "..\HP1Coop.u"
if (-not (Test-Path $src)) { $src = Join-Path $PSScriptRoot "HP1Coop.u" }
if (-not (Test-Path $src)) { throw "No encuentro HP1Coop.u junto al instalador." }
Copy-Item $src (Join-Path $System "HP1Coop.u") -Force
Write-Host "Copiado HP1Coop.u a System\"

# --- patch the config --------------------------------------------------------
Write-Host "Configurando:"
$userIni = Join-Path $env:USERPROFILE "Documents\Harry Potter\HP.ini"
$seedOk = Set-IniConsole (Join-Path $System "Default.ini")
$userOk = Set-IniConsole $userIni

if (-not $userOk) {
    Write-Host ""
    Write-Warning "No existe todavia $userIni"
    Write-Warning "Abre el juego UNA VEZ, cierralo, y vuelve a ejecutar este instalador."
    exit 1
}

Write-Host ""
Write-Host "=== Instalado ===" -ForegroundColor Green
Write-Host ""
Write-Host "Abre el juego, CARGA UNA PARTIDA, y pulsa TAB para abrir la consola."
Write-Host "(En el menu principal no funciona: hace falta estar jugando.)"
Write-Host ""
Write-Host "  El que hace de servidor escribe:   CoopHost"
Write-Host "  El otro escribe:                   CoopConnect <IP-del-servidor>"
Write-Host ""
Write-Host "  CoopStatus   ver estado y ping"
Write-Host "  CoopZ 12     ajustar la altura del companero si flota o se hunde"
Write-Host "  CoopDisconnect"
Write-Host ""
Write-Host "Los dos teneis que estar en el MISMO mapa para veros."
Write-Host "Para desinstalar: Desinstalar.bat"
Write-Host ""
