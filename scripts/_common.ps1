# Shared helpers for the workshop infra scripts.
#
# These scripts deploy into an EXISTING, user-selected resource group (they
# never create one). deploy.ps1 records the selected subscription / resource
# group / location in .azure/deploy-config.json so the later scripts can find
# them without azd.

function Get-ProjectRoot {
    Split-Path -Parent $PSScriptRoot
}

function Get-DeployConfigPath {
    Join-Path (Get-ProjectRoot) '.azure/deploy-config.json'
}

function Save-DeployConfig {
    param(
        [Parameter(Mandatory = $true)] [string]$SubscriptionId,
        [Parameter(Mandatory = $true)] [string]$ResourceGroup,
        [Parameter(Mandatory = $true)] [string]$Location
    )
    $path = Get-DeployConfigPath
    $dir = Split-Path -Parent $path
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [pscustomobject]@{
        subscriptionId = $SubscriptionId
        resourceGroup  = $ResourceGroup
        location       = $Location
    } | ConvertTo-Json | Set-Content -Path $path -Encoding utf8
}

function Get-DeployConfig {
    $path = Get-DeployConfigPath
    if (Test-Path $path) {
        return Get-Content $path -Raw | ConvertFrom-Json
    }
    return $null
}

# Resolve the target resource group: an explicit -ResourceGroup wins, otherwise
# fall back to the one recorded by deploy.ps1. Never invents or creates a group.
function Resolve-ResourceGroup {
    param([string]$ResourceGroup)
    if (-not [string]::IsNullOrWhiteSpace($ResourceGroup)) {
        return $ResourceGroup
    }
    $cfg = Get-DeployConfig
    if ($cfg -and -not [string]::IsNullOrWhiteSpace($cfg.resourceGroup)) {
        return $cfg.resourceGroup
    }
    throw 'Resource group not specified. Pass -ResourceGroup, or run ./scripts/deploy.ps1 first (it records the selected resource group in .azure/deploy-config.json).'
}

# Purge any soft-deleted Foundry (Cognitive Services) accounts that belonged to
# the resource group, so their deterministic names are free for the next deploy.
function Clear-SoftDeletedFoundryAccounts {
    param([string]$ResourceGroup)

    if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
        return
    }

    $deletedJson = az cognitiveservices account list-deleted -o json 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($deletedJson)) {
        return
    }

    $rgPattern = "/resourceGroups/$([regex]::Escape($ResourceGroup))/"
    $toPurge = @(($deletedJson | ConvertFrom-Json) | Where-Object { $_.id -match $rgPattern })
    foreach ($acct in $toPurge) {
        Write-Host "Purging soft-deleted Foundry account '$($acct.name)' in '$($acct.location)'..."
        az cognitiveservices account purge `
            --name $acct.name `
            --resource-group $ResourceGroup `
            --location $acct.location `
            --only-show-errors | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Could not purge '$($acct.name)'. Purge it manually in the Azure portal."
        }
    }
}
