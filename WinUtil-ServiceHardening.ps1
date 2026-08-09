#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Safe post-WinUtil follow-up: disable leftover diagnostic/telemetry services
  and verify critical Windows services were not broken.

.DESCRIPTION
 This script:
    1) Stops and sets recommended-disable services to Disabled
    2) Verifies DiagTrack is Disabled
    3) Asserts protected services remain present and not Disabled
    4) Prints a clear before/after report

  Protected services are NEVER modified by this script.

.PARAMETER WhatIf
  Show what would change without modifying anything.

.PARAMETER SkipXbox
  Do not disable Xbox Live services (XblAuthManager, XblGameSave, XboxNetApiSvc).

.PARAMETER SkipDPS
  Do not disable Diagnostic Policy Service (needed for Windows Troubleshooters).

.EXAMPLE
  .\WinUtil-ServiceHardening.ps1 -WhatIf

.EXAMPLE
  .\WinUtil-ServiceHardening.ps1

.EXAMPLE
  .\WinUtil-ServiceHardening.ps1 -SkipXbox -SkipDPS
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$SkipXbox,
    [switch]$SkipDPS
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Services to disable (safe for typical modern home PCs after WinUtil)
# ---------------------------------------------------------------------------
$DisableTargets = [ordered]@{
    DiagTrack        = 'Connected User Experiences and Telemetry'
    dmwappushservice = 'WAP Push Message Routing Service'
    DPS              = 'Diagnostic Policy Service'
    PcaSvc           = 'Program Compatibility Assistant Service'
    RemoteRegistry   = 'Remote Registry'
    lmhosts          = 'TCP/IP NetBIOS Helper'
    MapsBroker       = 'Downloaded Maps Manager'
    XblAuthManager   = 'Xbox Live Auth Manager'
    XblGameSave      = 'Xbox Live Game Save'
    XboxNetApiSvc    = 'Xbox Live Networking Service'
}

if ($SkipDPS) {
    $DisableTargets.Remove('DPS')
}

if ($SkipXbox) {
    foreach ($name in @('XblAuthManager', 'XblGameSave', 'XboxNetApiSvc')) {
        $DisableTargets.Remove($name)
    }
}

# ---------------------------------------------------------------------------
# Must NEVER be touched / must not end up Disabled
# ---------------------------------------------------------------------------
$ProtectedServices = [ordered]@{
    wuauserv  = 'Windows Update'
    WinDefend = 'Windows Defender Antivirus Service'
    Dhcp      = 'DHCP Client'
    PlugPlay  = 'Plug and Play'
    CryptSvc  = 'Cryptographic Services'
}

function Get-ServiceSnapshot {
    param([string]$Name)

    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) {
        return [pscustomobject]@{
            Name        = $Name
            DisplayName = '(not installed)'
            Status      = 'Missing'
            StartType   = 'Missing'
            Exists      = $false
        }
    }

    # Prefer CIM for reliable StartMode on all editions
    $cim = Get-CimInstance -ClassName Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    $startType = if ($cim) { $cim.StartMode } else { $svc.StartType.ToString() }

    # Normalize Manual/Auto naming across Get-Service vs CIM
    switch -Regex ($startType) {
        '^(Auto|Automatic)$' { $startType = 'Automatic' }
        '^(Manual|Demand)$'  { $startType = 'Manual' }
        '^(Disabled)$'       { $startType = 'Disabled' }
        '^(Boot)$'           { $startType = 'Boot' }
        '^(System)$'         { $startType = 'System' }
    }

    [pscustomobject]@{
        Name        = $svc.Name
        DisplayName = $svc.DisplayName
        Status      = $svc.Status.ToString()
        StartType   = $startType
        Exists      = $true
    }
}

