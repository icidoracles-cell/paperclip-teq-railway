# ============================================================
#  StarTeQ Control Panel
#  Version: 1.0.0
#  Run from anywhere: .\StarTeQ-Control.ps1
# ============================================================

$ErrorActionPreference = "SilentlyContinue"

# ── Configuration ────────────────────────────────────────────
$PAPERCLIP_URL  = "https://paperclip-production-302b.up.railway.app"
$COMPANY_ID     = "b73af86e-2dbd-44ef-b896-8256291797ed"
$CEO_KEY        = "pcp_3f607b5ff53a2d47c59e2566a97ad1348eef87cedcc9ce18"
$DEPLOY_DIR     = "C:\Users\Sydney Parker\paperclip-deploy"
$STRIPE_KEY     = ""   # Add your Stripe secret key here
$CF_API_TOKEN   = ""   # Add your Cloudflare API token here
$CF_ZONE_ID     = ""   # Add your Cloudflare Zone ID here

$TEQ_APIS = @(
    @{ Name = "AetherCast (Weather)";    URL = "https://weather.starcaller.uk/health" },
    @{ Name = "Stratosphere (Agro)";     URL = "https://agro.starcaller.uk/health" },
    @{ Name = "QuasarStream (Finance)";  URL = "https://finance.starcaller.uk/health" },
    @{ Name = "NebulaMetrics (Market)";  URL = "https://market.starcaller.uk/health" },
    @{ Name = "Meridian (Geo)";          URL = "https://geo.starcaller.uk/health" },
    @{ Name = "Zenith (IP)";             URL = "https://ip.starcaller.uk/health" },
    @{ Name = "NovaMail (Email)";        URL = "https://mail.starcaller.uk/health" },
    @{ Name = "SentinelAuth (Auth)";     URL = "https://auth.starcaller.uk/health" },
    @{ Name = "NexusLink (URL)";         URL = "https://link.starcaller.uk/health" },
    @{ Name = "PrismBrand (Logo)";       URL = "https://logo.starcaller.uk/health" }
)

$AGENT_KEYS = @{
    "CEO"           = "pcp_3f607b5ff53a2d47c59e2566a97ad1348eef87cedcc9ce18"
    "BuildAgent"    = "pcp_2af943e9"
    "DeployAgent"   = "pcp_e8846f0b"
    "MonitorAgent"  = "pcp_16d440e9"
    "SecurityAgent" = "pcp_b45a8954"
    "CostAgent"     = "pcp_c973148c"
    "DocsAgent"     = "pcp_11945636"
}

# ── Helpers ──────────────────────────────────────────────────
function Show-Header {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║         StarTeQ Control Panel  v1.0          ║" -ForegroundColor Cyan
    Write-Host "  ║         starcaller.uk  |  Paperclip AI        ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Show-Menu {
    param($Title, $Options)
    Write-Host "  $Title" -ForegroundColor Yellow
    Write-Host "  $("─" * $Title.Length)" -ForegroundColor DarkGray
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host "  $($i+1). $($Options[$i])" -ForegroundColor White
    }
    Write-Host "  0. Back / Exit" -ForegroundColor DarkGray
    Write-Host ""
    $choice = Read-Host "  Select"
    return $choice
}

