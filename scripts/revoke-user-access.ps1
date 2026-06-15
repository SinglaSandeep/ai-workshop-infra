<#
.SYNOPSIS
    Remove the participant access granted by grant-user-access.ps1 (Part D).

.DESCRIPTION
    Deletes the Cosmos DB data-plane assignments and the Foundry / Search role
    assignments for every principal in infra/user-access.parameters.json. Run
    this before scripts/destroy.ps1 if you want to revoke access while keeping
    the infrastructure, or just rely on destroy.ps1 (deleting the resources also
    removes their assignments).

.EXAMPLE
    ./scripts/revoke-user-access.ps1
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $false)]
    [string]$MainOutputsFile = '.azure/main-outputs.json',

    [Parameter(Mandatory = $false)]
    [string]$UserAccessParametersFile = 'infra/user-access.parameters.json'
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
    $names = (Get-Content $MainOutputsFile -Raw | ConvertFrom-Json -Depth 50).resourceNames.value
    $params = (Get-Content $UserAccessParametersFile -Raw | ConvertFrom-Json -Depth 50).parameters
    $users = $params.workshopUsers.value

    $azureAiUserRoleId = $params.userAccess.value.foundry.roleDefinitionId
    $searchIndexDataReaderRoleId = $params.userAccess.value.search.roleDefinitionId

    $projectScope = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.CognitiveServices/accounts/$($names.aiFoundry)/projects/$($names.aiProject)"
    $searchScope = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Search/searchServices/$($names.aiSearch)"
    $projectScopeSecondary = $names.aiProjectSecondary ? "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.CognitiveServices/accounts/$($names.aiFoundrySecondary)/projects/$($names.aiProjectSecondary)" : ''

    Write-Host '== Revoking participant access =='
    foreach ($user in $users) {
        if ([string]::IsNullOrWhiteSpace($user.objectId) -or $user.objectId -eq '00000000-0000-0000-0000-000000000000') {
            continue
        }

        if ($names.aiProject) {
            az role assignment delete --assignee-object-id $user.objectId --role $azureAiUserRoleId --scope $projectScope --only-show-errors | Out-Null
        }
        if ($projectScopeSecondary) {
            az role assignment delete --assignee-object-id $user.objectId --role $azureAiUserRoleId --scope $projectScopeSecondary --only-show-errors | Out-Null
        }
        if ($names.aiSearch) {
            az role assignment delete --assignee-object-id $user.objectId --role $searchIndexDataReaderRoleId --scope $searchScope --only-show-errors | Out-Null
        }
        if ($names.cosmosDb) {
            $assignments = az cosmosdb sql role assignment list --resource-group $ResourceGroup --account-name $names.cosmosDb -o json | ConvertFrom-Json
            foreach ($assignment in $assignments) {
                if ($assignment.principalId -eq $user.objectId) {
                    az cosmosdb sql role assignment delete --resource-group $ResourceGroup --account-name $names.cosmosDb --role-assignment-id $assignment.id.Split('/')[-1] --yes --only-show-errors | Out-Null
                }
            }
        }
        Write-Host "  revoked: $($user.displayName)"
    }

    Write-Host 'Participant access revoked.'
}
finally {
    Pop-Location
}
