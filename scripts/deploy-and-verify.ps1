# StarTeQ Paperclip Deploy & Verify Script v1.1
# Run from: C:\Users\Sydney Parker\paperclip-deploy\

$ErrorActionPreference = "SilentlyContinue"

$PAPERCLIP_URL = "https://paperclip-production-302b.up.railway.app"
$COMPANY_ID    = "b73af86e-2dbd-44ef-b896-8256291797ed"
$CEO_KEY       = "pcp_3f607b5ff53a2d47c59e2566a97ad1348eef87cedcc9ce18"

function Write-Step { param($msg) Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "   OK   $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "   WARN $msg" -ForegroundColor Yellow }
function Write-Fail { param($msg) Write-Host "   FAIL $msg" -ForegroundColor Red }
function Write-Info { param($msg) Write-Host "   INFO $msg" -ForegroundColor Gray }

# 1. Confirm correct directory
Write-Step "Checking deploy directory..."
if (-not (Test-Path "Dockerfile")) {
    Write-Fail "Dockerfile not found. Run from C:\Users\Sydney Parker\paperclip-deploy\"
    exit 1
}
Write-Ok "Dockerfile found"

# 2. Confirm Railway login
Write-Step "Checking Railway login..."
$whoami = railway whoami 2>&1
if ($whoami -match "Logged in as") {
    Write-Ok "$whoami"
} else {
    Write-Fail "Not logged in to Railway. Run: railway login"
    exit 1
}

# 3. Kill processes that commonly lock files
Write-Step "Releasing file locks before deploy..."
$toKill = @("node","npm","wrangler","code","notepad++","vim")
foreach ($proc in $toKill) {
    $found = Get-Process -Name $proc -ErrorAction SilentlyContinue
    if ($found) {
        Write-Warn "Stopping $proc (may be locking files)..."
        Stop-Process -Name $proc -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }
}
Write-Ok "File locks cleared"

# 4. Copy deploy files to a clean temp directory
Write-Step "Copying files to clean temp directory..."
$tempDir = "$env:TEMP\starteq-deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
Copy-Item -Path ".\*" -Destination $tempDir -Recurse -Force
Write-Ok "Files copied to $tempDir"

# 5. Deploy from temp directory
Write-Step "Deploying to Railway from clean directory..."
Push-Location $tempDir
railway up --detach
$deployResult = $LASTEXITCODE
Pop-Location

# Clean up temp dir
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

if ($deployResult -ne 0) {
    Write-Fail "railway up failed. Try running: railway logs -n 50"
    Write-Info "If the error persists, try: railway up --detach from a fresh PowerShell window"
    exit 1
}
Write-Ok "Deploy triggered successfully"

# 6. Wait for deployment to stabilise
Write-Step "Waiting 90 seconds for deployment to stabilise..."
$dots = 0
while ($dots -lt 18) {
    Start-Sleep -Seconds 5
    Write-Host "." -NoNewline
    $dots++
}
Write-Host ""

# 7. Health check
Write-Step "Checking Paperclip is responding..."
try {
    $response = Invoke-WebRequest -Uri "$PAPERCLIP_URL/health" -TimeoutSec 15 -UseBasicParsing
    Write-Ok "HTTP $($response.StatusCode) - Paperclip is up"
} catch {
    Write-Warn "Health endpoint not reachable yet - may still be starting"
}

# 8. Verify agents
Write-Step "Checking agent status..."
$headers = @{
    "Authorization" = "Bearer $CEO_KEY"
    "Content-Type"  = "application/json"
}
try {
    $agents = Invoke-RestMethod `
        -Uri "$PAPERCLIP_URL/api/companies/$COMPANY_ID/agents" `
        -Headers $headers `
        -TimeoutSec 15

    $total   = $agents.Count
    $running = 0

    foreach ($agent in $agents) {
        if ($agent.status -in @("active","running","idle")) {
            $running++
            Write-Host "   OK   $($agent.name) - $($agent.status)" -ForegroundColor Green
        } else {
            Write-Host "   WARN $($agent.name) - $($agent.status)" -ForegroundColor Yellow
        }
    }

    Write-Host ""
    if ($running -eq $total) {
        Write-Ok "All $total agents confirmed running"
    } else {
        Write-Warn "$running / $total agents running - check Paperclip dashboard"
    }
} catch {
    Write-Warn "Could not reach agents API: $($_.Exception.Message)"
    Write-Warn "Platform may still be warming up - wait 2 min and re-run"
}

# 9. Gemini CLI check
Write-Step "Verifying Gemini CLI in container..."
Write-Host "   Run this to confirm:" -ForegroundColor Gray
Write-Host "   railway run gemini --version" -ForegroundColor White

# 10. Summary
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Deploy complete" -ForegroundColor Cyan
Write-Host "  Dashboard : $PAPERCLIP_URL/STA/dashboard" -ForegroundColor White
Write-Host "  Logs      : railway logs -n 50" -ForegroundColor White
Write-Host "  Re-verify : .\scripts\deploy-and-verify.ps1" -ForegroundColor White
Write-Host "==========================================" -ForegroundColor Cyan