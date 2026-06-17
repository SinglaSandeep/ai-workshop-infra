<#
.SYNOPSIS
    Part C - Grant resource (service-to-service) access.

.DESCRIPTION
    Deploys infra/resource-access.bicep, which grants the workshop's own
    services the permissions they need to call each other at runtime, using
    managed identities (no keys):
      - Foundry project -> AI Search        (read the Foundry IQ knowledge base)
      - Foundry account -> Container Registry (pull hosted-agent images)

    Each grant and its role level is configurable in
    infra/resource-access.parameters.json. Run this AFTER scripts/deploy.ps1.

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
    [string]$MainOutputsFile = '.azure/main-outputs.json',

    [Parameter(Mandatory = $false)]
    [string]$ResourceAccessParametersFile = 'infra/resource-access.parameters.json',

    [Parameter(Mandatory = $false)]
    [string]$DeploymentName = 'workshop-resource-access'
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
    if (-not (Test-Path $MainOutputsFile)) {
        throw "Deployment outputs '$MainOutputsFile' not found. Run ./scripts/deploy.ps1 first."
    }
    if ($SubscriptionId) {
        az account set --subscription $SubscriptionId | Out-Null
    }

    $outputs = Get-Content $MainOutputsFile -Raw | ConvertFrom-Json
    $names = $outputs.resourceNames.value
    $principals = $outputs.managedIdentityPrincipals.value

    Write-Host '== Part C: granting resource (service-to-service) access =='
    $deploymentJson = az deployment group create `
        --resource-group $ResourceGroup `
        --name $DeploymentName `
        --template-file 'infra/resource-access.bicep' `
        --parameters ('@' + $ResourceAccessParametersFile) `
        --parameters "searchServiceName=$($names.aiSearch)" `
        --parameters "containerRegistryName=$($names.containerRegistry)" `
        --parameters "cosmosAccountName=$($names.cosmosDb)" `
        --parameters "foundryPrimaryProjectPrincipalId=$($principals.aiProjectPrincipalId)" `
        --parameters "foundrySecondaryProjectPrincipalId=$($principals.aiProjectSecondaryPrincipalId)" `
        --parameters "foundryPrimaryAccountPrincipalId=$($principals.aiFoundryPrincipalId)" `
        --parameters "foundrySecondaryAccountPrincipalId=$($principals.aiFoundrySecondaryPrincipalId)" `
        --parameters "containerAppsWorkloadPrincipalId=$($principals.workloadIdentityPrincipalId)" `
        --only-show-errors -o json
    if ($LASTEXITCODE -ne 0) {
        throw "Resource access deployment failed with exit code $LASTEXITCODE."
    }

    $summary = ($deploymentJson | ConvertFrom-Json).properties.outputs.summary.value

    Write-Host ''
    Write-Host 'Resource access granted:'
    $grants = @(
        [pscustomobject]@{ From = 'Foundry project';          To = "AI Search ($($names.aiSearch))";              Access = $summary.foundryProjectToSearch }
        [pscustomobject]@{ From = 'Foundry account';          To = "Container Registry ($($names.containerRegistry))"; Access = $summary.foundryAccountToAcr }
        [pscustomobject]@{ From = 'Container Apps workload';  To = "Container Registry ($($names.containerRegistry))"; Access = $summary.containerAppsToAcr }
        [pscustomobject]@{ From = 'Container Apps workload';  To = "Cosmos DB ($($names.cosmosDb))";               Access = $summary.containerAppsToCosmos }
    )
    $grants | Format-Table -AutoSize | Out-String | Write-Host
}
finally {
    Pop-Location
}
