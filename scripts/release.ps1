#Requires -Version 5.1
<#
.SYNOPSIS
    ALK release automation - enforces the project versioning policy.

.DESCRIPTION
    Versioning policy:
      * Structural / architectural change -> MAJOR : v1.0.1 -> v2.0.0
      * Data-only change                 -> PATCH : v1.0.0 -> v1.0.1

    The Android build number (the "+N" suffix) always increments by one so
    adb / Play Store can order builds.

.PARAMETER Type
    major | patch | auto   (default: auto)
    "auto" inspects the working tree and classifies the change.

.PARAMETER Notes
    Release notes written into the GitHub Release body.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\release.ps1 -Type major -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('auto', 'major', 'patch')]
    [string]$Type = 'auto',
    [string]$Notes = '',
    [switch]$SkipBuild,
    [switch]$Publish
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$pubspec = Join-Path $repoRoot 'pubspec.yaml'
$gitExe = 'C:\Program Files\Git\cmd\git.exe'
if (-not (Test-Path $gitExe)) { $gitExe = 'git' }

function Get-PubspecVersion {
    if (-not (Test-Path $pubspec)) { throw "pubspec.yaml not found at $pubspec" }
    $m = Select-String -Path $pubspec -Pattern '^version:\s*(.+?)\s*$' | Select-Object -First 1
    if (-not $m) { throw 'No "version:" line found in pubspec.yaml' }
    $raw = $m.Matches[0].Groups[1].Value.Trim().Trim('"').Trim("'")
    if ($raw -match '^(?<ver>\d+(\.\d+)*)\+(?<b>\d+)$') {
        return @{ Full = $raw; Version = $Matches['ver']; Build = [int]$Matches['b'] }
    }
    if ($raw -match '^\d+(\.\d+)*$') {
        return @{ Full = $raw; Version = $raw; Build = 0 }
    }
    throw "Cannot parse pubspec version '$raw'"
}

function Get-NextVersion {
    param([string]$Current, [ValidateSet('major', 'patch')][string]$Change, [int]$Build)
    $p = @(($Current -split '\.') | ForEach-Object { [int]$_ })
    while ($p.Count -lt 3) { $p += 0 }
    $major = $p[0]; $minor = $p[1]; $patch = $p[2]
    switch ($Change) {
        'major' { $major++; $minor = 0; $patch = 0 }
        'patch' { $patch++ }
    }
    $v = "$major.$minor.$patch"
    return @{ Version = $v; Tag = "v$v"; Full = "$v+$($Build + 1)"; Build = ($Build + 1) }
}

function Invoke-GitQuiet {
    # git writes "fatal: ..." to stderr; swallow it so a non-repo does not
    # become a terminating error under $ErrorActionPreference = 'Stop'.
    param([string[]]$GitArgs)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $gitExe @GitArgs 2>$null
        return @($out | Where-Object { $_ -notmatch '^fatal:' })
    } finally {
        $ErrorActionPreference = $prev
    }
}

function Get-ChangeTypeFromGit {
    $inside = Invoke-GitQuiet @('-C', $repoRoot, 'rev-parse', '--is-inside-work-tree')
    if (($inside -join '').Trim() -ne 'true') {
        Write-Warning 'Not a git repository - cannot auto-detect. Defaulting to MAJOR.'
        return 'major'
    }
    $changed = Invoke-GitQuiet @('-C', $repoRoot, 'diff', '--name-only', 'HEAD')
    if (-not $changed -or $changed.Count -eq 0) {
        $changed = Invoke-GitQuiet @('-C', $repoRoot, 'ls-files', '--others', '--exclude-standard')
    }
    if (-not $changed -or $changed.Count -eq 0) {
        Write-Warning 'No changes detected. Defaulting to PATCH.'
        return 'patch'
    }

    # Structural paths: application code, platform shells, dependency manifest.
    $structural = '(^lib/|^android/|^ios/|^web/|^tool/|pubspec\.lock$)'
    # Data-only paths: assets, localisation data, docs, tests.
    $dataOnly = '(^assets/|\.md$|source_dictionary\.json$|^test/|^scripts/|\.py$)'

    $hits = [System.Collections.Generic.List[string]]::new()
    foreach ($f in $changed) {
        $p = $f -replace '\\', '/'
        if ($p -match $structural) { $hits.Add($p) }
    }
    foreach ($h in $hits) { Write-Host "  structural: $h" -ForegroundColor Yellow }

    if ($hits.Count -gt 0) {
        Write-Host '-> CLASSIFIED AS: MAJOR (structural / architectural change)' -ForegroundColor Magenta
        return 'major'
    }

    foreach ($f in $changed) {
        $p = $f -replace '\\', '/'
        if ($p -notmatch $dataOnly) {
            Write-Host "  unclassified: $p" -ForegroundColor DarkGray
            Write-Host '-> CLASSIFIED AS: MAJOR (unclassified file touched)' -ForegroundColor Magenta
            return 'major'
        }
        Write-Host "  data: $p" -ForegroundColor DarkGray
    }
    Write-Host '-> CLASSIFIED AS: PATCH (data-only change)' -ForegroundColor Magenta
    return 'patch'
}

