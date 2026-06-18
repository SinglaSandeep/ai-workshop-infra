<#
.SYNOPSIS
    Part C - Grant resource (service / app) access.

.DESCRIPTION
    Deploys infra/resource-access.bicep, which grants the service principals /
    apps listed in infra/resource-access.parameters.json access at the resource
    group scope (default Contributor). Services authenticate to each other with
    keys / connection settings, so no per-resource role assignments are needed.

    Edit infra/resource-access.parameters.json first to list the real Entra
    service principals / apps and adjust the access level. Run this AFTER
    scripts/deploy.ps1.

.PARAMETER ResourceGroup
    Target resource group. Defaults to the azd environment value.

.EXAMPLE
    ./scripts/grant-resource-access.ps1
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$ResourceAccessParametersFile = 'infra/resource-access.parameters.json',

    [Parameter(Mandatory = $false)]
    [string]$DeploymentName = 'workshop-resource-access'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

$projectRoot = Get-ProjectRoot
Push-Location $projectRoot
try {
    $ResourceGroup = Resolve-ResourceGroup -ResourceGroup $ResourceGroup
    if ($SubscriptionId) {
        az account set --subscription $SubscriptionId | Out-Null
    }

    Write-Host '== Part C: granting resource (service / app) access =='
    $deploymentJson = az deployment group create `
        --resource-group $ResourceGroup `
        --name $DeploymentName `
        --template-file 'infra/resource-access.bicep' `
        --parameters ('@' + $ResourceAccessParametersFile) `
        --only-show-errors -o json
    if ($LASTEXITCODE -ne 0) {
        throw "Resource access deployment failed with exit code $LASTEXITCODE. Check that every objectId in $ResourceAccessParametersFile is a real Entra service-principal id (not the 00000000... placeholder)."
    }

    $summary = ($deploymentJson | ConvertFrom-Json).properties.outputs.summary.value

    Write-Host ''
    Write-Host "Resource access granted: $($summary.resourceGroupRoleName) at resource group scope to $($summary.principalsGranted) principal(s)."
}
finally {
    Pop-Location
}