function Write-Ok   { param($msg) Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-Fail { param($msg) Write-Host "  [FAIL] $msg" -ForegroundColor Red }
function Write-Info { param($msg) Write-Host "  [INFO] $msg" -ForegroundColor Cyan }
function Pause-Screen { Write-Host ""; Read-Host "  Press Enter to continue" }

function Get-PaperclipHeaders {
    return @{
        "Authorization" = "Bearer $CEO_KEY"
        "Content-Type"  = "application/json"
    }
}

# ══════════════════════════════════════════════════════════════
#  SECTION 1 — PLATFORM HEALTH
# ══════════════════════════════════════════════════════════════
function Check-AllAPIs {
    Show-Header
    Write-Host "  Checking all 10 TeQ APIs..." -ForegroundColor Yellow
    Write-Host ""
    $healthy = 0
    $results = @()

    foreach ($api in $TEQ_APIS) {
        $start = Get-Date
        try {
            $resp = Invoke-WebRequest -Uri $api.URL -TimeoutSec 10 -UseBasicParsing
            $ms = [int]((Get-Date) - $start).TotalMilliseconds
            $status = if ($ms -lt 500) { "FAST" } elseif ($ms -lt 2000) { "OK" } else { "SLOW" }
            $color = if ($ms -lt 500) { "Green" } elseif ($ms -lt 2000) { "Cyan" } else { "Yellow" }
            Write-Host "  [OK]   $($api.Name.PadRight(28)) $($resp.StatusCode)  ${ms}ms  [$status]" -ForegroundColor $color
            $healthy++
            $results += @{ Name=$api.Name; Status="UP"; MS=$ms }
        } catch {
            $ms = [int]((Get-Date) - $start).TotalMilliseconds
            Write-Host "  [FAIL] $($api.Name.PadRight(28)) UNREACHABLE" -ForegroundColor Red
            $results += @{ Name=$api.Name; Status="DOWN"; MS=$ms }
        }
    }

    Write-Host ""
    $color = if ($healthy -eq 10) { "Green" } elseif ($healthy -gt 7) { "Yellow" } else { "Red" }
    Write-Host "  $healthy / 10 APIs healthy" -ForegroundColor $color
    Write-Host "  Latency threshold: 2000ms  |  Target: 100% healthy" -ForegroundColor DarkGray
    Pause-Screen
}

function Check-AgentStatus {
    Show-Header
    Write-Host "  Checking Paperclip agent status..." -ForegroundColor Yellow
    Write-Host ""
    try {
        $agents = Invoke-RestMethod `
            -Uri "$PAPERCLIP_URL/api/companies/$COMPANY_ID/agents" `
            -Headers (Get-PaperclipHeaders) `
            -TimeoutSec 15

        $running = 0
        foreach ($agent in $agents) {
            if ($agent.status -in @("active","running","idle")) {
                $running++
                Write-Host "  [OK]   $($agent.name.PadRight(20)) $($agent.status)  |  $($agent.adapterType)" -ForegroundColor Green
            } else {
                Write-Host "  [WARN] $($agent.name.PadRight(20)) $($agent.status)" -ForegroundColor Yellow
            }
        }
        Write-Host ""
        Write-Ok "$running / $($agents.Count) agents running"
        Write-Info "Dashboard: $PAPERCLIP_URL/STA/dashboard"
    } catch {
        Write-Fail "Could not reach Paperclip: $($_.Exception.Message)"
    }
    Pause-Screen
}

function Check-PaperclipHealth {
    Show-Header
    Write-Host "  Checking Paperclip platform health..." -ForegroundColor Yellow
    Write-Host ""
    try {
        $resp = Invoke-WebRequest -Uri "$PAPERCLIP_URL/health" -TimeoutSec 10 -UseBasicParsing
        Write-Ok "Paperclip responding — HTTP $($resp.StatusCode)"
    } catch {
        Write-Fail "Paperclip not responding: $($_.Exception.Message)"
    }
    Write-Host ""
    Write-Info "Dashboard : $PAPERCLIP_URL/STA/dashboard"
    Write-Info "Logs      : railway logs -n 50"
    Pause-Screen
}

function Show-HealthMenu {
    Show-Header
    $choice = Show-Menu "Platform Health" @(
        "Health check all 10 TeQ APIs",
        "Check agent status",
        "Check Paperclip platform",
        "Full health report (all of the above)"
    )
    switch ($choice) {
        "1" { Check-AllAPIs }
        "2" { Check-AgentStatus }
        "3" { Check-PaperclipHealth }
        "4" { Check-AllAPIs; Check-AgentStatus; Check-PaperclipHealth }
    }
}

# ══════════════════════════════════════════════════════════════
#  SECTION 2 — DEPLOYMENT
# ══════════════════════════════════════════════════════════════
function Deploy-Paperclip {
    Show-Header
    Write-Host "  Deploying Paperclip to Railway..." -ForegroundColor Yellow
    Write-Host ""

    if (-not (Test-Path $DEPLOY_DIR)) {
        Write-Fail "Deploy directory not found: $DEPLOY_DIR"
        Pause-Screen
        return
    }

    Push-Location $DEPLOY_DIR
    Write-Info "Running: railway up --detach"
    railway up --detach
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Deploy triggered. Waiting 90s for stabilisation..."
        $dots = 0
        while ($dots -lt 18) {
            Start-Sleep -Seconds 5
            Write-Host "." -NoNewline
            $dots++
        }
        Write-Host ""
        Check-AgentStatus
    } else {
        Write-Fail "railway up failed. Check: railway logs -n 50"
    }
    Pop-Location
    Pause-Screen
}

function Rollback-Worker {
    Show-Header
    Write-Host "  Rollback a Cloudflare Worker" -ForegroundColor Yellow
    Write-Host ""
    $workers = @("aethercast-weather","stratosphere-agro","quasarstream-finance",
                 "nebulametrics-market","meridian-geocoding","zenith-ip",
                 "novamail-email","sentinelauth-identity","nexuslink-url","prismbrand-logo")

    for ($i=0; $i -lt $workers.Count; $i++) {
        Write-Host "  $($i+1). $($workers[$i])" -ForegroundColor White
    }
    Write-Host ""
    $sel = Read-Host "  Select worker (1-10)"
    $idx = [int]$sel - 1
    if ($idx -ge 0 -and $idx -lt $workers.Count) {
        $w = $workers[$idx]
        Write-Info "Listing deployments for $w..."
        wrangler deployments list --name $w
        Write-Host ""
        $ver = Read-Host "  Enter version ID to rollback to (or press Enter to cancel)"
        if ($ver) {
            wrangler rollback $w --version $ver
            Write-Ok "Rollback initiated for $w"
        }
    }
    Pause-Screen
}

function Show-RailwayLogs {
    Show-Header
    Write-Host "  Railway logs (last 50 lines)" -ForegroundColor Yellow
    Write-Host ""
    railway logs -n 50
    Pause-Screen
}

function Verify-GeminiCLI {
    Show-Header
    Write-Host "  Verifying Gemini CLI in Railway container..." -ForegroundColor Yellow
    Write-Host ""
    railway run gemini --version
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Gemini CLI is present in the container"
    } else {
        Write-Fail "Gemini CLI not found - redeploy from $DEPLOY_DIR"
    }
    Pause-Screen
}

function Show-DeployMenu {
    Show-Header
    $choice = Show-Menu "Deployment" @(
        "Deploy Paperclip (full deploy + verify)",
        "Rollback a Cloudflare Worker",
        "View Railway logs",
        "Verify Gemini CLI in container"
    )
    switch ($choice) {
        "1" { Deploy-Paperclip }
        "2" { Rollback-Worker }
        "3" { Show-RailwayLogs }
        "4" { Verify-GeminiCLI }
    }
}

# ══════════════════════════════════════════════════════════════
#  SECTION 3 — SECURITY
# ══════════════════════════════════════════════════════════════
function Check-SecurityHeaders {
    Show-Header
    Write-Host "  Checking security headers on all TeQ APIs..." -ForegroundColor Yellow
    Write-Host ""

    $requiredHeaders = @("X-Content-Type-Options","X-Frame-Options","Content-Security-Policy")

    foreach ($api in $TEQ_APIS) {
        try {
            $resp = Invoke-WebRequest -Uri $api.URL -TimeoutSec 10 -UseBasicParsing -Method HEAD
            $missing = @()
            foreach ($h in $requiredHeaders) {
                if (-not $resp.Headers[$h]) { $missing += $h }
            }
            if ($missing.Count -eq 0) {
                Write-Host "  [OK]   $($api.Name)" -ForegroundColor Green
            } else {
                Write-Host "  [WARN] $($api.Name) — missing: $($missing -join ', ')" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  [FAIL] $($api.Name) — unreachable" -ForegroundColor Red
        }
    }
    Pause-Screen
}

function Check-DNSHealth {
    Show-Header
    Write-Host "  Checking DNS records for starcaller.uk..." -ForegroundColor Yellow
    Write-Host ""
    $records = @("starcaller.uk","weather.starcaller.uk","agro.starcaller.uk",
                 "finance.starcaller.uk","geo.starcaller.uk","ip.starcaller.uk",
                 "mail.starcaller.uk","auth.starcaller.uk","link.starcaller.uk","logo.starcaller.uk")
    foreach ($r in $records) {
        try {
            $result = Resolve-DnsName $r -ErrorAction Stop
            Write-Ok "$r — $($result[0].IPAddress)"
        } catch {
            Write-Fail "$r — could not resolve"
        }
    }
    Pause-Screen
}

function Show-SecurityMenu {
    Show-Header
    $choice = Show-Menu "Security" @(
        "Check security headers on all APIs",
        "DNS health check for starcaller.uk"
    )
    switch ($choice) {
        "1" { Check-SecurityHeaders }
        "2" { Check-DNSHealth }
    }
}

# ══════════════════════════════════════════════════════════════
#  SECTION 4 — AGENT MANAGEMENT
# ══════════════════════════════════════════════════════════════
function Create-PaperclipIssue {
    Show-Header
    Write-Host "  Create a Paperclip Issue" -ForegroundColor Yellow
    Write-Host ""
    $title    = Read-Host "  Issue title"
    $desc     = Read-Host "  Description"
    Write-Host "  Priority: 1=high  2=medium  3=low"
    $priSel   = Read-Host "  Select"
    $priority = switch ($priSel) { "1" {"high"} "2" {"medium"} "3" {"low"} default {"medium"} }

    $body = @{
        title       = $title
        description = $desc
        status      = "backlog"
        priority    = $priority
    } | ConvertTo-Json

    try {
        $resp = Invoke-RestMethod `
            -Uri "$PAPERCLIP_URL/api/companies/$COMPANY_ID/issues" `
            -Method POST `
            -Headers (Get-PaperclipHeaders) `
            -Body $body `
            -TimeoutSec 15
        Write-Ok "Issue created: $($resp.id)"
    } catch {
        Write-Fail "Failed to create issue: $($_.Exception.Message)"
    }
    Pause-Screen
}

function List-PaperclipIssues {
    Show-Header
    Write-Host "  Paperclip Issue Pipeline" -ForegroundColor Yellow
    Write-Host ""
    try {
        $issues = Invoke-RestMethod `
            -Uri "$PAPERCLIP_URL/api/companies/$COMPANY_ID/issues" `
            -Headers (Get-PaperclipHeaders) `
            -TimeoutSec 15

        $backlog     = $issues | Where-Object { $_.status -eq "backlog" }
        $in_progress = $issues | Where-Object { $_.status -eq "in_progress" }
        $done        = $issues | Where-Object { $_.status -eq "done" }

        Write-Host "  BACKLOG ($($backlog.Count))" -ForegroundColor Yellow
        foreach ($i in $backlog) { Write-Host "    · [$($i.priority.ToUpper())] $($i.title)" -ForegroundColor White }

        Write-Host ""
        Write-Host "  IN PROGRESS ($($in_progress.Count))" -ForegroundColor Cyan
        foreach ($i in $in_progress) { Write-Host "    · [$($i.priority.ToUpper())] $($i.title)" -ForegroundColor White }

        Write-Host ""
        Write-Host "  DONE ($($done.Count))" -ForegroundColor Green
        foreach ($i in ($done | Select-Object -Last 5)) { Write-Host "    · $($i.title)" -ForegroundColor DarkGray }
        if ($done.Count -gt 5) { Write-Host "    · ... and $($done.Count - 5) more" -ForegroundColor DarkGray }

    } catch {
        Write-Fail "Could not reach Paperclip: $($_.Exception.Message)"
    }
    Pause-Screen
}

function Switch-AgentModel {
    Show-Header
    Write-Host "  Switch Agent Model/Adapter" -ForegroundColor Yellow
    Write-Host ""
    try {
        $agents = Invoke-RestMethod `
            -Uri "$PAPERCLIP_URL/api/companies/$COMPANY_ID/agents" `
            -Headers (Get-PaperclipHeaders) `
            -TimeoutSec 15

        for ($i=0; $i -lt $agents.Count; $i++) {
            Write-Host "  $($i+1). $($agents[$i].name) — $($agents[$i].adapterType)" -ForegroundColor White
        }
        Write-Host ""
        $sel = Read-Host "  Select agent"
        $idx = [int]$sel - 1
        if ($idx -ge 0 -and $idx -lt $agents.Count) {
            $agent = $agents[$idx]
            Write-Host "  Models: 1=gemma-4-31b-it  2=gemma-3-27b-it  3=gemini-2.0-flash"
            $mSel  = Read-Host "  Select model"
            $model = switch ($mSel) {
                "1" {"gemma-4-31b-it"}
                "2" {"gemma-3-27b-it"}
                "3" {"gemini-2.0-flash"}
                default {"gemma-4-31b-it"}
            }
            $body = @{
                adapterType   = "gemini_local"
                adapterConfig = @{ model = $model; command = "gemini" }
            } | ConvertTo-Json -Depth 5

            Invoke-RestMethod `
                -Uri "$PAPERCLIP_URL/api/agents/$($agent.id)" `
                -Method PATCH `
                -Headers (Get-PaperclipHeaders) `
                -Body $body `
                -TimeoutSec 15 | Out-Null
            Write-Ok "$($agent.name) switched to $model"
        }
    } catch {
        Write-Fail "Failed: $($_.Exception.Message)"
    }
    Pause-Screen
}

function Show-AgentMenu {
    Show-Header
    $choice = Show-Menu "Agent Management" @(
        "View issue pipeline",
        "Create a new issue",
        "Switch agent model/adapter"
    )
    switch ($choice) {
        "1" { List-PaperclipIssues }
        "2" { Create-PaperclipIssue }
        "3" { Switch-AgentModel }
    }
}

# ══════════════════════════════════════════════════════════════
#  SECTION 5 — BUSINESS & BILLING (stub — needs Stripe key)
# ══════════════════════════════════════════════════════════════
function Show-BillingMenu {
    Show-Header
    Write-Host "  Business & Billing" -ForegroundColor Yellow
    Write-Host ""
    if (-not $STRIPE_KEY) {
        Write-Warn "Stripe API key not configured."
        Write-Info "Add your key to the STRIPE_KEY variable at the top of this script."
        Write-Host ""
        Write-Host "  Once configured, this section will show:" -ForegroundColor DarkGray
        Write-Host "    · Monthly revenue by tier (Free/Basic/Pro/Enterprise)" -ForegroundColor DarkGray
        Write-Host "    · Active subscriber count" -ForegroundColor DarkGray
        Write-Host "    · Customers approaching quota limits" -ForegroundColor DarkGray
        Write-Host "    · Outstanding invoices" -ForegroundColor DarkGray
        Write-Host "    · Overage charges this month" -ForegroundColor DarkGray
    } else {
        Write-Info "Stripe connected — billing features coming in next update"
    }
    Pause-Screen
}

# ══════════════════════════════════════════════════════════════
#  MAIN MENU
# ══════════════════════════════════════════════════════════════
function Show-MainMenu {
    while ($true) {
        Show-Header
        Write-Host "  Main Menu" -ForegroundColor Yellow
        Write-Host "  ─────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host "  1. Platform Health" -ForegroundColor White
        Write-Host "  2. Deployment" -ForegroundColor White
        Write-Host "  3. Security" -ForegroundColor White
        Write-Host "  4. Agent Management" -ForegroundColor White
        Write-Host "  5. Business & Billing" -ForegroundColor White
        Write-Host ""
        Write-Host "  0. Exit" -ForegroundColor DarkGray
        Write-Host ""
        $choice = Read-Host "  Select"

        switch ($choice) {
            "1" { Show-HealthMenu }
            "2" { Show-DeployMenu }
            "3" { Show-SecurityMenu }
            "4" { Show-AgentMenu }
            "5" { Show-BillingMenu }
            "0" {
                Write-Host ""
                Write-Host "  Goodbye. StarTeQ is watching." -ForegroundColor Cyan
                Write-Host ""
                exit 0
            }
        }
    }
}

# ── Entry point ──────────────────────────────────────────────
Show-MainMenu
