<#
.SYNOPSIS
    Deletes the workshop Fabric workspaces created by
    provision-fabric-workspaces.ps1.

.DESCRIPTION
    Reads the mapping CSV (default: .azure/workspace-assignments.csv)
    written by the provisioning script and DELETEs each workspace via
    the Fabric REST API.

.PARAMETER MappingCsv
    Path to the mapping CSV. Default '.azure/workspace-assignments.csv'.

.PARAMETER WhatIf
    Print actions without calling the API.

.EXAMPLE
    ./scripts/deprovision-fabric-workspaces.ps1
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string] $MappingCsv
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $MappingCsv) { $MappingCsv = Join-Path $projectRoot '.azure/workspace-assignments.csv' }
if (-not (Test-Path $MappingCsv)) { throw "Mapping CSV not found: $MappingCsv" }

$token = az account get-access-token --resource 'https://api.fabric.microsoft.com' --query accessToken -o tsv
if (-not $token) { throw "Could not acquire Fabric token. Run 'az login' first." }

$rows = Import-Csv -Path $MappingCsv | Where-Object { $_.WorkspaceId }
Write-Host "Will delete $($rows.Count) workspaces from $MappingCsv"
$ok = 0; $fail = 0
foreach ($r in $rows) {
    if (-not $PSCmdlet.ShouldProcess("$($r.WorkspaceName) ($($r.WorkspaceId))", 'DELETE workspace')) { continue }
    try {
        Invoke-RestMethod -Method DELETE `
            -Uri "https://api.fabric.microsoft.com/v1/workspaces/$($r.WorkspaceId)" `
            -Headers @{ Authorization = "Bearer $token" } | Out-Null
        Write-Host "  deleted $($r.WorkspaceName)"
        $ok++
    } catch {
        Write-Warning "  FAILED $($r.WorkspaceName): $_"
        $fail++
    }
}
Write-Host ""
Write-Host "Summary: $ok deleted, $fail failed."
if ($fail -gt 0) { exit 1 }
