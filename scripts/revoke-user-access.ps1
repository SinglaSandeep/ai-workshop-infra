<#
.SYNOPSIS
    Remove the participant access granted by grant-user-access.ps1 (Part D).

.DESCRIPTION
    Deletes the resource group Contributor role assignment for every principal
    in infra/user-access.parameters.json. Run this before scripts/destroy.ps1 if
    you want to revoke access while keeping the infrastructure, or just rely on
    destroy.ps1 (deleting the resource group also removes its assignments).

.EXAMPLE
    ./scripts/revoke-user-access.ps1
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $false)]
    [string]$UserAccessParametersFile = 'infra/user-access.parameters.json'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

$projectRoot = Get-ProjectRoot
Push-Location $projectRoot
try {
    $ResourceGroup = Resolve-ResourceGroup -ResourceGroup $ResourceGroup

    $subscriptionId = (az account show --query id -o tsv)
    $params = (Get-Content $UserAccessParametersFile -Raw | ConvertFrom-Json).parameters
    $users = $params.workshopUsers.value

    $resourceGroupRoleId = $params.userAccess.value.resourceGroup.roleDefinitionId

    $resourceGroupScope = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup"

    Write-Host '== Revoking participant access =='
    foreach ($user in $users) {
        if ([string]::IsNullOrWhiteSpace($user.objectId) -or $user.objectId -eq '00000000-0000-0000-0000-000000000000') {
            continue
        }

        az role assignment delete --assignee-object-id $user.objectId --role $resourceGroupRoleId --scope $resourceGroupScope --only-show-errors | Out-Null
        Write-Host "  revoked: $($user.displayName)"
    }

    Write-Host 'Participant access revoked.'
}
finally {
    Pop-Location
}