$cur = Get-PubspecVersion
Write-Host ''
Write-Host '=== ALK Release ===' -ForegroundColor Cyan
Write-Host "  current : $($cur.Full)   (tag v$($cur.Version))"

if ($Type -eq 'auto') {
    $resolved = Get-ChangeTypeFromGit
} else {
    $resolved = $Type
}

# Phase detection: phase 1 bumps pubspec.yaml but does not commit; phase 2 is
# re-run with -Publish. Reuse the pending version instead of bumping twice
# (which would wrongly turn 1.0.2 into 1.0.3).
$bumped = $false
$committedVer = $null
foreach ($line in (Invoke-GitQuiet @('-C', $repoRoot, 'show', 'HEAD:pubspec.yaml'))) {
    if ($line -match '^version:\s*(\S+)') { $committedVer = $Matches[1]; break }
}
if ($committedVer -and (($committedVer -split '\+')[0] -ne ($cur.Full -split '\+')[0])) {
    $bumped = $true
}

if ($bumped) {
    $next = @{ Version = $cur.Version; Tag = "v$($cur.Version)"; Full = $cur.Full; Build = $cur.Build }
    Write-Host "  note    : pubspec already bumped (HEAD=$committedVer)" -ForegroundColor Yellow
    Write-Host "  change  : $resolved  ->  $($next.Tag)  (reusing pending version)" -ForegroundColor Green
} else {
    $next = Get-NextVersion -Current $cur.Version -Change $resolved -Build $cur.Build
    Write-Host "  change  : $resolved  ->  $($next.Tag)" -ForegroundColor Green
    Write-Host "  new     : $($next.Full)" -ForegroundColor Green
}
Write-Host ''

if ($bumped) {
    if ($WhatIfPreference) {
        Write-Host "  (dry run - pubspec.yaml already $($cur.Full))" -ForegroundColor DarkGray
        return
    }
    Write-Host "  pubspec.yaml already at $($cur.Full) - not modified" -ForegroundColor DarkGray
} elseif ($PSCmdlet.ShouldProcess("pubspec.yaml $($cur.Full) -> $($next.Full)", 'Bump version')) {
    (Get-Content -Path $pubspec -Raw) -replace "(?m)^version:\s*\S+\s*$", "version: $($next.Full)" |
        Set-Content -Path $pubspec -NoNewline -Encoding UTF8
    Write-Host "  updated pubspec.yaml -> version: $($next.Full)" -ForegroundColor Green
} else {
    Write-Host '  (dry run - pubspec.yaml NOT modified)' -ForegroundColor DarkGray
    return
}

$apk = Join-Path $repoRoot 'build\app\outputs\flutter-apk\app-release.apk'

