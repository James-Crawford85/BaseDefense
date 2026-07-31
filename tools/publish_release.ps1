<#
.SYNOPSIS
  Cut and publish a new Base Defense release in one step.

.DESCRIPTION
  Bumps application/config/version, commits + pushes it, exports the Windows
  build, stages steam_appid.txt beside the exe, zips everything under a
  BaseDefense/ folder, and creates the GitHub release. Players' in-game updater
  picks it up automatically.

.EXAMPLE
  ./tools/publish_release.ps1 -Version 0.2.0 -Notes "New engineer tank, wall balance."
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version,

    [string]$Notes = "",

    [string]$Godot = "C:\Godot\Godot_v4.7-stable_win64.exe"
)

$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$tag = "v$Version"
Write-Host "== Publishing Base Defense $tag ==" -ForegroundColor Cyan

# 1. Bump config/version (BOM-free so Godot parses project.godot cleanly)
$projPath = Join-Path $repo "project.godot"
$content = Get-Content $projPath -Raw
$content = $content -replace 'config/version="[^"]*"', "config/version=`"$Version`""
[System.IO.File]::WriteAllText($projPath, $content, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Set config/version = $Version"

# 2. Commit + push the bump so the release tag matches the shipped build
git -C $repo add project.godot
git -C $repo commit -m "Release $tag" | Out-Null
git -C $repo push
Write-Host "Committed and pushed version bump"

# 3. Export the Windows build
$buildDir = Join-Path $repo "build\windows"
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
Get-ChildItem $buildDir -File | Remove-Item -Force -ErrorAction SilentlyContinue
& $Godot --headless --path $repo --export-release "Windows Desktop" (Join-Path $buildDir "BaseDefense.exe")
if (-not (Test-Path (Join-Path $buildDir "BaseDefense.exe"))) { throw "Export failed: no exe produced." }

# 4. steam_appid.txt must sit LOOSE next to the exe (see net.gd / updater notes)
Copy-Item (Join-Path $repo "steam_appid.txt") (Join-Path $buildDir "steam_appid.txt") -Force

# 5. Zip under a top-level BaseDefense/ folder for clean extraction
$stage = Join-Path $repo "build\BaseDefense"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item (Join-Path $buildDir "*") $stage -Force
$zip = Join-Path $repo "build\BaseDefense-Windows-$tag.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $stage -DestinationPath $zip
$zipMB = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Host ("Packaged {0} ({1} MB)" -f $zip, $zipMB)

# 6. Publish the GitHub release
if ([string]::IsNullOrWhiteSpace($Notes)) {
    $Notes = "Base Defense $tag. Download, extract, keep all files together, run BaseDefense.exe with Steam running. In-game the updater offers this automatically to anyone on an older build."
}
gh release create $tag $zip --repo James-Crawford85/BaseDefense --title "Base Defense $tag" --notes $Notes
Write-Host ("== Done: https://github.com/James-Crawford85/BaseDefense/releases/tag/{0} ==" -f $tag) -ForegroundColor Green
