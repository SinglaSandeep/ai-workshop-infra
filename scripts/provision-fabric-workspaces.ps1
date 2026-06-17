<#
.SYNOPSIS
    Bulk-provisions Microsoft Fabric workspaces for workshop attendees and
    binds each one to the workshop Fabric capacity.

.DESCRIPTION
    For each attendee in the input CSV this script:
      1. Creates a Fabric workspace named "<WorkspacePrefix>-<userSlug>".
      2. Binds it to the workshop Fabric capacity.
      3. Adds the attendee as Admin on their workspace so they can create
         the Lakehouse, run notebooks, build the Power BI semantic model,
         and create a Fabric Data Agent.

    Idempotent: if a workspace with the same name already exists, the script
    updates its capacity + role assignments rather than creating a duplicate.

    Writes a mapping CSV (UPN -> workspace name -> workspace id -> URL) for
    handout to attendees.

.PARAMETER AttendeesCsv
    Path to a CSV with columns: UPN, ObjectId, DisplayName.
    DisplayName is optional (defaults to the UPN local-part).

.PARAMETER CapacityName
    Azure resource name of the Fabric capacity (e.g.
    fabpepsiwspz6amwca5pv26). The script looks up its Fabric capacity GUID
    via the Fabric REST API.

.PARAMETER WorkspacePrefix
    Prefix for every workspace name. Default 'ws-pepsi-day2'.

.PARAMETER OutputCsv
    Path to write the attendee-to-workspace mapping. Default
    .azure/workspace-assignments.csv.

.PARAMETER WhatIf
    Print the actions but do not call the Fabric API.

.EXAMPLE
    ./scripts/provision-fabric-workspaces.ps1 `
        -AttendeesCsv attendees.csv `
        -CapacityName fabpepsiwspz6amwca5pv26

.NOTES
    - You must be a Fabric admin / capacity admin to run this.
    - The capacity must already exist and be in Active state.
    - Auth: az login + az account get-access-token --resource https://api.fabric.microsoft.com
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)] [string] $AttendeesCsv,
    [Parameter(Mandatory = $true)] [string] $CapacityName,
    [string] $WorkspacePrefix = 'ws-pepsi-day2',
    [string] $OutputCsv
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputCsv) {
    $outDir = Join-Path $projectRoot '.azure'
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
    $OutputCsv = Join-Path $outDir 'workspace-assignments.csv'
}

if (-not (Test-Path $AttendeesCsv)) {
    throw "Attendees CSV not found: $AttendeesCsv"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Get-FabricToken {
    Write-Verbose 'Acquiring Fabric API token...'
    $tokenJson = az account get-access-token --resource 'https://api.fabric.microsoft.com' -o json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Could not acquire Fabric API token. Run 'az login' first. Output: $tokenJson"
    }
    return ($tokenJson | ConvertFrom-Json).accessToken
}

function Invoke-Fabric {
    param(
        [string] $Method,
        [string] $Path,
        [object] $Body,
        [string] $Token
    )
    $url = "https://api.fabric.microsoft.com/v1$Path"
    $headers = @{
        Authorization = "Bearer $Token"
        'Content-Type' = 'application/json'
    }
    $bodyJson = if ($null -ne $Body) { ($Body | ConvertTo-Json -Depth 10) } else { $null }
    try {
        if ($bodyJson) {
            Invoke-RestMethod -Method $Method -Uri $url -Headers $headers -Body $bodyJson
        } else {
            Invoke-RestMethod -Method $Method -Uri $url -Headers $headers
        }
    } catch {
        $resp = $_.Exception.Response
        if ($resp) {
            $stream = $resp.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $detail = $reader.ReadToEnd()
            throw "Fabric API $Method $Path failed: $($resp.StatusCode) - $detail"
        }
        throw
    }
}

function Slugify {
    param([string] $upn)
    $local = $upn.Split('@')[0]
    return ($local -replace '[^a-zA-Z0-9]', '').ToLower()
}

# ---------------------------------------------------------------------------
# Load attendees
# ---------------------------------------------------------------------------
$attendees = Import-Csv -Path $AttendeesCsv
if (-not $attendees) { throw "Attendees CSV is empty: $AttendeesCsv" }
$required = @('UPN','ObjectId')
foreach ($col in $required) {
    if ($attendees[0].PSObject.Properties.Name -notcontains $col) {
        throw "Attendees CSV missing required column '$col'. Required columns: $($required -join ', '). Optional: DisplayName."
    }
}
Write-Host "Loaded $($attendees.Count) attendees from $AttendeesCsv"

