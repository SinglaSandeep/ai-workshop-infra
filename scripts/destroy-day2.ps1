<#
.SYNOPSIS
    Tear down the Day 2 (Data) slim deployment.

.DESCRIPTION
    Deletes the three Day 2 resources from the target resource group:
      - Microsoft Fabric capacity
      - Azure SQL server + database
      - Microsoft Purview account

    Does NOT delete the resource group itself (Sandeep's Day 1 resources
    live in the same RG).

.PARAMETER ResourceGroupName
    The Day 2 RG (same as Sandeep's Day 1 RG).

.PARAMETER Force
    Skip the confirmation prompt.

.EXAMPLE
    ./scripts/destroy-day2.ps1 -ResourceGroupName rg-pepsi-shared
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $ResourceGroupName,
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$outputsFile = Join-Path $projectRoot '.azure/main-day2-outputs.json'

if (-not (Test-Path $outputsFile)) {
    Write-Warning "Outputs file not found at $outputsFile; will discover Day 2 resources by tag/type."
    $fabricName = (az resource list -g $ResourceGroupName --resource-type Microsoft.Fabric/capacities --query "[0].name" -o tsv)
    $purviewName = (az resource list -g $ResourceGroupName --resource-type Microsoft.Purview/accounts --query "[0].name" -o tsv)
    $sqlServerName = (az resource list -g $ResourceGroupName --resource-type Microsoft.Sql/servers --query "[0].name" -o tsv)
} else {
    $outputs = Get-Content $outputsFile | ConvertFrom-Json
    $fabricName = $outputs.fabricCapacityName.value
    $purviewName = $outputs.purviewAccountName.value
    $sqlServerName = if ($outputs.sqlServerFqdn.value) { $outputs.sqlServerFqdn.value.Split('.')[0] } else { '' }
}

Write-Host "== Day 2 teardown plan =="
Write-Host "  Resource group : $ResourceGroupName"
Write-Host "  Fabric capacity: $fabricName"
Write-Host "  SQL server     : $sqlServerName"
Write-Host "  Purview account: $purviewName"
Write-Host ""

if (-not $Force) {
    $confirm = Read-Host "Delete the three resources above? (yes/N)"
    if ($confirm -ne 'yes') { Write-Host 'Aborted.'; return }
}

if ($sqlServerName) {
    Write-Host "Deleting SQL server $sqlServerName (and its databases)..."
    az sql server delete --resource-group $ResourceGroupName --name $sqlServerName --yes --only-show-errors
}
if ($fabricName) {
    Write-Host "Deleting Fabric capacity $fabricName..."
    az resource delete --resource-group $ResourceGroupName --name $fabricName --resource-type Microsoft.Fabric/capacities --only-show-errors
}
if ($purviewName) {
    Write-Host "Deleting Purview account $purviewName..."
    az purview account delete --resource-group $ResourceGroupName --name $purviewName --yes --only-show-errors
}

Write-Host ""
Write-Host "Done. The resource group '$ResourceGroupName' was NOT deleted (Sandeep's Day 1 resources may still live there)."