function Set-ServiceDisabledSafe {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [string]$FriendlyName
    )

    $before = Get-ServiceSnapshot -Name $Name
    if (-not $before.Exists) {
        Write-Host ("  SKIP  {0,-18} not installed on this system" -f $Name) -ForegroundColor DarkYellow
        return [pscustomobject]@{
            Name      = $Name
            Action    = 'Skipped (missing)'
            Before    = $before.StartType
            After     = $before.StartType
            Status    = $before.Status
            Changed   = $false
        }
    }

    $needsDisable = $before.StartType -ne 'Disabled'
    $needsStop    = $before.Status -eq 'Running'

    if (-not $needsDisable -and -not $needsStop) {
        Write-Host ("  OK    {0,-18} already Disabled / Stopped" -f $Name) -ForegroundColor Green
        return [pscustomobject]@{
            Name      = $Name
            Action    = 'Already hardened'
            Before    = $before.StartType
            After     = $before.StartType
            Status    = $before.Status
            Changed   = $false
        }
    }

    $desc = if ($FriendlyName) { "$Name ($FriendlyName)" } else { $Name }

    if ($PSCmdlet.ShouldProcess($desc, 'Stop and set StartType=Disabled')) {
        try {
            if ($needsStop) {
                Stop-Service -Name $Name -Force -ErrorAction Stop
            }
            if ($needsDisable) {
                Set-Service -Name $Name -StartupType Disabled -ErrorAction Stop
            }
        }
        catch {
            Write-Host ("  FAIL  {0,-18} {1}" -f $Name, $_.Exception.Message) -ForegroundColor Red
            $afterFail = Get-ServiceSnapshot -Name $Name
            return [pscustomobject]@{
                Name      = $Name
                Action    = "Failed: $($_.Exception.Message)"
                Before    = $before.StartType
                After     = $afterFail.StartType
                Status    = $afterFail.Status
                Changed   = $false
            }
        }
    }

    $after = Get-ServiceSnapshot -Name $Name
    $label = if ($WhatIfPreference) { 'Would harden' } else { 'Hardened' }
    Write-Host ("  SET   {0,-18} {1} -> {2} ({3})" -f $Name, $before.StartType, $after.StartType, $after.Status) -ForegroundColor Cyan

    [pscustomobject]@{
        Name      = $Name
        Action    = $label
        Before    = $before.StartType
        After     = $after.StartType
        Status    = $after.Status
        Changed   = $true
    }
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor White
Write-Host ' WinUtil follow-up: service hardening + protected checks' -ForegroundColor White
Write-Host '============================================================' -ForegroundColor White
if ($WhatIfPreference) {
    Write-Host ' Mode: WhatIf (no changes will be made)' -ForegroundColor Yellow
}
else {
    Write-Host ' Mode: Apply changes' -ForegroundColor Yellow
}
Write-Host ''

# --- Protected pre-check (abort hardening if any critical service is already Disabled) ---
Write-Host 'Protected services (will NOT be modified):' -ForegroundColor White
$protectedIssues = @()
$protectedReport = foreach ($entry in $ProtectedServices.GetEnumerator()) {
    $snap = Get-ServiceSnapshot -Name $entry.Key
    $ok = $snap.Exists -and ($snap.StartType -ne 'Disabled')

    if (-not $snap.Exists) {
        # WinDefend can be absent on Server / some SKUs; treat as warning not hard fail
        if ($entry.Key -eq 'WinDefend') {
            Write-Host ("  WARN  {0,-18} not present (OK on some SKUs)" -f $entry.Key) -ForegroundColor DarkYellow
            $state = 'Warning'
        }
        else {
            Write-Host ("  BAD   {0,-18} MISSING" -f $entry.Key) -ForegroundColor Red
            $protectedIssues += $entry.Key
            $state = 'Missing'
        }
    }
    elseif ($snap.StartType -eq 'Disabled') {
        Write-Host ("  BAD   {0,-18} is Disabled (StartType={1}, Status={2})" -f $entry.Key, $snap.StartType, $snap.Status) -ForegroundColor Red
        $protectedIssues += $entry.Key
        $state = 'Disabled'
    }
    else {
        Write-Host ("  OK    {0,-18} StartType={1,-10} Status={2}" -f $entry.Key, $snap.StartType, $snap.Status) -ForegroundColor Green
        $state = 'OK'
    }

    [pscustomobject]@{
        Name      = $entry.Key
        Purpose   = $entry.Value
        StartType = $snap.StartType
        Status    = $snap.Status
        State     = $state
    }
}

