# Arcadia prototype: imports the project, then runs the simulation test.
# Run by double-clicking run_tests.bat, or with:
#   powershell -ExecutionPolicy Bypass -File run_tests.ps1 -Godot "C:\path\to\Godot_v4.7-stable_win64_console.exe"

param([string]$Godot = $env:GODOT_PATH)

$project = $PSScriptRoot

function Find-Godot {
    $roots = @($project, (Join-Path $env:USERPROFILE "Downloads"), (Join-Path $env:USERPROFILE "Desktop"))
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        $folders = @($root) + @(Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
        foreach ($folder in $folders) {
            $hit = Get-ChildItem -Path $folder -Filter "Godot*console*.exe" -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }
    return $null
}

if (-not $Godot) { $Godot = Find-Godot }

if (-not $Godot -or -not (Test-Path $Godot)) {
    Write-Host "Godot 4.7 was not found."
    Write-Host "Download the Windows console build from https://godotengine.org/download"
    Write-Host "Then run this again with the path to the .exe:"
    Write-Host "  powershell -ExecutionPolicy Bypass -File run_tests.ps1 -Godot 'C:\path\to\Godot_v4.7-stable_win64_console.exe'"
    Read-Host "Press Enter to close"
    exit 1
}

Write-Host "Using Godot: $Godot"
Write-Host ""
Write-Host "Step 1 of 2: importing assets (first run only takes a little longer)..."
& $Godot --headless --path $project --import | Out-Null

Write-Host "Step 2 of 2: running the simulation test..."
$output = & $Godot --headless --path $project -s tests/sim_test.gd 2>&1
$output | ForEach-Object { Write-Host $_ }

$failureLine = $output | Where-Object { $_ -match "FAILURES:" } | Select-Object -Last 1
Write-Host ""
if ($failureLine -match "FAILURES: 0") {
    Write-Host "ALL CHECKS PASSED ($failureLine)" -ForegroundColor Green
    $code = 0
} else {
    Write-Host "SOME CHECKS FAILED. Copy the output above and send it back." -ForegroundColor Red
    $code = 1
}

Read-Host "Press Enter to close"
exit $code
