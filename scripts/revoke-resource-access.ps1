<#
.SYNOPSIS
    Remove the resource (service-to-service) access granted by
    grant-resource-access.ps1 (Part C).

.DESCRIPTION
    Deletes the Foundry -> Search and Foundry -> Container Registry role
    assignments. Run this before scripts/destroy.ps1 to revoke while keeping the
    infrastructure, or just rely on destroy.ps1 (deleting the resources also
    removes their assignments).

.EXAMPLE
    ./scripts/revoke-resource-access.ps1
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $false)]
    [string]$MainOutputsFile = '.azure/main-outputs.json',

    [Parameter(Mandatory = $false)]
    [string]$ResourceAccessParametersFile = 'infra/resource-access.parameters.json'
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
        throw "Deployment outputs '$MainOutputsFile' not found."
    }

    $subscriptionId = (az account show --query id -o tsv)
    $outputs = Get-Content $MainOutputsFile -Raw | ConvertFrom-Json
    $names = $outputs.resourceNames.value
    $principals = $outputs.managedIdentityPrincipals.value
    $grants = (Get-Content $ResourceAccessParametersFile -Raw | ConvertFrom-Json).parameters.resourceGrants.value

    $searchScope = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Search/searchServices/$($names.aiSearch)"
    $acrScope = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ContainerRegistry/registries/$($names.containerRegistry)"

    $projectPrincipals = @($principals.aiProjectPrincipalId, $principals.aiProjectSecondaryPrincipalId) | Where-Object { $_ }
    $accountPrincipals = @($principals.aiFoundryPrincipalId, $principals.aiFoundrySecondaryPrincipalId) | Where-Object { $_ }
    $workloadPrincipal = $principals.workloadIdentityPrincipalId

    Write-Host '== Revoking resource (service-to-service) access =='

    foreach ($principalId in $projectPrincipals) {
        if ($names.aiSearch) {
            az role assignment delete --assignee-object-id $principalId --role $grants.foundryProjectToSearch.roleDefinitionId --scope $searchScope --only-show-errors | Out-Null
        }
    }
    foreach ($principalId in $accountPrincipals) {
        if ($names.containerRegistry) {
            az role assignment delete --assignee-object-id $principalId --role $grants.foundryAccountToAcr.roleDefinitionId --scope $acrScope --only-show-errors | Out-Null
        }
    }
    if ($workloadPrincipal) {
        if ($names.containerRegistry) {
            az role assignment delete --assignee-object-id $workloadPrincipal --role $grants.containerAppsToAcr.roleDefinitionId --scope $acrScope --only-show-errors | Out-Null
        }
        if ($names.cosmosDb) {
            $assignments = az cosmosdb sql role assignment list --resource-group $ResourceGroup --account-name $names.cosmosDb -o json | ConvertFrom-Json
            foreach ($assignment in $assignments) {
                if ($assignment.principalId -eq $workloadPrincipal) {
                    az cosmosdb sql role assignment delete --resource-group $ResourceGroup --account-name $names.cosmosDb --role-assignment-id $assignment.id.Split('/')[-1] --yes --only-show-errors | Out-Null
                }
            }
        }
    }

    Write-Host 'Resource access revoked.'
}
finally {
    Pop-Location
}
