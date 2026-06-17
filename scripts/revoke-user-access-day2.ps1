<#
.SYNOPSIS
    Revoke Day 2 Data Platform workshop participant access (RBAC cleanup).

.DESCRIPTION
    Removes all role assignments created by grant-user-access-day2.ps1.
    This script deletes the 'workshop-user-access-day2' deployment, which
    automatically removes all RBAC role assignments for Day 2 resources.

    Use this for cleanup after the workshop or to reset permissions.

.PARAMETER ResourceGroup
    Target resource group. Defaults to the azd environment value.

.PARAMETER SubscriptionId
    Azure subscription ID. Optional.

.PARAMETER DeploymentName
    Name of the deployment to delete.

.EXAMPLE
    ./scripts/revoke-user-access-day2.ps1

.EXAMPLE
    ./scripts/revoke-user-access-day2.ps1 -ResourceGroup "rg-workshop-prod"
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$DeploymentName = 'workshop-user-access-day2'
)

$ErrorActionPreference = 'Stop'

function Get-ProjectRoot {
    Split-Path -Parent $PSScriptRoot
}

function Get-AzdEnvValues {
    $values = @{}
    $lines = azd env get-values 2>$null
    foreach ($line in $lines) {
        if ($line -match '^([^=]+)=(.*)$') {
            $values[$matches[1]] = $matches[2].Trim('"')
        }
    }
    return $values
}

$projectRoot = Get-ProjectRoot
Push-Location $projectRoot
try {
    if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
        $ResourceGroup = (Get-AzdEnvValues)['AZURE_RESOURCE_GROUP']
    }
    if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
        throw 'AZURE_RESOURCE_GROUP not found. Pass -ResourceGroup or run inside an azd environment.'
    }
    if ($SubscriptionId) {
        az account set --subscription $SubscriptionId | Out-Null
    }

    Write-Host '== Day 2: Revoking participant access (RBAC cleanup) ==' -ForegroundColor Cyan
    Write-Host ''
    Write-Host "Resource Group: $ResourceGroup" -ForegroundColor Gray
    Write-Host "Deployment    : $DeploymentName" -ForegroundColor Gray
    Write-Host ''

    # Check if deployment exists
    $deploymentExists = az deployment group show `
        --resource-group $ResourceGroup `
        --name $DeploymentName `
        --query 'id' `
        --output tsv 2>$null

    if (-not $deploymentExists) {
        Write-Host "⚠️  Deployment '$DeploymentName' not found. Nothing to revoke." -ForegroundColor Yellow
        exit 0
    }

    # Delete the deployment (this removes all role assignments it created)
    Write-Host "Deleting deployment '$DeploymentName'..." -ForegroundColor Gray
    az deployment group delete `
        --resource-group $ResourceGroup `
        --name $DeploymentName `
        --no-wait

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to delete deployment with exit code $LASTEXITCODE."
    }

    Write-Host ''
    Write-Host '✅ Day 2 participant access revoked successfully!' -ForegroundColor Green
    Write-Host ''
    Write-Host 'All Day 2 RBAC role assignments have been removed:' -ForegroundColor Cyan
    Write-Host '  - Azure OpenAI: Cognitive Services User' -ForegroundColor Gray
    Write-Host '  - Azure ML: AzureML Data Scientist' -ForegroundColor Gray
    Write-Host '  - Storage: Storage Blob Data Contributor' -ForegroundColor Gray
    Write-Host '  - Key Vault: Key Vault Secrets User' -ForegroundColor Gray
    Write-Host '  - PostgreSQL: Reader role' -ForegroundColor Gray
    Write-Host ''
    Write-Host 'Note: Resources still exist. Use "azd down" to delete infrastructure.' -ForegroundColor Yellow
    Write-Host ''
}
finally {
    Pop-Location
}
