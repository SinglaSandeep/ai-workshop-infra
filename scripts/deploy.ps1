<#
.SYNOPSIS
    Part A - Provision the shared workshop infrastructure into an EXISTING
    resource group that you select.

.DESCRIPTION
    Deploys infra/main.bicep into the resource group passed with -ResourceGroup.
    The resource group MUST already exist — this script never creates one.

    After a successful deployment it writes the outputs to
    .azure/main-outputs.json and records the selected subscription / resource
    group / location in .azure/deploy-config.json so the later scripts
    (load-data.ps1, grant-resource-access.ps1, grant-user-access.ps1) can find
    them.

    This script ONLY creates infrastructure. It does not load data and does not
    grant any access. See README.md for the full four-part flow.

.PARAMETER ResourceGroup
    REQUIRED. An existing resource group to deploy into.

.PARAMETER SubscriptionId
    Subscription to use. Defaults to the current Azure CLI account.

.PARAMETER Location
    Region recorded for the workshop (used by load-data.ps1). Defaults to
    primaryLocation in infra/main.parameters.json.

.EXAMPLE
    ./scripts/deploy.ps1 -ResourceGroup rg-zava-sandbox
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$Location,

    [Parameter(Mandatory = $false)]
    [string]$ParametersFile = 'infra/main.parameters.json',

    [Parameter(Mandatory = $false)]
    [string]$TemplateFile = 'infra/main.bicep',

    [Parameter(Mandatory = $false)]
    [string]$DeploymentName = 'workshop-infra'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

$projectRoot = Get-ProjectRoot
Push-Location $projectRoot
try {
    Write-Host '== Part A: provisioning shared workshop infrastructure =='

    # Ensure the Azure CLI is signed in.
    $account = az account show -o json 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($account -join ''))) {
        throw "The Azure CLI is not logged in. Run 'az login' first, then re-run ./scripts/deploy.ps1."
    }

    if (-not [string]::IsNullOrWhiteSpace($SubscriptionId)) {
        az account set --subscription $SubscriptionId | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Could not switch the Azure CLI to subscription '$SubscriptionId'. Run 'az login' against that subscription, then re-run ./scripts/deploy.ps1."
        }
    }
    $SubscriptionId = (az account show --query id -o tsv)

    # The resource group MUST already exist — this script never creates one.
    $exists = (az group exists --name $ResourceGroup -o tsv)
    if ($exists -ne 'true') {
        throw "Resource group '$ResourceGroup' does not exist in subscription '$SubscriptionId'. Create it (or select an existing one) and pass it with -ResourceGroup. This script never creates a resource group."
    }

    if ([string]::IsNullOrWhiteSpace($Location)) {
        $paramConfig = Get-Content $ParametersFile -Raw | ConvertFrom-Json
        $Location = $paramConfig.parameters.workshopConfig.value.primaryLocation
    }

    # Purge any soft-deleted Foundry accounts left over from a previous teardown
    # so the deterministic account names are free to be (re)created.
    Clear-SoftDeletedFoundryAccounts -ResourceGroup $ResourceGroup

    Write-Host "Deploying '$TemplateFile' into resource group '$ResourceGroup'..."
    $deploymentJson = az deployment group create `
        --resource-group $ResourceGroup `
        --name $DeploymentName `
        --template-file $TemplateFile `
        --parameters ('@' + $ParametersFile) `
        --only-show-errors -o json
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($deploymentJson -join ''))) {
        throw "Infrastructure deployment failed with exit code $LASTEXITCODE."
    }

    # Persist the deployment outputs for the later scripts. The shape matches
    # what load-data.ps1 / grant-*.ps1 expect (each output exposes a .value).
    $outputsDir = Join-Path $projectRoot '.azure'
    if (-not (Test-Path $outputsDir)) {
        New-Item -ItemType Directory -Path $outputsDir -Force | Out-Null
    }
    $outputs = ($deploymentJson | ConvertFrom-Json).properties.outputs
    ($outputs | ConvertTo-Json -Depth 20) | Set-Content -Path (Join-Path $outputsDir 'main-outputs.json') -Encoding utf8

    Save-DeployConfig -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -Location $Location

    Write-Host ''
    Write-Host "Infrastructure ready in resource group '$ResourceGroup'."
    Write-Host 'Next steps:'
    Write-Host '  Part B - load data:        ./scripts/load-data.ps1 -WorkshopPath <path-to-ai-agents-workshop>'
    Write-Host '  Part C - resource access:  ./scripts/grant-resource-access.ps1'
    Write-Host '  Part D - user access:      ./scripts/grant-user-access.ps1'
}
finally {
    Pop-Location
}