# ---------------------------------------------------------------------------
# Auth + capacity lookup
# ---------------------------------------------------------------------------
$token = Get-FabricToken
Write-Host "Looking up Fabric capacity '$CapacityName'..."
$capList = Invoke-Fabric -Method GET -Path '/capacities' -Token $token
$cap = $capList.value | Where-Object { $_.displayName -eq $CapacityName }
if (-not $cap) {
    throw "Fabric capacity '$CapacityName' not found via Fabric REST API. Available: $(($capList.value | Select-Object -ExpandProperty displayName) -join ', ')"
}
$capacityId = $cap.id
Write-Host "  Capacity id: $capacityId (state: $($cap.state))"
if ($cap.state -ne 'Active') {
    Write-Warning "  Capacity is not Active (state=$($cap.state)). Workspace creation may fail."
}

# ---------------------------------------------------------------------------
# List existing workspaces (idempotency)
# ---------------------------------------------------------------------------
Write-Host 'Listing existing workspaces for idempotency check...'
$existingMap = @{}
$wsList = Invoke-Fabric -Method GET -Path '/workspaces' -Token $token
foreach ($w in $wsList.value) { $existingMap[$w.displayName] = $w }

# ---------------------------------------------------------------------------
# Per-attendee loop
# ---------------------------------------------------------------------------
$results = @()
$ok = 0; $failed = 0
foreach ($a in $attendees) {
    $slug = Slugify -upn $a.UPN
    $wsName = "$WorkspacePrefix-$slug"

    Write-Host ""
    Write-Host "[$($a.UPN)] -> $wsName"

    try {
        # Create or reuse
        if ($existingMap.ContainsKey($wsName)) {
            $ws = $existingMap[$wsName]
            Write-Host "  Workspace exists (id=$($ws.id)). Will ensure capacity + role assignment."
            if ($PSCmdlet.ShouldProcess($wsName, "Assign capacity $capacityId")) {
                Invoke-Fabric -Method POST -Path "/workspaces/$($ws.id)/assignToCapacity" -Body @{ capacityId = $capacityId } -Token $token | Out-Null
            }
        } else {
            if ($PSCmdlet.ShouldProcess($wsName, "Create workspace on capacity $capacityId")) {
                $ws = Invoke-Fabric -Method POST -Path '/workspaces' -Body @{
                    displayName = $wsName
                    description = "Workshop workspace for $($a.UPN)"
                    capacityId  = $capacityId
                } -Token $token
                Write-Host "  Created workspace id=$($ws.id)"
            }
        }

        # Add attendee as Admin
        if ($PSCmdlet.ShouldProcess("$wsName / $($a.UPN)", 'Add Admin role')) {
            try {
                Invoke-Fabric -Method POST -Path "/workspaces/$($ws.id)/roleAssignments" -Body @{
                    principal = @{ id = $a.ObjectId; type = 'User' }
                    role      = 'Admin'
                } -Token $token | Out-Null
                Write-Host "  Granted Admin to $($a.UPN)"
            } catch {
                if ("$_" -match 'already exists|PrincipalAlreadyHasWorkspaceRolePermissions|Conflict|\b400\b|\b409\b') {
                    Write-Host "  Admin role already present (skipping)."
                } else { throw }
            }
        }

        $results += [pscustomobject]@{
            UPN          = $a.UPN
            ObjectId     = $a.ObjectId
            WorkspaceName = $wsName
            WorkspaceId  = $ws.id
            WorkspaceUrl = "https://app.fabric.microsoft.com/groups/$($ws.id)"
            Status       = 'OK'
            Error        = ''
        }
        $ok++
    } catch {
        Write-Warning "  FAILED: $_"
        $results += [pscustomobject]@{
            UPN          = $a.UPN
            ObjectId     = $a.ObjectId
            WorkspaceName = $wsName
            WorkspaceId  = ''
            WorkspaceUrl = ''
            Status       = 'FAILED'
            Error        = ("$_").Substring(0, [Math]::Min(500, "$_".Length))
        }
        $failed++
    }
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
$results | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding utf8
Write-Host ""
Write-Host "================================================================"
Write-Host "Summary: $ok succeeded, $failed failed (out of $($attendees.Count))."
Write-Host "Mapping CSV written to: $OutputCsv"
Write-Host "Share each attendee's WorkspaceUrl from that CSV."
Write-Host "================================================================"
if ($failed -gt 0) { exit 1 }
