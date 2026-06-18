<#
.SYNOPSIS
    Remove the resource (service / app) access granted by
    grant-resource-access.ps1 (Part C).

.DESCRIPTION
    Deletes the resource group role assignment for every service principal /
    app listed in infra/resource-access.parameters.json. Run this before
    scripts/destroy.ps1 to revoke while keeping the infrastructure, or just rely
    on destroy.ps1 (deleting the resource group also removes its assignments).

.EXAMPLE
    ./scripts/revoke-resource-access.ps1
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $false)]
    [string]$ResourceAccessParametersFile = 'infra/resource-access.parameters.json'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

$projectRoot = Get-ProjectRoot
Push-Location $projectRoot
try {
    $ResourceGroup = Resolve-ResourceGroup -ResourceGroup $ResourceGroup

    $subscriptionId = (az account show --query id -o tsv)
    $params = (Get-Content $ResourceAccessParametersFile -Raw | ConvertFrom-Json).parameters
    $servicePrincipals = $params.servicePrincipals.value
    $roleId = $params.resourceAccess.value.roleDefinitionId

    $resourceGroupScope = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup"

    Write-Host '== Revoking resource (service / app) access =='
    foreach ($sp in $servicePrincipals) {
        if ([string]::IsNullOrWhiteSpace($sp.objectId) -or $sp.objectId -eq '00000000-0000-0000-0000-000000000000') {
            continue
        }
        az role assignment delete --assignee-object-id $sp.objectId --role $roleId --scope $resourceGroupScope --only-show-errors | Out-Null
        Write-Host "  revoked: $($sp.displayName)"
    }

    Write-Host 'Resource access revoked.'
}
finally {
    Pop-Location
}
