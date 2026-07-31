<#
.SYNOPSIS
  Cut and publish a new Base Defense release in one step.

.DESCRIPTION
  Bumps application/config/version, commits + pushes it, exports the Windows
  build, stages steam_appid.txt beside the exe, zips everything under a
  BaseDefense/ folder, and creates the GitHub release. Players' in-game updater
  picks it up automatically.

  Note: does NOT use ErrorActionPreference=Stop, because native tools (git)
  write harmless warnings to stderr that Stop would treat as fatal. Instead
  each native step is followed by an explicit exit-code check.

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

function Assert-LastExit([string]$What) {
    if ($LASTEXITCODE -ne 0) { throw "$What failed (exit $LASTEXITCODE)" }
}

$repo = Split-Path $PSScriptRoot -Parent
$tag = "v$Version"
Write-Host "== Publishing Base Defense $tag ==" -ForegroundColor Cyan

# 1. Bump config/version (BOM-free so Godot parses project.godot cleanly)
$projPath = Join-Path $repo "project.godot"
$content = Get-Content $projPath -Raw
$content = $content -replace 'config/version="[^"]*"', "config/version=`"$Version`""
[System.IO.File]::WriteAllText($projPath, $content, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Set config/version = $Version"

# 2. Commit + push the bump so the release tag matches the shipped build.
#    (git prints an LF/CRLF warning to stderr - harmless; we check exit codes.)
git -C $repo add project.godot
Assert-LastExit "git add"
# Only commit if the version actually changed (re-running for the same version
# is fine). git diff --cached --quiet exits 1 when there are staged changes.
git -C $repo diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
    git -C $repo commit -m "Release $tag"
    Assert-LastExit "git commit"
    Write-Host "Committed version bump"
} else {
    Write-Host "Version already committed - nothing to commit"
}
git -C $repo push
Assert-LastExit "git push"
Write-Host "Pushed"

# 3. Export the Windows build
$buildDir = Join-Path $repo "build\windows"
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
Get-ChildItem $buildDir -File | Remove-Item -Force -ErrorAction SilentlyContinue
# Pipe Godot's stdout through Out-Null: this makes PowerShell read the stream to
# EOF and thus WAIT for the process to fully exit before continuing. Without the
# pipe, the call can return before the exe is finished writing and the Test-Path
# below races/fails.
& $Godot --headless --path $repo --export-release "Windows Desktop" (Join-Path $buildDir "BaseDefense.exe") | Out-Null
Assert-LastExit "godot export"
if (-not (Test-Path (Join-Path $buildDir "BaseDefense.exe"))) { throw "Export failed: no exe produced." }
Write-Host "Exported build"

# 4. steam_appid.txt must sit LOOSE next to the exe (see net.gd / updater notes)
Copy-Item (Join-Path $repo "steam_appid.txt") (Join-Path $buildDir "steam_appid.txt") -Force

# 4b. Pre-flight the loose-file manifest. A headless export can silently omit the
#     native Steam libraries if the GDExtension fails to load (we've seen the
#     debug-DLL copy race), and the exit code stays 0. Such a build boots for
#     players as "Steam cannot be contacted" with no signal here, so verify every
#     required file is present before we zip and publish.
foreach ($name in @("BaseDefense.exe", "BaseDefense.pck", "steam_api64.dll", "steam_appid.txt")) {
    if (-not (Test-Path (Join-Path $buildDir $name))) {
        throw "Build is missing $name - refusing to publish an incomplete build."
    }
}
# GodotSteam release DLL: match by pattern so an addon version bump won't break this.
$steamDll = Get-ChildItem $buildDir -Filter "libgodotsteam*template_release*.dll" -ErrorAction SilentlyContinue
if (-not $steamDll) {
    throw "Build is missing the GodotSteam release DLL - Steam would fail to init for players. Refusing to publish."
}
Write-Host "Verified build manifest (exe, pck, Steam libs, appid)"

# 5. Zip under a top-level BaseDefense/ folder for clean extraction
$stage = Join-Path $repo "build\BaseDefense"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item (Join-Path $buildDir "*") $stage -Force
$zip = Join-Path $repo "build\BaseDefense-Windows-$tag.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $stage -DestinationPath $zip -Force
$zipMB = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Host ("Packaged {0} ({1} MB)" -f $zip, $zipMB)

# 6. Publish the GitHub release
if ([string]::IsNullOrWhiteSpace($Notes)) {
    $Notes = "Base Defense $tag. Download, extract, keep all files together, run BaseDefense.exe with Steam running. In-game the updater offers this automatically to anyone on an older build."
}
gh release create $tag $zip --repo James-Crawford85/BaseDefense --title "Base Defense $tag" --notes $Notes
Assert-LastExit "gh release create"
Write-Host ("== Done: https://github.com/James-Crawford85/BaseDefense/releases/tag/{0} ==" -f $tag) -ForegroundColor Green