if ($protectedIssues.Count -gt 0 -and -not $WhatIfPreference) {
    Write-Host ''
    Write-Host 'Aborting: one or more protected services are Disabled/missing.' -ForegroundColor Red
    Write-Host 'Fix those first (services.msc or Set-Service) before hardening.' -ForegroundColor Red
    exit 2
}

Write-Host ''
Write-Host 'Services to disable / verify:' -ForegroundColor White
$disableReport = foreach ($entry in $DisableTargets.GetEnumerator()) {
    Set-ServiceDisabledSafe -Name $entry.Key -FriendlyName $entry.Value
}

# --- Final verification ---
Write-Host ''
Write-Host 'Final verification:' -ForegroundColor White

$disableFailed = @()
foreach ($entry in $DisableTargets.GetEnumerator()) {
    $snap = Get-ServiceSnapshot -Name $entry.Key
    if (-not $snap.Exists) {
        Write-Host ("  SKIP  {0,-18} not installed" -f $entry.Key) -ForegroundColor DarkYellow
        continue
    }
    if ($WhatIfPreference) {
        $would = if ($snap.StartType -eq 'Disabled') { 'already Disabled' } else { "would set Disabled (now $($snap.StartType))" }
        Write-Host ("  CHECK {0,-18} {1}" -f $entry.Key, $would) -ForegroundColor Cyan
        continue
    }
    if ($snap.StartType -eq 'Disabled') {
        Write-Host ("  OK    {0,-18} Disabled / {1}" -f $entry.Key, $snap.Status) -ForegroundColor Green
    }
    else {
        Write-Host ("  FAIL  {0,-18} still {1}" -f $entry.Key, $snap.StartType) -ForegroundColor Red
        $disableFailed += $entry.Key
    }
}

Write-Host ''
Write-Host 'Protected services (post-check, untouched):' -ForegroundColor White
$protectedBroken = @()
foreach ($entry in $ProtectedServices.GetEnumerator()) {
    $snap = Get-ServiceSnapshot -Name $entry.Key
    if (-not $snap.Exists) {
        if ($entry.Key -eq 'WinDefend') {
            Write-Host ("  WARN  {0,-18} not present" -f $entry.Key) -ForegroundColor DarkYellow
        }
        else {
            Write-Host ("  BAD   {0,-18} MISSING" -f $entry.Key) -ForegroundColor Red
            $protectedBroken += $entry.Key
        }
        continue
    }
    if ($snap.StartType -eq 'Disabled') {
        Write-Host ("  BAD   {0,-18} Disabled" -f $entry.Key) -ForegroundColor Red
        $protectedBroken += $entry.Key
    }
    else {
        Write-Host ("  OK    {0,-18} StartType={1,-10} Status={2}" -f $entry.Key, $snap.StartType, $snap.Status) -ForegroundColor Green
    }
}

Write-Host ''
Write-Host 'Summary' -ForegroundColor White
Write-Host '-------'
$changed = @($disableReport | Where-Object Changed).Count
Write-Host ("  Disable targets processed : {0}" -f $DisableTargets.Count)
Write-Host ("  Changed (or would change) : {0}" -f $changed)
Write-Host ("  Disable verification fails: {0}" -f $disableFailed.Count)
Write-Host ("  Protected issues          : {0}" -f $protectedBroken.Count)
Write-Host ''

if ($disableFailed.Count -gt 0 -or $protectedBroken.Count -gt 0) {
    Write-Host 'Completed with issues. Review FAIL/BAD lines above.' -ForegroundColor Red
    exit 1
}

if ($WhatIfPreference) {
    Write-Host 'WhatIf complete. Re-run without -WhatIf to apply.' -ForegroundColor Yellow
}
else {
    Write-Host 'Done. Recommended disable list is Disabled; protected services untouched.' -ForegroundColor Green
}

exit 0
