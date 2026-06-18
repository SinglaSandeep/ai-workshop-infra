<#
.SYNOPSIS
    Part D - Grant workshop participants their access (RBAC).

.DESCRIPTION
    Deploys infra/user-access.bicep, which grants every principal listed in
    infra/user-access.parameters.json Contributor at the resource group scope
    (manage/use every resource in the workshop RG). With key-based auth enabled,
    Contributor lets participants read the resource keys / connection settings
    they need (including Cosmos).

    Run this AFTER scripts/deploy.ps1. Edit infra/user-access.parameters.json
    first to list the real Entra users or groups and adjust the access level.

.PARAMETER ResourceGroup
    Target resource group. Defaults to the azd environment value.

.EXAMPLE
    ./scripts/grant-user-access.ps1
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$UserAccessParametersFile = 'infra/user-access.parameters.json',

    [Parameter(Mandatory = $false)]
    [string]$DeploymentName = 'workshop-user-access'
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

    Write-Host '== Part D: granting participant access (RBAC) =='
    az deployment group create `
        --resource-group $ResourceGroup `
        --name $DeploymentName `
        --template-file 'infra/user-access.bicep' `
        --parameters ('@' + $UserAccessParametersFile) `
        --only-show-errors | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Participant access deployment failed with exit code $LASTEXITCODE. Check that every objectId in $UserAccessParametersFile is a real Entra user/group id (not the 00000000... placeholder)."
    }

    Write-Host 'Participant access granted.'
}
finally {
    Pop-Location
}
