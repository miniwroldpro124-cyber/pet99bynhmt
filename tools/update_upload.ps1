param(
    [string]$CommitMessage = "Obfuscate all Lua modules with Prometheus Polymorphic Multi-Register VM",
    [switch]$RestoreOnly,
    [switch]$NoPush
)

$ErrorActionPreference = "Stop"
$RepoDir = "C:\Users\LaptopAT\.gemini\antigravity\scratch\pet99bynhmt"
$ToolScript = Join-Path $RepoDir "tools\prometheus_vm_obf.py"

Push-Location $RepoDir
try {
    if ($RestoreOnly) {
        Write-Host "[Steph HUB] Restoring clean unobfuscated sources..." -ForegroundColor Cyan
        python -u $ToolScript --restore
        if ($LASTEXITCODE -ne 0) { throw "Restore failed with exit code $LASTEXITCODE" }
        return
    }

    Write-Host "[Steph HUB] Running Backup + Prometheus Polymorphic Multi-Register VM Obfuscator + Verifier..." -ForegroundColor Cyan
    python -u $ToolScript
    if ($LASTEXITCODE -ne 0) { throw "Obfuscation/Verification failed with exit code $LASTEXITCODE" }

    if (-not $NoPush) {
        Write-Host "[Steph HUB] Staging obfuscated files and tools/ for GitHub upload..." -ForegroundColor Cyan
        git add .gitignore main.lua Stehp-Hub.lua ps99_engine_v3.lua manifest.lua games/ lib/ modules/ tools/prometheus_vm_obf.py tools/update_upload.ps1
        
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
            Write-Host "[Steph HUB] Successfully pushed obfuscated build to origin/main ($hash)" -ForegroundColor Green
        } else {
            Write-Host "[Steph HUB] Working tree already clean, nothing to commit." -ForegroundColor Yellow
        }
    }
} finally {
    Pop-Location
}
