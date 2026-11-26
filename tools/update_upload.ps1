param(
    [string]$CommitMessage = "Optimize PS99 Event anti-lag engine v3.4.4 (cached breakables/pos/plot/features, smart pet route diffing, budgeted BFS FX optimizer, split 0.15s/0.5s ticks)",
    [switch]$RestoreOnly,
    [switch]$NoPush,
    [switch]$Push
)

$ErrorActionPreference = "Stop"
$RepoDir = "C:\Users\LaptopAT\.gemini\antigravity\scratch\pet99bynhmt"
$LocalPython = "C:\Users\LaptopAT\AppData\Local\Python\bin\python.exe"
$PythonExe = if (Test-Path $LocalPython) { $LocalPython } else { "python" }
$ToolScript = Join-Path $RepoDir "tools\prometheus_vm_obf.py"
$BundlerScript = Join-Path $RepoDir "tools\bundler.py"
$VerifySpongeScript = Join-Path $RepoDir "tools\verify_v5_sponge.py"
$VerifyGcScript = Join-Path $RepoDir "tools\verify_gc_and_upvalues.py"
$VerifyV6Script = Join-Path $RepoDir "tools\verify_v6_luau_obf.py"

Push-Location $RepoDir
try {
    if ($RestoreOnly) {
        Write-Host "[Steph HUB v6.0] Restoring clean unobfuscated sources..." -ForegroundColor Cyan
        & $PythonExe -u $ToolScript --restore
        if ($LASTEXITCODE -ne 0) { throw "Restore failed with exit code $LASTEXITCODE" }
        return
    }

    Write-Host "================================================================================" -ForegroundColor Magenta
    Write-Host "[Steph HUB v6.0] Prometheus Polymorphic Luau Dual-VM & Bundler Pipeline (--target=luau)" -ForegroundColor Magenta
    Write-Host "  - Unified Stream + Shuffled 85-Char Base85 (0 padding tails) + Xorshift32-CFB" -ForegroundColor Gray
    Write-Host "  - Shuffled Outer IIFE + Dummy Args + Immediate CFF State Machine (--target=luau)" -ForegroundColor Gray
    Write-Host "  - Silent Seed Poisoning via debug.info / isyieldable / Pointer Uniqueness" -ForegroundColor Gray
    Write-Host "  - Zero table.concat + Stage-2 Super-Instructions + <=8-Slot Lazy K(idx) Ring" -ForegroundColor Gray
    Write-Host "  - Pre-Obfuscator Module Bundler (tools/bundler.py) + Public README Hardening" -ForegroundColor Gray
    Write-Host "  - Clean Backups -> unobf/, pet99bynhmt_unobf/, Real\workspace\stephhub-src\" -ForegroundColor Gray
    Write-Host "  - Live Sync     -> Real\workspace\" -ForegroundColor Gray
    Write-Host "================================================================================" -ForegroundColor Magenta

    if (Test-Path $BundlerScript) {
        Write-Host "[Steph HUB v6.0] Running Pre-Obfuscator Module Bundler Self-Test (tools/bundler.py --self-test)..." -ForegroundColor Cyan
        & $PythonExe -u $BundlerScript --self-test
        if ($LASTEXITCODE -ne 0) { throw "Bundler self-test (tools/bundler.py --self-test) failed with exit code $LASTEXITCODE" }
    }

    Write-Host "[Steph HUB v6.0] Running Backup + v6.0 Luau VM Obfuscator (--target=luau) + Built-in Verifier..." -ForegroundColor Cyan
    & $PythonExe -u $ToolScript --target=luau
    if ($LASTEXITCODE -ne 0) { throw "Obfuscation/Verification failed with exit code $LASTEXITCODE" }

    if (Test-Path $VerifySpongeScript) {
        Write-Host "[Steph HUB v6.0] Running Red-Team Sponge & Anti-Pre-Hook Verifier (tools/verify_v5_sponge.py)..." -ForegroundColor Cyan
        & $PythonExe -u $VerifySpongeScript --skip-v6
        if ($LASTEXITCODE -ne 0) { throw "Red-Team Sponge Verification (verify_v5_sponge.py) failed with exit code $LASTEXITCODE" }
    } else {
        Write-Host "[Steph HUB v6.0] Notice: tools/verify_v5_sponge.py not found, skipping external sponge verifier." -ForegroundColor Yellow
    }

    if (Test-Path $VerifyGcScript) {
        Write-Host "[Steph HUB v6.0] Running getgc(true) Lazy Ring-Buffer & Sealed Upvalue Auditor (tools/verify_gc_and_upvalues.py)..." -ForegroundColor Cyan
        & $PythonExe -u $VerifyGcScript
        if ($LASTEXITCODE -ne 0) { throw "GC & Upvalue Verification (verify_gc_and_upvalues.py) failed with exit code $LASTEXITCODE" }
    } else {
        Write-Host "[Steph HUB v6.0] Notice: tools/verify_gc_and_upvalues.py not found, skipping external GC/upvalue auditor." -ForegroundColor Yellow
    }

    if (Test-Path $VerifyV6Script) {
        Write-Host "[Steph HUB v6.0] Running Comprehensive v6.0 Luau Specification Suite (tools/verify_v6_luau_obf.py)..." -ForegroundColor Cyan
        & $PythonExe -u $VerifyV6Script
        if ($LASTEXITCODE -ne 0) { throw "Comprehensive v6.0 Verification (verify_v6_luau_obf.py) failed with exit code $LASTEXITCODE" }
    } else {
        Write-Host "[Steph HUB v6.0] Notice: tools/verify_v6_luau_obf.py not found, skipping v6.0 verifier." -ForegroundColor Yellow
    }

    Write-Host "[Steph HUB v6.0] All v6.0 Luau build & security verification gates PASSED." -ForegroundColor Green

    if (-not $NoPush) {
        Write-Host "[Steph HUB v6.0] Staging obfuscated files, README.md, and tools/ for GitHub upload..." -ForegroundColor Cyan
        $stagePaths = @(
            ".gitignore",
            "README.md",
            "main.lua",
            "Stehp-Hub.lua",
            "ps99_engine_v3.lua",
            "manifest.lua",
            "games/",
            "lib/",
            "modules/",
            "tools/prometheus_vm_obf.py",
            "tools/update_upload.ps1"
        )
        if (Test-Path $BundlerScript) { $stagePaths += "tools/bundler.py" }
        if (Test-Path $VerifySpongeScript) { $stagePaths += "tools/verify_v5_sponge.py" }
        if (Test-Path $VerifyGcScript) { $stagePaths += "tools/verify_gc_and_upvalues.py" }
        if (Test-Path $VerifyV6Script) { $stagePaths += "tools/verify_v6_luau_obf.py" }
        git add @stagePaths

        # Verify no unobf/ files are staged
        $staged = git diff --cached --name-only
        if ($staged -match "^unobf/" -or $staged -match "\.unobf\.lua$" -or $staged -match "^tools/Prometheus/") {
            throw "SAFETY ABORT: Unobfuscated backup or tools/Prometheus was staged!"
        }

        $status = git status --porcelain
        if ($status) {
            git commit -m $CommitMessage
            if ($LASTEXITCODE -ne 0) { throw "git commit failed" }
            git push origin main
            if ($LASTEXITCODE -ne 0) { throw "git push origin main failed" }
            $hash = (git rev-parse --short HEAD).Trim()
            Write-Host "[Steph HUB v6.0] Successfully pushed obfuscated v6.0 build to origin/main ($hash)" -ForegroundColor Green
        } else {
            Write-Host "[Steph HUB v6.0] Working tree already clean, nothing to commit." -ForegroundColor Yellow
        }
    }
} finally {
    Pop-Location
}
