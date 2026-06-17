<#
.SYNOPSIS
    Deploys Day 2 (Data) slim infrastructure into the customer's Azure
    subscription / resource group.

.DESCRIPTION
    Runs `az deployment group create` against infra/main-day2.bicep, then
    writes a workshop .env file with the resource endpoints labs 01-03 need.

    Day 1 (Sandeep — Agentic AI: Foundry, Cosmos, AI Search, ContainerApps,
    ACR, AOAI) is deployed separately. This script targets the SAME RG that
    holds Sandeep's resources.

.PARAMETER ResourceGroupName
    Existing resource group (Sandeep's Day 1 RG). The script will not
    create it. Default: 'rg-pepsi-day2'.

.PARAMETER Location
    Azure region. Must support Fabric, Azure SQL VECTOR, and Purview.
    Default: 'eastus2' (or the resource group's location if the RG exists
    and no explicit value is passed).

.PARAMETER SqlLocation
    Azure region for the SQL server (override when -Location is throttled).
    Default: 'centralus' so SQL never lands in a throttled eastus2 quota.

.PARAMETER FabricAdminObjectId
    UPN (preferred) or Entra Object ID of the user/group to be Fabric
    capacity admin. Default: signed-in user's UPN from `az account show`.

.PARAMETER SqlAadAdminLogin
    UPN of the Entra admin for Azure SQL (Entra-only auth).
    Default: signed-in user's UPN from `az account show`.

.PARAMETER SqlAadAdminObjectId
    Entra Object ID matching SqlAadAdminLogin.
    Default: signed-in user's Object ID from `az ad signed-in-user show`.

.PARAMETER SkipFabric
    Skip Fabric capacity provisioning (use if a shared capacity already exists).

.PARAMETER SkipSql
    Skip Azure SQL provisioning.

.PARAMETER SkipPurview
    Skip Purview provisioning.

.EXAMPLE
    # Simplest invocation - uses signed-in user as Fabric/SQL admin,
    # rg-pepsi-day2 as the resource group, eastus2 + centralus as regions.
    az login
    ./scripts/deploy-day2.ps1

.EXAMPLE
    # Explicit override
    ./scripts/deploy-day2.ps1 -ResourceGroupName rg-pepsi-shared -Location eastus2 `
        -FabricAdminObjectId admin@contoso.com `
        -SqlAadAdminLogin admin@contoso.com `
        -SqlAadAdminObjectId 4c517221-2844-4edd-84e1-8a3f5f4bb55f
#>
[CmdletBinding()]
param(
    [string] $ResourceGroupName = 'rg-pepsi-day2',
    [string] $Location          = 'eastus2',
    [string] $SqlLocation       = 'centralus',
    [string] $FabricAdminObjectId,
    [string] $SqlAadAdminLogin,
    [string] $SqlAadAdminObjectId,
    [string] $WorkshopName = 'pepsiws',
    [string] $EnvironmentName = 'day2',
    [ValidateSet('F2','F4','F8','F16','F32','F64')] [string] $FabricSku = 'F2',
    [string] $SqlDatabaseName = 'vectordb',
    [switch] $SkipFabric,
    [switch] $SkipSql,
    [switch] $SkipPurview
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$bicep = Join-Path $projectRoot 'infra/main-day2.bicep'

if (-not (Test-Path $bicep)) {
    throw "Cannot find $bicep. Run from the data-workshop-infra repo root."
}

# ---------- Auto-resolve identity defaults from `az` ----------
$needSignedInUpn = (-not $FabricAdminObjectId) -or (-not $SqlAadAdminLogin)
$needSignedInOid = (-not $SqlAadAdminObjectId)

if ($needSignedInUpn) {
    $signedInUpn = az account show --query user.name -o tsv 2>$null
    if (-not $signedInUpn) { throw "Could not detect signed-in user. Run 'az login' first or pass -FabricAdminObjectId / -SqlAadAdminLogin." }
}
if ($needSignedInOid) {
    $signedInOid = az ad signed-in-user show --query id -o tsv 2>$null
    if (-not $signedInOid) { throw "Could not detect signed-in Object ID. Run 'az login' or pass -SqlAadAdminObjectId." }
}
if (-not $FabricAdminObjectId) { $FabricAdminObjectId = $signedInUpn; Write-Host "Defaulting -FabricAdminObjectId  to signed-in UPN '$FabricAdminObjectId'" }
if (-not $SqlAadAdminLogin)    { $SqlAadAdminLogin    = $signedInUpn; Write-Host "Defaulting -SqlAadAdminLogin     to signed-in UPN '$SqlAadAdminLogin'" }
if (-not $SqlAadAdminObjectId) { $SqlAadAdminObjectId = $signedInOid; Write-Host "Defaulting -SqlAadAdminObjectId  to signed-in OID '$SqlAadAdminObjectId'" }

# Confirm RG exists (auto-create if missing - first-time customer flow)
$rgExists = az group exists --name $ResourceGroupName 2>$null
if ($rgExists -ne 'true') {
    Write-Host "Resource group '$ResourceGroupName' not found - creating it in '$Location'..."
    az group create --name $ResourceGroupName --location $Location --output none
    if ($LASTEXITCODE -ne 0) { throw "Failed to create resource group '$ResourceGroupName'." }
} else {
    # Honour the RG's actual location unless caller explicitly overrode it.
    $rgLocation = az group show --name $ResourceGroupName --query location -o tsv
    if ($PSBoundParameters.ContainsKey('Location') -eq $false -and $rgLocation) {
        $Location = $rgLocation
    }
}

$deployName = "pepsi-day2-$(Get-Date -Format 'yyyyMMddHHmmss')"

Write-Host "== Deploying Day 2 slim infra =="
Write-Host "  Resource group : $ResourceGroupName"
Write-Host "  Location       : $Location"
Write-Host "  SQL Location   : $SqlLocation"
Write-Host "  Fabric admin   : $FabricAdminObjectId"
Write-Host "  SQL Entra admin: $SqlAadAdminLogin ($SqlAadAdminObjectId)"
Write-Host "  Skip flags     : Fabric=$($SkipFabric.IsPresent) SQL=$($SkipSql.IsPresent) Purview=$($SkipPurview.IsPresent)"
Write-Host ""

az deployment group create `
    --resource-group $ResourceGroupName `
    --name $deployName `
    --template-file $bicep `
    --parameters `
        workshopName=$WorkshopName `
        environmentName=$EnvironmentName `
        location=$Location `
        sqlLocation=$SqlLocation `
        enableFabricCapacity=$([bool](-not $SkipFabric.IsPresent)) `
        fabricSkuName=$FabricSku `
        fabricAdminObjectId=$FabricAdminObjectId `
        enableSqlVector=$([bool](-not $SkipSql.IsPresent)) `
        sqlAadAdminLogin=$SqlAadAdminLogin `
        sqlAadAdminObjectId=$SqlAadAdminObjectId `
        sqlDatabaseName=$SqlDatabaseName `
        enablePurview=$([bool](-not $SkipPurview.IsPresent)) `
    --output none
if ($LASTEXITCODE -ne 0) {
    throw "Deployment failed with exit $LASTEXITCODE."
}

# Capture outputs
$outputsJson = az deployment group show `
    --resource-group $ResourceGroupName `
    --name $deployName `
    --query properties.outputs `
    -o json
$outputs = $outputsJson | ConvertFrom-Json

# Write outputs to .azure/main-day2-outputs.json for downstream scripts
$outDir = Join-Path $projectRoot '.azure'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$outputsJson | Set-Content -Path (Join-Path $outDir 'main-day2-outputs.json') -Encoding utf8

# Write a workshop .env helper
$envFile = Join-Path $outDir 'workshop-day2.env'
@"
# PepsiCo MSFT Workshop — Day 2 (Data) endpoints
# Generated $(Get-Date -Format 'u') from deployment '$deployName'
AZURE_RESOURCE_GROUP=$ResourceGroupName
AZURE_LOCATION=$Location
FABRIC_CAPACITY_NAME=$($outputs.fabricCapacityName.value)
SQL_SERVER_FQDN=$($outputs.sqlServerFqdn.value)
SQL_DATABASE_NAME=$($outputs.sqlDatabaseName.value)
PURVIEW_ACCOUNT_NAME=$($outputs.purviewAccountName.value)
PURVIEW_ATLAS_ENDPOINT=$($outputs.purviewAtlasEndpoint.value)
"@ | Set-Content -Path $envFile -Encoding utf8

Write-Host ""
Write-Host "Day 2 infrastructure ready."
Write-Host "  Outputs : $outDir/main-day2-outputs.json"
Write-Host "  Env file: $envFile"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1) Run the SQL VECTOR setup:    sqlcmd -S $($outputs.sqlServerFqdn.value) -d $($outputs.sqlDatabaseName.value) -G -i Allfiles/lab03/setup-sql-vector.sql"
Write-Host "  2) Grant participant access:    ./scripts/grant-user-access-day2.ps1 -ResourceGroupName $ResourceGroupName"
Write-Host "  3) Add the Fabric capacity to a workspace and assign attendees as Workspace Contributors (Fabric portal)."
