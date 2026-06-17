<#
.SYNOPSIS
    Part A - Provision the shared workshop infrastructure with azd.

.DESCRIPTION
    Runs `azd up` against infra/main.bicep and then writes the deployment
    outputs to .azure/main-outputs.json so the later steps
    (load-data.ps1, grant-resource-access.ps1, grant-user-access.ps1) can read
    resource names and endpoints.

    This script ONLY creates infrastructure. It does not load data and does not
    grant any access. See README.md for the full four-part flow.

.EXAMPLE
    ./scripts/deploy.ps1
#>
param()

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

# Azure AI Foundry (Cognitive Services) accounts support SOFT DELETE. When the
# stack is torn down, the account name lingers in a soft-deleted state for days.
# Because this template generates deterministic account names from the resource
# group, a fresh `azd up` then fails with FlagMustBeSetForRestore. Purging any
# soft-deleted accounts that belong to the target resource group first makes the
# deployment idempotent and repeatable.
function Clear-SoftDeletedFoundryAccounts {
    param([string]$ResourceGroup)

    if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
        Write-Warning 'Resource group unknown; skipping soft-deleted Foundry cleanup.'
        return
    }

    Write-Host "Checking for soft-deleted Foundry (Cognitive Services) accounts in '$ResourceGroup'..."
    $deletedJson = az cognitiveservices account list-deleted -o json 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($deletedJson)) {
        return
    }

    $rgPattern = "/resourceGroups/$([regex]::Escape($ResourceGroup))/"
    $toPurge = @(($deletedJson | ConvertFrom-Json) | Where-Object { $_.id -match $rgPattern })
    if ($toPurge.Count -eq 0) {
        Write-Host '  None found.'
        return
    }

    foreach ($acct in $toPurge) {
        Write-Host "  Purging soft-deleted account '$($acct.name)' in '$($acct.location)'..."
        az cognitiveservices account purge `
            --name $acct.name `
            --resource-group $ResourceGroup `
            --location $acct.location `
            --only-show-errors | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "  Could not purge '$($acct.name)'. Purge it manually in the Azure portal, then re-run this script."
        }
    }
}

# azd and the Azure CLI (az) authenticate independently. It is common for
# `azd up` to succeed (so all resources get created) while `az` is either not
# logged in or pointed at a different subscription. When that happens the
# `az deployment group ...` calls below return nothing, and a PowerShell
# pipeline that pipes empty output into Set-Content silently creates NO file
# and raises NO error (true on both Windows PowerShell 5.1 and PowerShell 7).
# The result is a "successful" run with no main-outputs.json. Guard against it
# by aligning az with azd's subscription and checking every az exit code.
function Assert-AzCliContext {
    param([string]$SubscriptionId)

    $account = az account show -o json 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($account -join ''))) {
        throw "The Azure CLI is not logged in. Run 'az login' (and 'az account set --subscription <id>') so this script can read the deployment outputs, then re-run ./scripts/deploy.ps1."
    }

    if (-not [string]::IsNullOrWhiteSpace($SubscriptionId)) {
        $currentSub = ($account | ConvertFrom-Json).id
        if ($currentSub -ne $SubscriptionId) {
            Write-Host "Aligning Azure CLI subscription with azd ($SubscriptionId)..."
            az account set --subscription $SubscriptionId | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Could not switch the Azure CLI to subscription '$SubscriptionId'. Run 'az login' against that subscription, then re-run ./scripts/deploy.ps1."
            }
        }
    }
}

function Export-DeploymentOutputs {
    param(
        [string]$ResourceGroup,
        [string]$OutputPath
    )

    $deploymentsJson = az deployment group list --resource-group $ResourceGroup -o json
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($deploymentsJson -join ''))) {
        throw "Could not list deployments in resource group '$ResourceGroup' (az exit code $LASTEXITCODE). Confirm 'azd up' succeeded and that the Azure CLI is logged in to the same subscription as azd (az login / az account set --subscription <id>)."
    }

    $latestDeployment = @($deploymentsJson | ConvertFrom-Json) |
        Where-Object { $_ -and $_.name -and $_.properties -and $_.properties.outputs } |
        Sort-Object { $_.properties.timestamp } |
        Select-Object -Last 1

    $deploymentName = if ($latestDeployment) { $latestDeployment.name } else { $null }

    if ([string]::IsNullOrWhiteSpace($deploymentName)) {
        throw "Could not find a deployment with outputs in resource group '$ResourceGroup'. Did 'azd up' succeed?"
    }

    $outputsDir = Split-Path -Parent $OutputPath
    if (-not (Test-Path $outputsDir)) {
        New-Item -ItemType Directory -Path $outputsDir -Force | Out-Null
    }

    # Capture the outputs FIRST so a failed az call cannot leave us with a
    # missing/empty file and a silent exit-0.
    $outputsJson = az deployment group show --resource-group $ResourceGroup --name $deploymentName --query properties.outputs -o json
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($outputsJson -join ''))) {
        throw "Failed to read outputs for deployment '$deploymentName' in resource group '$ResourceGroup' (az exit code $LASTEXITCODE). The Azure CLI may not be logged in or may be pointed at a different subscription than azd."
    }

    Set-Content -Path $OutputPath -Value $outputsJson -Encoding utf8

    Write-Host "Deployment outputs written to $OutputPath"
}

$projectRoot = Get-ProjectRoot
Push-Location $projectRoot
try {
    Write-Host '== Part A: provisioning shared workshop infrastructure (azd up) =='

    # Purge any soft-deleted Foundry accounts left over from a previous teardown
    # so the deterministic account names are free to be (re)created.
    $preEnv = Get-AzdEnvValues
    $preResourceGroup = $preEnv['AZURE_RESOURCE_GROUP']
    if ([string]::IsNullOrWhiteSpace($preResourceGroup) -and -not [string]::IsNullOrWhiteSpace($preEnv['AZURE_ENV_NAME'])) {
        # azd's default resource group name is rg-<environment-name>.
        $preResourceGroup = "rg-$($preEnv['AZURE_ENV_NAME'])"
    }
    Clear-SoftDeletedFoundryAccounts -ResourceGroup $preResourceGroup

    azd up
    if ($LASTEXITCODE -ne 0) {
        throw "azd up failed with exit code $LASTEXITCODE."
    }

    $envValues = Get-AzdEnvValues
    $resourceGroup = $envValues['AZURE_RESOURCE_GROUP']
    if ([string]::IsNullOrWhiteSpace($resourceGroup)) {
        throw 'AZURE_RESOURCE_GROUP was not found in the azd environment.'
    }

    # azd just provisioned everything, but the steps below read the deployment
    # via the Azure CLI, which authenticates separately from azd. Make sure az is
    # logged in to the same subscription before we try to export the outputs.
    Assert-AzCliContext -SubscriptionId $envValues['AZURE_SUBSCRIPTION_ID']

    Export-DeploymentOutputs -ResourceGroup $resourceGroup -OutputPath (Join-Path $projectRoot '.azure/main-outputs.json')

    Write-Host ''
    Write-Host 'Infrastructure ready.'
    Write-Host 'Next steps:'
    Write-Host '  Part B - load data:        ./scripts/load-data.ps1 -WorkshopPath <path-to-ai-agents-workshop>'
    Write-Host '  Part C - resource access:  ./scripts/grant-resource-access.ps1'
    Write-Host '  Part D - user access:      ./scripts/grant-user-access.ps1'
}
finally {
    Pop-Location
}
