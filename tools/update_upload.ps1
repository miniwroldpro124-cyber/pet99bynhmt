param(
    [string]$CommitMessage = "Obfuscate all Lua modules with Prometheus Polymorphic Multi-Register VM v5.0 (24-Bit Sponge + Sealed Upvalues + 8-Slot Ring Buffer)",
    [switch]$RestoreOnly,
    [switch]$NoPush
)

$ErrorActionPreference = "Stop"
$RepoDir = "C:\Users\LaptopAT\.gemini\antigravity\scratch\pet99bynhmt"
$ToolScript = Join-Path $RepoDir "tools\prometheus_vm_obf.py"
$VerifySpongeScript = Join-Path $RepoDir "tools\verify_v5_sponge.py"
$VerifyGcScript = Join-Path $RepoDir "tools\verify_gc_and_upvalues.py"

Push-Location $RepoDir
try {
    if ($RestoreOnly) {
        Write-Host "[Steph HUB v5.0] Restoring clean unobfuscated sources..." -ForegroundColor Cyan
        python -u $ToolScript --restore
        if ($LASTEXITCODE -ne 0) { throw "Restore failed with exit code $LASTEXITCODE" }
        return
    }

    Write-Host "================================================================================" -ForegroundColor Magenta
    Write-Host "[Steph HUB v5.0] Prometheus Dual-Layer Polymorphic Multi-Register VM Pipeline" -ForegroundColor Magenta
    Write-Host "  - 24-Bit Sponge (S0, S1, S2) over 15 C-closures (debug=nil; string.dump=nil)" -ForegroundColor Gray
    Write-Host "  - 3-way 23575/42 Invariant + C-Dumper Trap (__metatable=211)" -ForegroundColor Gray
    Write-Host "  - Sealed Awxs Lexical Upvalues (zero _ENV primitive lookups)" -ForegroundColor Gray
    Write-Host "  - Metatable-Free 8-Slot K_salt Ring Buffer (getgc(true) hardened)" -ForegroundColor Gray
    Write-Host "  - Direct BUILD_SALT Compiler Seed Generation (23 modules)" -ForegroundColor Gray
    Write-Host "  - Clean Backups -> unobf/, pet99bynhmt_unobf/, Real\workspace\stephhub-src\" -ForegroundColor Gray
    Write-Host "  - Live Sync     -> Real\workspace\" -ForegroundColor Gray
    Write-Host "================================================================================" -ForegroundColor Magenta

    Write-Host "[Steph HUB v5.0] Running Backup + v5.0 VM Obfuscator + Built-in Verifier..." -ForegroundColor Cyan
    python -u $ToolScript
    if ($LASTEXITCODE -ne 0) { throw "Obfuscation/Verification failed with exit code $LASTEXITCODE" }

    if (Test-Path $VerifySpongeScript) {
        Write-Host "[Steph HUB v5.0] Running Red-Team Sponge & Anti-Tamper Verifier (tools/verify_v5_sponge.py)..." -ForegroundColor Cyan
        python -u $VerifySpongeScript
        if ($LASTEXITCODE -ne 0) { throw "Red-Team Sponge Verification (verify_v5_sponge.py) failed with exit code $LASTEXITCODE" }
    } else {
        Write-Host "[Steph HUB v5.0] Notice: tools/verify_v5_sponge.py not found, skipping external sponge verifier." -ForegroundColor Yellow
    }

    if (Test-Path $VerifyGcScript) {
        Write-Host "[Steph HUB v5.0] Running getgc(true) Ring-Buffer & Sealed Upvalue Auditor (tools/verify_gc_and_upvalues.py)..." -ForegroundColor Cyan
        python -u $VerifyGcScript
        if ($LASTEXITCODE -ne 0) { throw "GC & Upvalue Verification (verify_gc_and_upvalues.py) failed with exit code $LASTEXITCODE" }
    } else {
        Write-Host "[Steph HUB v5.0] Notice: tools/verify_gc_and_upvalues.py not found, skipping external GC/upvalue auditor." -ForegroundColor Yellow
    }

    Write-Host "[Steph HUB v5.0] All v5.0 build & security verification gates PASSED." -ForegroundColor Green

    if (-not $NoPush) {
        Write-Host "[Steph HUB v5.0] Staging obfuscated files and tools/ for GitHub upload..." -ForegroundColor Cyan
        $stagePaths = @(
            ".gitignore",
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
        if (Test-Path $VerifySpongeScript) { $stagePaths += "tools/verify_v5_sponge.py" }
        if (Test-Path $VerifyGcScript) { $stagePaths += "tools/verify_gc_and_upvalues.py" }
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
            Write-Host "[Steph HUB v5.0] Successfully pushed obfuscated v5.0 build to origin/main ($hash)" -ForegroundColor Green
        } else {
            Write-Host "[Steph HUB v5.0] Working tree already clean, nothing to commit." -ForegroundColor Yellow
        }
    }
} finally {
    Pop-Location
}
