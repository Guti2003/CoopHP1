<#
    HP1 Co-op uninstaller. Restores the ini backups made by Install.ps1 and
    removes HP1Coop.u. The game's own files were never touched.
#>

param([string]$GameDir)

$ErrorActionPreference = "Stop"

function Restore([string]$path) {
    $backup = "$path.hp1coop-backup"
    if (Test-Path $backup) {
        Copy-Item $backup $path -Force
        Remove-Item $backup -Force
        Write-Host "  restaurado: $path"
    } elseif (Test-Path $path) {
        $txt = [IO.File]::ReadAllText($path, [Text.Encoding]::Default)
        if ($txt -match 'Console=HP1Coop\.CoopConsole') {
            $txt = $txt -replace 'Console=HP1Coop\.CoopConsole', 'Console=HPMenu.HPConsole'
            [IO.File]::WriteAllText($path, $txt, [Text.Encoding]::Default)
            Write-Host "  revertido a mano: $path"
        }
    }
}

Write-Host ""
Write-Host "=== HP1 Co-op - desinstalador ===" -ForegroundColor Cyan

if (-not $GameDir) {
    foreach ($c in @(
        "C:\Program Files (x86)\EA Games\Harry Potter y la Piedra Filosofal",
        "C:\Program Files (x86)\EA Games\Harry Potter and the Sorcerer's Stone",
        "C:\Program Files (x86)\EA Games\Harry Potter and the Philosopher's Stone")) {
        if (Test-Path (Join-Path $c "System\HarryPotter.u")) { $GameDir = $c; break }
    }
}
if (-not $GameDir) { $GameDir = Read-Host "Carpeta del juego" }
$GameDir = $GameDir.Trim('"')
$System = Join-Path $GameDir "System"

Restore (Join-Path $System "Default.ini")
Restore (Join-Path $env:USERPROFILE "Documents\Harry Potter\HP.ini")

$u = Join-Path $System "HP1Coop.u"
if (Test-Path $u) { Remove-Item $u -Force; Write-Host "  borrado: HP1Coop.u" }

Write-Host ""
Write-Host "Desinstalado. El juego queda como estaba." -ForegroundColor Green
Write-Host ""
