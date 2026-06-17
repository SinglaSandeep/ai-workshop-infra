<#
.SYNOPSIS
    Grant Day 2 Data Platform workshop participants their access (RBAC).

.DESCRIPTION
    Deploys infra/user-access-day2.bicep, which grants every principal listed in
    infra/user-access-day2.parameters.json:
      - Azure OpenAI  : Cognitive Services User (inference only, no deployments).
      - Azure ML      : AzureML Data Scientist (run experiments, no config changes).
      - Storage       : Storage Blob Data Contributor (read/write Lakehouse data).
      - Key Vault     : Key Vault Secrets User (read connection strings).
      - PostgreSQL    : Reader role (data plane access via SQL GRANT).

    Run this AFTER scripts/deploy.ps1 or azd up. Edit 
    infra/user-access-day2.parameters.json first to list the real Entra users 
    or groups and adjust access levels.

.PARAMETER ResourceGroup
    Target resource group. Defaults to the azd environment value.

.PARAMETER SubscriptionId
    Azure subscription ID. Optional.

.PARAMETER MainOutputsFile
    Path to main deployment outputs JSON file.

.PARAMETER UserAccessParametersFile
    Path to user access parameters JSON file.

.PARAMETER DeploymentName
    Name for the deployment.

.EXAMPLE
    ./scripts/grant-user-access-day2.ps1

.EXAMPLE
    ./scripts/grant-user-access-day2.ps1 -ResourceGroup "rg-workshop-prod"
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$MainOutputsFile = '.azure/main-outputs.json',

    [Parameter(Mandatory = $false)]
    [string]$UserAccessParametersFile = 'infra/user-access-day2.parameters.json',

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
    if (-not (Test-Path $MainOutputsFile)) {
        throw "Deployment outputs '$MainOutputsFile' not found. Run 'azd up' or './scripts/deploy.ps1' first."
    }
    if ($SubscriptionId) {
        az account set --subscription $SubscriptionId | Out-Null
    }

    # Extract Day 2 resource names from deployment outputs
    $outputs = Get-Content $MainOutputsFile -Raw | ConvertFrom-Json
    $names = $outputs.resourceNames.value

    # Build parameters for Day 2 resources (handle missing properties gracefully)
    $azureOpenAIName = if ($names.PSObject.Properties['azureOpenAI']) { $names.azureOpenAI } else { '' }
    $azureMLName = if ($names.PSObject.Properties['azureML']) { $names.azureML } else { '' }
    $storageName = if ($names.PSObject.Properties['storage']) { $names.storage } else { '' }
    $postgresName = if ($names.PSObject.Properties['postgres']) { $names.postgres } else { '' }
    $keyVaultName = if ($names.PSObject.Properties['keyVault']) { $names.keyVault } else { '' }

    Write-Host '== Day 2: Granting participant access to Data Platform resources (RBAC) ==' -ForegroundColor Cyan
    Write-Host ''
    Write-Host "Resource Group    : $ResourceGroup" -ForegroundColor Gray
    Write-Host "Azure OpenAI      : $azureOpenAIName" -ForegroundColor Gray
    Write-Host "Azure ML Workspace: $azureMLName" -ForegroundColor Gray
    Write-Host "Storage Account   : $storageName" -ForegroundColor Gray
    Write-Host "PostgreSQL Server : $postgresName" -ForegroundColor Gray
    Write-Host "Key Vault         : $keyVaultName" -ForegroundColor Gray
    Write-Host ''

    az deployment group create `
        --resource-group $ResourceGroup `
        --name $DeploymentName `
        --template-file 'infra/user-access-day2.bicep' `
        --parameters ('@' + $UserAccessParametersFile) `
        --parameters "azureOpenAIName=$azureOpenAIName" `
        --parameters "azureMLWorkspaceName=$azureMLName" `
        --parameters "storageAccountName=$storageName" `
        --parameters "postgresServerName=$postgresName" `
        --parameters "keyVaultName=$keyVaultName" `
        --only-show-errors | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "Day 2 participant access deployment failed with exit code $LASTEXITCODE. Check that every objectId in $UserAccessParametersFile is a real Entra user/group ID (not the 00000000... placeholder)."
    }

    Write-Host ''
    Write-Host '✅ Day 2 participant access granted successfully!' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Participants now have:' -ForegroundColor Cyan
    Write-Host '  - Azure OpenAI: Cognitive Services User (inference only)' -ForegroundColor Gray
    Write-Host '  - Azure ML: AzureML Data Scientist (run experiments)' -ForegroundColor Gray
    Write-Host '  - Storage: Storage Blob Data Contributor (read/write data)' -ForegroundColor Gray
    Write-Host '  - Key Vault: Key Vault Secrets User (read secrets)' -ForegroundColor Gray
    if ($postgresName) {
        Write-Host '  - PostgreSQL: Reader role (configure data plane via SQL GRANT)' -ForegroundColor Gray
    }
    Write-Host ''
}
finally {
    Pop-Location
}