if (-not $SkipBuild) {
    Write-Host ''
    Write-Host '--- Building signed release APK ---' -ForegroundColor Cyan
    Push-Location $repoRoot
    try {
        & C:\src\flutter\bin\flutter.bat build apk --release `
            --obfuscate --split-debug-info=build/symbols
        if ($LASTEXITCODE -ne 0) { throw "flutter build failed (exit $LASTEXITCODE)" }
    } finally { Pop-Location }
} else {
    Write-Host '  (-SkipBuild: reusing existing APK)' -ForegroundColor DarkGray
}

if (-not (Test-Path $apk)) { throw "APK not found: $apk" }
$sizeMb = [math]::Round((Get-Item $apk).Length / 1MB, 2)
Write-Host "  APK: $apk ($sizeMb MB)" -ForegroundColor Green

if (-not $Publish) {
    Write-Host ''
    Write-Host '--- NEXT STEPS ---' -ForegroundColor Cyan
    Write-Host "  1. Commit:  git add -A; git commit -m `"release $($next.Tag)`""
    Write-Host "  2. Tag   :  git tag $($next.Tag)"
    Write-Host "  3. Push  :  git push origin main; git push origin $($next.Tag)"
    Write-Host "  4. Publish (requires commit+tag): re-run with -Publish"
    Write-Host ''
    Write-Host "Re-run to publish:  .\release.ps1 -Type $resolved -SkipBuild -Publish"
    return
}

Write-Host ''
Write-Host '--- Committing, tagging and publishing ---' -ForegroundColor Cyan

# git/gh legitimately write progress to stderr. Under
# $ErrorActionPreference = 'Stop' PowerShell promotes that to a terminating
# NativeCommandError, which previously aborted mid-publish (leaving the tag
# and release uncreated). Relax it for this block only, then restore.
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    Push-Location $repoRoot
    try {
        & $gitExe -C $repoRoot add -A
        & $gitExe -C $repoRoot commit -m "release $($next.Tag)"
        if ($LASTEXITCODE -ne 0) {
            Write-Warning 'Nothing to commit, or commit failed - continuing to tag.'
        }

        $haveTag = Invoke-GitQuiet @('-C', $repoRoot, 'tag', '-l', $next.Tag)
        if (($haveTag | Measure-Object).Count -eq 0) {
            & $gitExe -C $repoRoot tag $next.Tag
            if ($LASTEXITCODE -ne 0) { throw "git tag failed (exit $LASTEXITCODE)" }
        } else {
            Write-Host "  tag $($next.Tag) already exists - reusing" -ForegroundColor DarkGray
        }

        & $gitExe -C $repoRoot push origin HEAD
        if ($LASTEXITCODE -ne 0) { throw "git push HEAD failed (exit $LASTEXITCODE)" }

        & $gitExe -C $repoRoot push origin $next.Tag
        if ($LASTEXITCODE -ne 0) { throw "git push tag failed (exit $LASTEXITCODE)" }

        # Arabic release notes must be written as UTF-8 (no BOM) and passed
        # via --notes-file; a plain --notes argument is mangled by the
        # Windows console into mojibake.
        $body = if ($Notes) { $Notes } else { "Auto-released from release.ps1 ($resolved change)." }
        $notesPath = Join-Path ([System.IO.Path]::GetTempPath()) 'alk-release-notes.md'
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($notesPath, ($body -replace "`r`n", "`n"), $utf8NoBom)

        $gh = 'C:\Program Files\GitHub CLI\gh.exe'
        $null = & $gh release view $next.Tag --repo jtnnazzal24-lab/alk-app --json tagName 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  release $next.Tag already exists - updating notes" -ForegroundColor DarkGray
            & $gh release edit $next.Tag --repo jtnnazzal24-lab/alk-app --notes-file $notesPath
            if ($LASTEXITCODE -ne 0) { throw "gh release edit failed (exit $LASTEXITCODE)" }
        } else {
            & $gh release create $next.Tag $apk `
                --repo jtnnazzal24-lab/alk-app `
                --title "alk health $($next.Tag)" `
                --notes-file $notesPath
            if ($LASTEXITCODE -ne 0) { throw "gh release create failed (exit $LASTEXITCODE)" }
        }
        Remove-Item $notesPath -ErrorAction SilentlyContinue
    } finally { Pop-Location }
} finally {
    $ErrorActionPreference = $prevEAP
}

Write-Host ''
Write-Host "=== Published $($next.Tag) ===" -ForegroundColor Green
Write-Host "  https://github.com/jtnnazzal24-lab/alk-app/releases/tag/$($next.Tag)"